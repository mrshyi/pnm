# PNM Phase 3 验收设计

日期：2026-10-22。对应源码基线：`7a8dfe134f0c07e7ba16d740eb0e3c54db53b9ec`。

**状态：验收计划；L1 已有本地执行记录，L2/L3 仍待执行。** 对应 [实施前评估](IMPLEMENTATION_ASSESSMENT.md) 和 [部署事务设计](DEPLOYMENT_TRANSACTION_DESIGN.md)。初次文档审计的 Linux 环境阻塞已解除；第 6 节记录后续本地执行范围，不代表整份矩阵已通过。

## 1. 分层证据与环境

| 层级 | 环境 / 方法 | 可以证明 | 不可替代 |
|---|---|---|---|
| L0 | 当前 Windows 工作区、源码与测试检查、文档检查 | 分支存在、静态缺口、设计可追踪 | Bash 执行、真实权限及服务行为 |
| L1 | Linux Bash + 既有 mock/临时目录测试 | 返回码、步骤、状态记录、文件变更和注入分支 | systemd、真实 Core、reboot、公网握手 |
| L2 | 可丢弃的 Debian 13 amd64/systemd VM | root/账户/权限、真实 unit、监听、恢复、reboot | 其他发行版矩阵及公网客户端连通 |
| L3 | 受控外部 Xray/HY2 客户端 | 相应网络条件下真实协议握手和传输 | 服务故障补偿和其他网络条件 |

README 声明支持 Debian 12/13、Ubuntu 22.04/24.04 amd64。Debian 13 是首轮集成基线；其他发行版未执行就保留未验证，不能仅靠 os-release fixture 宣称整个平台验收完成。

前置工具根据 Makefile、tests 和实际调用链确认：Bash、make、ShellCheck、Python 3、zip/unzip、tar、flock、OpenSSL、curl、sha256sum、ss、systemctl/systemd-analyze、账户工具、runuser 及标准 coreutils。测试资产必须是可公开的固定 fixture 或批准的 Core 版本，不使用生产 Secret。

## 2. 仓库检查命令

仅在准备好的 Linux 测试工作区执行，保留每个命令的独立退出码；任一步失败先定位，不用筛掉 ShellCheck 规则后的结果替代原门禁。

```bash
make check
make shellcheck
make release-check
```

`make check` 包含 syntax/security-scan/test；`make release-check` 再次调用 check，不能把两次执行统计为更多独立用例。当前 CI 在 ubuntu-latest 配置了这三个命令，但本轮没有读取任何 CI 运行结果。

无需为纯文档增加业务测试；实施 S1～S5 时扩展现有测试文件，用可验证的前后状态断言覆盖缺口，不只检查函数调用次数。

## 3. 故障注入矩阵

所有注入只用于 L1 或可丢弃 L2。表中“候选”指当前待应用的一组资源；失败后均须同时验证文件、身份、服务、applied 状态及敏感输出，而非只检查非零退出码。

