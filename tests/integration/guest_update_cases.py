"""Actual Core update/rollback with a loopback-only pinned HTTPS transport."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import socket
import socketserver
import ssl
import subprocess
import threading
import time
from typing import Callable
from urllib.parse import unquote


def require(condition: bool, label: str) -> None:
    if not condition:
        raise RuntimeError(label)


class AssetServer(socketserver.ThreadingTCPServer):
    """Accept only GitHub CONNECT and the two fixed public release paths."""
    allow_reuse_address=False
    daemon_threads=True
    block_on_close=False

    def __init__(self, payloads: dict[str,bytes], context: ssl.SSLContext):
        self.payloads=payloads
        self.context=context
        self.requests: list[str]=[]
        self.errors: list[str]=[]
        self.lock=threading.Lock()
        self.connections: dict[socket.socket,socket.socket]={}
        self.request_threads: list[threading.Thread]=[]
        super().__init__(('127.0.0.1',0),AssetRequest)

    def process_request(self, request, client_address):
        with self.lock:
            if len(self.request_threads)>=8:
                request.close()
                self.errors.append('asset connection budget exceeded')
                return
            self.connections[request]=request
            thread=threading.Thread(target=self.process_request_thread,
                                    args=(request,client_address),daemon=True)
            self.request_threads.append(thread)
        thread.start()

    def replace_connection(self, original: socket.socket, current: socket.socket) -> None:
        with self.lock:
            if original not in self.connections:
                current.close()
                raise RuntimeError('asset connection deadline expired')
            self.connections[original]=current

    def retire_connection(self, original: socket.socket) -> None:
        with self.lock:
            current=self.connections.pop(original,None)
        if current is not None:
            try:
                current.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            current.close()

    def server_close(self):
        # Closing a listening socket alone does not wake an accepted TLS/read
        # thread. Retire only registered own sockets, then bound all joins.
        socketserver.TCPServer.server_close(self)
        with self.lock:
            connections=list(self.connections)
            threads=list(self.request_threads)
        for connection in connections:
            self.retire_connection(connection)
        deadline=time.monotonic()+2
        for thread in threads:
            thread.join(timeout=max(0,deadline-time.monotonic()))
        require(not any(t.is_alive() for t in threads),'asset request threads did not retire')

    def handle_error(self, _request, _client_address):
        # Exception text can contain request bytes; retain only a fixed label.
        with self.lock:
            self.errors.append('asset request failed')


class AssetRequest(socketserver.StreamRequestHandler):
    def headers(self, stream) -> bytes:
        first=stream.readline(8193)
        require(0<len(first)<=8192,'asset request line bound')
        total=len(first)
        for _ in range(100):
            line=stream.readline(8193)
            total+=len(line)
            require(line and len(line)<=8192 and total<=65536,'asset header bound')
            if line in (b'\r\n',b'\n'):
                return first.rstrip(b'\r\n')
        raise RuntimeError('asset header count bound')

    def handle(self):
        timer=threading.Timer(20,self.server.retire_connection,args=(self.request,))
        timer.daemon=True
        timer.start()
        try:
            self.handle_asset()
        finally:
            timer.cancel()
            self.server.retire_connection(self.request)

    def handle_asset(self):
        self.request.settimeout(20)
        require(self.headers(self.rfile)==b'CONNECT github.com:443 HTTP/1.1','unexpected proxy destination')
        self.wfile.write(b'HTTP/1.1 200 Connection Established\r\n\r\n')
        self.wfile.flush()
        with self.server.context.wrap_socket(self.request,server_side=True,do_handshake_on_connect=False) as connection:
            self.server.replace_connection(self.request,connection)
            connection.do_handshake()
            with connection.makefile('rb') as stream:
                request=self.headers(stream).decode('ascii').split(' ')
            require(len(request)==3 and request[0]=='GET' and request[2]=='HTTP/1.1','unexpected asset method')
            path=unquote(request[1])
            require(path in self.server.payloads,'unexpected asset path')
            body=self.server.payloads[path]
            connection.sendall(('HTTP/1.1 200 OK\r\nContent-Length: '+str(len(body))+
                                '\r\nConnection: close\r\nContent-Type: application/octet-stream\r\n\r\n').encode('ascii'))
            for offset in range(0,len(body),1024*1024):
                connection.sendall(body[offset:offset+1024*1024])
            with self.server.lock:
                self.server.requests.append(path)


def run_updates(logs: Path, env: dict[str,str], call: Callable,
                core_state: Callable, binding: Callable, links_ready: Callable,
                passed: list[str], *, inject_start_failure: bool = False,
                recovery_failure_core: str | None = None) -> None:
    mapping=[int(x) for x in Path('/proc/self/uid_map').read_text().split()]
    require(os.geteuid()==0 and len(mapping)==3 and mapping[0]==0 and mapping[1]>0
            and mapping[2]==65536,'updates require isolated mapped guest root')
    require(Path('/run/host/container-manager').read_text().strip()=='systemd-nspawn',
            'updates require native guest')
    require({p.name for p in Path('/sys/class/net').iterdir()}=={'lo'},'updates require private lo')
    target=json.loads(Path('/opt/pnm-update-targets.json').read_text())
    prior=json.loads(Path('/opt/pnm-test-versions.json').read_text())
    assets=Path('/opt/pnm-update-assets')
    payloads={}
    paths={}
    for core in ('xray','hysteria2'):
        pin=target[core]
        body=(assets/pin['filename']).read_bytes()
        require(len(body)==pin['size'] and hashlib.sha256(body).hexdigest()==pin['sha256'],
                'update fixture asset differs from frozen pin')
        path=('/XTLS/Xray-core/releases/download/'+pin['version']+'/Xray-linux-64.zip'
              if core=='xray' else '/apernet/hysteria/releases/download/app/'+pin['version']+'/hysteria-linux-amd64')
        paths[core]=path
        payloads[path]=body
    certificate=logs/'asset-server.crt'
    key=logs/'asset-server.key'
    generated=subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1',
        '-subj','/CN=github.com','-addext','subjectAltName=DNS:github.com',
        '-keyout',str(key),'-out',str(certificate)],capture_output=True,timeout=15)
    require(generated.returncode==0,'asset fixture certificate generation failed')
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version=ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(str(certificate),str(key))
    server=AssetServer(payloads,context)
    worker=threading.Thread(target=server.serve_forever,name='pnm-private-asset-server')
    original_env=dict(env)
    versions=Path('/etc/pnm/versions.conf')
    binaries={'xray':'/usr/local/bin/xray','hysteria2':'/usr/local/bin/hysteria'}
    prefix={'xray':'XRAY','hysteria2':'HY2'}

    def state(core: str) -> dict:
        result=core_state(core)
        previous={}
        for name in ('previous','previous.env'):
            path=Path('/var/lib/pnm/cores')/core/name
            require(not path.is_symlink(),'unexpected previous-state symlink')
            if path.exists():
                info=path.stat()
                previous[name]=(hashlib.sha256(path.read_bytes()).hexdigest(),
                                info.st_mode,info.st_uid,info.st_gid)
            else:
                previous[name]=None
        result['previous']=previous
        return result

    def actual_version(core: str) -> str:
        result=subprocess.run([binaries[core],'version'],capture_output=True,text=True,timeout=10)
        require(result.returncode==0,'installed binary version command failed')
        found=re.search(r'(?m)^Xray (\d+\.\d+\.\d+)' if core=='xray'
                        else r'(?m)^Version:\s*v?(\d+\.\d+\.\d+)',result.stdout+result.stderr)
        require(found is not None,'installed version is not recognizable')
        return found.group(1)

    def approve(core: str, checksum: str) -> None:
        text=versions.read_text()
        for name,value in ((prefix[core]+'_VERSION',target[core]['version']),
                           (prefix[core]+'_SHA256',checksum)):
            text,count=re.subn(r'(?m)^'+name+r'=.*$',lambda _match:name+'='+value,text)
            require(count==1,'approval fixture field missing')
        versions.write_text(text)

    def failed_start(operation: str, core: str, peer: str, baseline: dict,
                     peer_before: dict, version: str) -> dict:
        from guest_start_fault import start_fault
        transactions=set(Path('/var/lib/pnm/transactions').iterdir())
        with start_fault(core) as fault:
            result=call(operation+'-start-failure-'+core,[operation,core],accepted=(1,))
            require(('Core '+operation+' failed during service restart (rc=1); previous Core state was restored.').encode() in result.stderr,
                    'Core failure/recovery cause differs from start fixture')
            require(fault['attempts']==2 and fault['rejected']==1,'real failure and compensation starts were not both observed')
            recovered=state(core)
            require(recovered['resources']==baseline['resources'] and recovered['previous']==baseline['previous'],
                    'start failure did not restore binary/config/previous resources')
            require(actual_version(core)==version and recovered['invocation']!=baseline['invocation'],
                    'start recovery did not activate the previous real version')
            require(state(peer)==peer_before,'start failure compensation changed peer Core')
            binding(core)
            links_ready(operation+'-start-recovered-links-'+core)
            health=json.loads(call(operation+'-start-recovered-health-'+core,
                                   ['--json','check'],accepted=(0,1,2)).stdout)
            require(not [x for x in health['checks'] if x['status'] in ('FAIL','UNKNOWN') and x['id']!='time_sync'],
                    'recovered Core local health failed')
            created=set(Path('/var/lib/pnm/transactions').iterdir())-transactions
            require(len(created)==1,'start failure created unexpected transactions')
            journal=(created.pop()/'journal.tsv').read_text().splitlines()
            rows=[line.split('\t',2) for line in journal]
            events=[row[1] for row in rows]
            require(any(row[1:]==['WRITE','label=core_binary'] for row in rows)
                    and 'ROLLBACK_COMPLETE' in events and events[-1]=='ROLLED_BACK'
                    and 'RECOVERY_REQUIRED' not in events,'start failure did not complete binary compensation')
        passed.append('actual '+core+' '+operation+' startup failure restores resources and confirmed service evidence')
        return state(core)

    try:
        worker.start()
        env.update({'https_proxy':'http://127.0.0.1:'+str(server.server_address[1]),
                    'CURL_CA_BUNDLE':str(certificate),'NO_PROXY':''})
        for core in ('xray','hysteria2'):
            peer='hysteria2' if core=='xray' else 'xray'
            binary=binaries[core]
            old=state(core)
            peer_before=state(peer)
            require(actual_version(core)==prior[core]['version'].removeprefix('v'),
                    'initial Core is not the distinct previous version')
            transactions=set(Path('/var/lib/pnm/transactions').iterdir())
            approve(core,'0'*64)
            before_requests=server.requests.count(paths[core])
            call('update-bad-checksum-'+core,['update',core],accepted=(78,))
            require(server.requests.count(paths[core])==before_requests+1,'checksum refusal did not fetch the frozen asset')
            require(state(core)==old and state(peer)==peer_before,'checksum refusal changed a Core')
            require(transactions==set(Path('/var/lib/pnm/transactions').iterdir()),'checksum refusal began publication transaction')
            passed.append('actual '+core+' checksum refusal preserves both Cores before publication')

            approve(core,target[core]['sha256'])
            if inject_start_failure:
                old=failed_start('update',core,peer,old,peer_before,prior[core]['version'].removeprefix('v'))
            call('update-'+core,['update',core,'--version',target[core]['version']])
            updated=state(core)
            require(actual_version(core)==target[core]['version'].removeprefix('v'),'update did not change real binary version')
            require(old['resources'][binary][0]!=updated['resources'][binary][0] and old['invocation']!=updated['invocation'],'update did not activate distinct binary')
            require(all(v==updated['resources'][p] for p,v in old['resources'].items() if p!=binary),'update changed configuration or credentials')
            require(state(peer)==peer_before,'update changed peer Core')
            previous=Path('/var/lib/pnm/cores')/core/'previous'
            require(hashlib.sha256(previous.read_bytes()).hexdigest()==old['resources'][binary][0],'previous binary differs from actual baseline')
            binding(core)
            links_ready('links-updated-'+core)
            passed.append('actual '+core+' distinct-version update preserves peer and applied binding')

            if inject_start_failure:
                updated=failed_start('rollback',core,peer,updated,peer_before,target[core]['version'].removeprefix('v'))

            call('rollback-'+core,['rollback',core])
            reverted=state(core)
            require(actual_version(core)==prior[core]['version'].removeprefix('v') and reverted['resources']==old['resources'],'rollback did not restore previous binary/resources')
            require(reverted['invocation']!=updated['invocation'] and state(peer)==peer_before,'rollback did not isolate service replacement')
            binding(core)
            links_ready('links-rollback-'+core)
            passed.append('actual '+core+' rollback restores previous version without changing peer')

            call('rollback-forward-'+core,['rollback',core])
            forward=state(core)
            require(actual_version(core)==target[core]['version'].removeprefix('v') and forward['resources']==updated['resources'],'rollback swap did not restore updated resources')
            require(forward['invocation']!=reverted['invocation'] and state(peer)==peer_before,'rollback swap changed peer or retained stale invocation')
            binding(core)
            links_ready('links-rollback-forward-'+core)
            passed.append('actual '+core+' rollback swap forward retains confirmed links and peer')
        expected_fetches=3 if inject_start_failure else 2
        require(all(server.requests.count(paths[c])==expected_fetches for c in paths),'unexpected asset fetch count')
    finally:
        env.clear()
        env.update(original_env)
        if worker.ident is not None:
            server.shutdown()
        server.server_close()
        if worker.ident is not None:
            worker.join(timeout=2)
    require(not worker.is_alive() and not server.errors,'asset fixture failed or did not retire')
    report=json.loads(call('check-updated',['--json','check'],accepted=(0,1,2)).stdout)
    require(not [x for x in report['checks'] if x['status'] in ('FAIL','UNKNOWN') and x['id']!='time_sync'],
            'final updated Core health failed')
    if recovery_failure_core is not None:
        from guest_recovery_cases import run_core_recovery_failure
        run_core_recovery_failure(call,state,recovery_failure_core,passed)
