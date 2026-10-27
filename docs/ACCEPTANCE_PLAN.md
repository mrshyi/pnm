# PNM Phase 3 验收设计

初稿：2026-10-22；云端开发边界更新：2026-10-26。当前源码基线和已执行结果见 [TASKS.md](TASKS.md)，原始设计基线保留在历史评估中。

**状态：验收计划；L1 和选定 Debian 13 L2 场景有执行记录，完整 L2 矩阵及 L3 尚未通过。** 对应 [历史评估](history/IMPLEMENTATION_ASSESSMENT.md) 和 [原部署事务设计](history/DEPLOYMENT_TRANSACTION_DESIGN.md)。旧环境的真实生命周期、更新、重启及故障切片范围见 [历史矩阵](history/PHASE3_EXECUTION_2026-10-22_26.md#matrix-reconciliation--2026-10-25)，不能视为当前云端重跑或整份矩阵通过。

## 1. 分层证据与环境

| 层级 | 环境 / 方法 | 可以证明 | 不可替代 |
|---|---|---|---|
| L0 | 当前工作区的源码、Git 和文档静态检查 | 分支与差异、静态缺口、设计可追踪 | 动态测试、真实权限及服务行为 |
| L1 | Linux 开发环境，含 Ubuntu ARM64／非 root；mock、私有临时目录与回环传输测试 | 返回码、步骤、状态记录、实际文件/权限、受控 curl/TLS 错误和注入分支；root 专项明确跳过 | 目标 amd64 平台、真实 systemd/Core、reboot、公网握手 |
| L2 | 可丢弃的受支持 Ubuntu/Debian amd64/systemd 环境 | root/账户/权限、真实 unit、监听、恢复、reboot | 其他发行版矩阵及公网客户端连通 |
| L3 | 受控外部 Xray/HY2 客户端 | 相应网络条件下真实协议握手和传输 | 服务故障补偿和其他网络条件 |

README 声明支持 Debian 12/13、Ubuntu 22.04/24.04 amd64。当前验证优先级见 TASKS；各发行版未执行就保留未验证，不能仅靠 os-release fixture 宣称整个平台验收完成，也不要求完成 Debian 验收后才验证 Ubuntu。

云端开发准备和只运行 L1 的边界见 [CONTRIBUTING.md](../CONTRIBUTING.md)。旧 WSL
宿主、磁盘容量、私有夹具路径和已完成的准备计划不作为当前环境前提；每次重新检查
执行命名空间的权限、systemd、挂载与虚拟化能力，不自动在开发主机运行故障注入。

前置工具根据 Makefile、tests 和实际调用链确认：Bash、make、ShellCheck、Python 3、zip/unzip、tar、flock、OpenSSL、curl、sha256sum、ss、systemctl/systemd-analyze、账户工具、runuser 及标准 coreutils。测试资产必须是可公开的固定 fixture 或批准的 Core 版本，不使用生产 Secret。

## 2. 仓库检查命令

仅在准备好的 Linux 测试工作区执行，保留每个命令的独立退出码；任一步失败先定位，不用筛掉 ShellCheck 规则后的结果替代原门禁。

```bash
make check
make shellcheck
make release-check
```

`make check` 包含 syntax/security-scan/test；`make release-check` 再次调用 check，不能把两次执行统计为更多独立用例。CI 已显式配置 Ubuntu22.04／24.04 amd64 的三个门禁，并记录工具版本；配置存在不代表任务已运行或通过，实际结果见 TASKS。

无需为纯文档增加业务测试；修改实现时优先扩展现有测试，用可验证的前后状态断言覆盖缺口，不只检查函数调用次数。

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

| 测试文件 | 用例定位 | 需独立核对的验收边界 |
|---|---|---|
| [test_deploy.sh](../tests/unit/test_deploy.sh)、[test_deployment_transaction.sh](../tests/unit/test_deployment_transaction.sh) | 顺序、整体提交/补偿、marker 与不确定状态 | T-09～T-20 剩余 L2 故障位置和调度，不能只凭 mock 关闭 |
| [test_transaction.sh](../tests/unit/test_transaction.sh) | 摘要、元数据、目录、schema、inspect 与中断记录 | 记录拒绝和 L1 恢复不等于跨进程自动恢复或物理断电持久性 |
| [test_sandbox_install.sh](../tests/unit/test_sandbox_install.sh)、[test_host_apply.sh](../tests/unit/test_host_apply.sh) | 安装、凭据复用、路径与权限门禁 | 实际 root 身份、服务账户与 Core 加载；非 root 不伪装为已验收 |
| [test_core_ops.sh](../tests/unit/test_core_ops.sh)、[test_core_evidence.sh](../tests/unit/test_core_evidence.sh) | per-Core 生命周期、binary/metadata 配对、applied 恢复 | T-22/T-25 剩余 L2 存储、中断与恢复失败组合 |
| [test_preflight.sh](../tests/unit/test_preflight.sh) | 依赖、配置端口、监听归属、重复安装和恢复收据 | 其他平台/获取失败与未执行的实际工具条件 |
| [test_node.sh](../tests/unit/test_node.sh)、[test_check.sh](../tests/unit/test_check.sh) | 脱敏、双 Core 门控、证据缺失、非 root 拒绝 | T-20/T-26 剩余调度与真实 root/runuser 边界；L3 另验 |
| [test_tls.sh](../tests/unit/test_tls.sh)、[test_hy2_sni.sh](../tests/unit/test_hy2_sni.sh)、[test_tls_access.sh](../tests/unit/test_tls_access.sh) | 真实证书、SAN、有效期与可读性 | root 专项、目标 amd64 工具版本及真实客户端 TLS 加载 |

当前通过和跳过项见 TASKS，历史结果见第 6 节链接。上表是用例与验收边界索引，不将旧缺口重新标为未实现。隔离 VM 应使用真实二进制和 systemd，避免测试 fakebin 提前占用 PATH 造成假通过。

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

## 6. 历史记录与受控检查

历史执行次数、旧 WSL 环境和增量结果已移至 [阶段执行记录](history/PHASE3_EXECUTION_2026-10-22_26.md)。
最新云端结果与未验收边界见 [TASKS.md](TASKS.md)，不将历史通过重记为本次通过。

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