| ID | 场景 / 注入点 | 核心断言 | 层级 |
|---|---|---|---|
| T-01 | 全新节点，固定资产完整安装 | 两 Core 健康；Secret 和 TLS 权限正确；唯一提交证据；configured=yes；链接状态 ready | L1/L2 |
| T-02 | 已有有效 Secret/TLS 重试 | 凭据字节和证书 pin 不旋转；损坏已有凭据明确拒绝且不覆盖 | L1/L2 |
| T-03 | 缺工具、缺 SHA、下载错误/摘要不符/坏 ZIP | 在对应变更前失败；原管理资源无变化；不伪报零写入审计目录 | L1/L2 |
| T-04 | 自定义两端口；目标端口占用、默认端口被无关进程占用 | 检查配置端口；拒绝未知占用；无关默认端口不误阻止 | L1/L2 |
| T-05 | root 别名、目标/祖先 symlink、目录元数据操作 | 写入/chmod/chown 前拒绝；外部哨兵文件/目录及 `/` 元数据不变 | L1/L2 |
| T-06 | 文件原 UID/GID/mode 非默认；原文件缺失 | 正常补偿恢复字节和数字身份/权限；缺失状态恢复；不按固定属主掩盖缺口 | L1/L2 |
| T-07 | mkdir/chmod 后失败；既有目录或新建目录被外部写入 | 既有目录元数据恢复；仅 rmdir 本次创建的空目录；不递归清理用户内容 | L1/L2 |
| T-08 | 账户创建中断、已有有效账户、删除账户/组失败 | 收据可识别 INTENT；已有身份不删；依赖未解除时不删组；失败保留恢复要求 | L1/L2 |
| T-09 | Xray lifecycle 失败，HY2 尚未开始 | 原资源和服务基线恢复；未触及阶段无额外副作用；无部署提交 | L1/L2 |
| T-10 | HY2 lifecycle 失败，Xray 已激活 | 两 Core 回到各自基线，Secret/config/unit/applied 无混合代次 | L1/L2 |
| T-11 | post-health：服务 active 但无 TCP/UDP 监听 | 整次未提交并恢复；不能只断言 restore_service 被调用 | L1/L2 |
| T-12 | TLS/SNI/pin、owner/mode 或 hysteria 实际读权限错误 | 健康门控失败；输出不含密钥/密码；恢复原权限与状态 | L1/L2 |
| T-13 | applied 写入或 node configured 标记失败 | node 和两 applied 记录均回到一致的恢复状态；不留下 configured=yes | L1/L2 |
| T-14 | 外层期限超时、最后一次健康失败 | 发生在唯一提交之前；全部补偿；允许干净重试或明确恢复要求 | L1/L2 |
| T-15 | COMMIT_INTENT / marker 创建、写入、rename 失败 | 无有效提交；统一恢复；原错误和恢复错误分别记录 | L1/L2 |
| T-16 | marker 成功后派生收据或日志/清理失败 | 仍报告已提交及警告；不因派生信息失败返回普通部署失败 | L1/L2 |
| T-17 | marker/清单损坏或发布后同步失败 | 不猜测已提交/已回滚；非零及恢复要求；后续写操作被拦截 | L1/L2 |
| T-18 | 恢复时文件内容或元数据被其他操作者改变 | 不覆盖漂移；保留证据；不得伪报完整回滚 | L1/L2 |
| T-19 | INT/TERM；阶段间 SIGKILL；VM reboot | 可捕获信号尽力补偿；不可捕获中断后由磁盘识别未决状态，不依赖全局数组 | L2 |
| T-20 | 并发 install/apply/links | 写互斥；一致性敏感读取不能输出未提交候选链接；锁无泄漏 | L1/L2 |
| T-21 | 新旧/未知事务 schema 与恶意路径/回调字段 | 旧格式只读可识别；缺 UID/GID 不自动执行完整恢复；未知版本和不安全数据拒绝；无 eval/source | L1 |
| T-22 | Core update 的 previous binary/metadata 发布、restart、健康或 commit 失败 | 当前 binary、previous 与 previous.env 恢复配对；另一 Core 不重启；恢复错误可见 | L1/L2 |
| T-23 | restore 坏包、重复成员、路径穿越、symlink、超大成员、缺 TLS | 候选隔离验证失败，原资源无变化；可信测试包不夹带可执行攻击载荷 | L1/L2 |
| T-24 | restore 写入中或双 Core 健康失败 | 恢复文件、目录元数据、服务基线和有效 applied 证据；不能只恢复内容 | L1/L2 |
| T-25 | PNM restart/update/rollback 成功及失败后重启旧服务 | 新 InvocationID 与经验证配置配对；目标 Core 链接 ready；另一 Core 证据不变 | L1/L2 |
| T-26 | 外部 restart / reboot 后执行 show/links | 未重新认证时明确 unknown/drift；通过经验证的 apply 重建记录，不能静默认可未知进程 | L2 |
| T-27 | 成功安装、应用、重启、更新/回滚后外部双协议验证 | 各 Core 独立记录握手和传输结果，链接仅安全传递；失败不因本地监听就判 PASS | L3 |

## 4. 既有测试复用与缺口

| 测试文件 | 已有断言方向 | 需要扩展 |
|---|---|---|
| [test_deploy.sh](../tests/unit/test_deploy.sh) | 顺序、失败停止、post-health、服务恢复及 journal 错误 | T-09～T-17 使用实际临时文件和状态，覆盖真实 mark-configured 与外层 gate |
| [test_transaction.sh](../tests/unit/test_transaction.sh) | 摘要守卫、写入意图、inspect、错误传播、部署关联 | 元数据/目录/schema/marker/中断恢复和幂等性 |
| [test_sandbox_install.sh](../tests/unit/test_sandbox_install.sh)、[test_host_apply.sh](../tests/unit/test_host_apply.sh) | 资源安装、校验补偿、Secret 生成复用、host gate | host 祖先 symlink、root 别名、真实 UID/GID、目录与账户依赖 |
| [test_core_ops.sh](../tests/unit/test_core_ops.sh) | apply 故障、applied 摘要、更新错误报告、restore 候选验证 | 更新 binary/metadata 配对、恢复全矩阵及 T-25 |
| [test_preflight.sh](../tests/unit/test_preflight.sh) | 缺工具、恢复监听者归属、重复安装拒绝、receipt/drop-in | 自定义端口、完整依赖、未决新 schema 事务 |
| [test_node.sh](../tests/unit/test_node.sh)、[test_check.sh](../tests/unit/test_check.sh) | 脱敏、双 Core 独立门控、证据缺失、TLS/账户访问 | 重启/reboot 证据、并发读取、真实 runuser 和父目录访问 |

既有测试与新增 G-02 测试的本地执行结果见第 6 节；通过既有套件不等于本表“需要扩展”及 L2/L3 已完成。隔离 VM 应使用真实二进制和 systemd，避免测试 fakebin 提前占用 PATH 造成假通过。

## 5. 验收记录格式与关闭规则

每次验收记录：源码 HEAD、工作区差异、发行版/架构/内核/systemd、工具及两 Core 固定版本、资产摘要、测试 ID、实际命令、退出码、故障点、前后资源断言及脱敏证据路径。权限记录包含 mode/数字 UID/GID；服务记录包含 active/enabled、实际 unit 路径、InvocationID 和监听归属。Secret 只记录“相同/不同”的比较结果，不记录其值或完整链接。

| 关闭对象 | 最低要求 |
|---|---|
| A-01/G-02 | T-01、T-09～T-20 在相关 L1/L2 通过；late gate failure 不遗留半提交；恢复不确定明确阻塞 |
| A-02/A-05 | T-05～T-08、T-18、T-21 通过；新资源删除、既有身份保护和路径边界可复核 |
| A-03/A-04 | T-04、T-25/T-26 通过；现有 CLI/JSON/URI 行为不被意外改变 |
| G-03/G-04 | T-22～T-24 在 L1/L2 通过，含原操作失败且回滚失败 |
| G-05/G-06 | T-03/T-04/T-12 在真实工具及账户条件通过 |
| Phase 3 | 上述项关闭或有明确接受的处置；G-01 授权主机源码身份独立核对；门禁命令成功 |
| 生产就绪 | 完成适用发行版/systemd/reboot 和 T-27；按 [RELEASING.md](RELEASING.md) 另行执行发布流程 |

生产节点不用于故障注入。源码身份核验、生产执行、版本更新、提交、打 tag 和发布均需各自已有授权；本计划本身不构成这些操作的授权。

## 6. 2026-10-23 本地执行及恢复检查边界

环境、命令退出码、26 套件/254 项结果及日志路径统一记录在 [TASKS.md](TASKS.md)。L1 的系统服务、账户操作和监听使用 mock，文件系统、权限、摘要和密码学工具真实执行；非 root 诊断及恢复调度兼容性另用真实 nobody UID 验证。

| 本地覆盖 | 实际断言 | 仍需补充 |
|---|---|---|
| [部署事务测试](../tests/unit/test_deployment_transaction.sh)，15 项 | 资源/Xray/HY2/内外健康/node/期限/提交失败恢复字节、mode、目录及双服务基线；active/disabled；基线写入失败后重试 | 真实账户、systemd 与服务启动时序 |
| 同套件提交与异常分支 | 唯一 marker、进度日志丢失仍提交、发布后同步异常/子进程退出保留预先持久化的 uncertainty、漂移不覆盖并拒绝后续写入/链接、TERM 补偿 | 真实存储故障、父进程 SIGKILL、VM reboot；不是完整 T-15～T-20 验收 |
| 同套件归属及 applied | 真实 CLI IFS 下拒绝无归属标准 unit/二进制；仅刷新原 confirmed applied；外部 applied 编辑保留 | 真实 systemd FragmentPath/drop-in/PID/监听归属和运行旧配置验证 |
| [沙箱接入测试](../tests/unit/test_sandbox_install.sh)，12 项 | 真实 sandbox、lifecycle、node/applied 参与函数共用事务，外层失败后恢复；既有 Secret/TLS 和补偿用例；宿主 TLS 复用分支在隔离路径中验证原字节及 UID/GID/mode 恢复 | 实际 Core 而非测试资产的 L2 激活与访问权限 |
| [读取权限测试](../tests/unit/test_read_access.sh)，1 项 | root0600 锁和0700状态目录下，非 root check 输出 UNKNOWN、退出1，show/links退出77且无stdout，links help可用 | 发行版用户权限及并发集成 |
| [端口及预检测试](../tests/unit/test_preflight.sh)，14 项 | 自定义端口探测、占用拒绝、无效节点不探测默认端口、恢复分支匹配配置端口，以及既有依赖和归属检查 | 真实 systemd/PID/监听归属及配置端口启动 |
| [生命周期证据测试](../tests/unit/test_core_evidence.sh)，22 项 | 既有证据门控和故障恢复；双 Core update/rollback 三资源发布前后失败矩阵、字节与 mode/UID/GID 恢复、外部元数据修改保留、错误候选版本、restart 与补偿 restart 失败可见；真实 flock 验证准备期互斥、冲突及未决部署提前拒绝、重入和关闭错误传播；另一 Core 不重启 | 服务、下载和 Core 配置验证为模拟；需真实并发 CLI/systemd、L2 启动时序、真实固定资产验证、reboot 及外部连接 |
| [恢复包解析测试](../tests/unit/test_backup_archive.sh)，2 项 | 完整包进入隔离验证 stub；12 类坏包在候选执行前拒绝，包括根目录/目录载荷、超大清单、缺 TLS、绝对/穿越路径、链接、重复/未知/过量成员 | 不执行候选二进制；PAX/GNU 内部扩展头资源限制及来源信任仍待确认，不代表完整 T-23/T-24 或任意不可信包安全 |
| [恢复文件系统补偿测试](../tests/unit/test_restore_recovery.sh)，9 项 | 真实文件字节及 UID/GID/mode 恢复、既有及新目录补偿、最终属主登记、发布/属主修改/登记入口元数据漂移拒绝、部分 chown 失败、symlink/外来目录属主拒绝、applied 文件及目录补偿 | 调用真实发布/补偿辅助函数；服务及账户名称映射为模拟，仍需 L2/L3 验收 |
| [恢复调度测试](../tests/unit/test_restore_flow.sh)，15 项 | 实际解析和调度；晚期写入/健康/applied/commit 失败恢复；active/disabled、inactive、not-found、未知及无效服务状态；原 confirmed InvocationID 更新；未知及外部改动证据保留；真实 flock、清理错误、enable 目录及受保护服务基线文件 | 目的路径映射到私有 host 夹具；Core 执行及 systemd 为模拟；root 使用真实 UID/GID，非 root 兼容运行模拟 root/服务账户策略；仍需真实并发 CLI、systemd、重启和客户端验收 |

未决部署的受控人工检查应先保留受保护的完整证据，不删除 uncertainty、改 journal 或设置 configured=yes 来绕过保护。`sudo pnm --json check`、`sudo pnm node show` 在未决状态返回70是预期拒绝。记录/快照可能包含凭据，不直接打印或附到普通报告。

需要只读摘要时，可在**已确认源码身份的安装**上执行以下检查（替换安装路径和事务 ID）；不是自动恢复命令，不执行记录中的函数或配置内容：

```bash
sudo bash -s -- /usr/local/lib/pnm/lib tx-REPLACE <<'BASH'
set -Eeuo pipefail
PNM_LIB_DIR=$1
transaction_id=$2
source "$PNM_LIB_DIR/common.sh"
source "$PNM_LIB_DIR/output.sh"
source "$PNM_LIB_DIR/config.sh"
source "$PNM_LIB_DIR/lock.sh"
source "$PNM_LIB_DIR/transaction.sh"
pnm_lock_acquire shared
trap pnm_lock_release EXIT
pnm_tx_load_for_inspect "$transaction_id"
printf 'id=%s operation=%s state=%s remaining_changes=%s\n' \
    "$PNM_TX_INSPECT_ID" "$PNM_TX_INSPECT_OPERATION" \
    "$PNM_TX_INSPECT_STATE" "$PNM_TX_INSPECT_CHANGES"
BASH
```

检查失败不代表可以清理记录；它可能表示损坏或证据不足。恢复需在隔离环境核对快照、当前资源和服务后另行制定受控步骤。该版本不提供新的跨进程自动恢复入口。
