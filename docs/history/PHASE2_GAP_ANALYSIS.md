> Historical baseline; later repairs may supersede findings below. Use [current tasks](../TASKS.md) and verify source before acting. This record is not execution or commit authorization.

# PNM Phase 2 — Gap Analysis & Minimal Implementation Plan

审计日期：2026-10-20\
范围：基于当前工作区源码，为 Phase 3～Phase 7 制定差距分类和最小增量计划。\
执行边界：只读审计。本文不代表本地测试、Debian VM 或生产节点验证已经通过。

## 1. 基线与证据边界

| 项目 | 结果 |
|---|---|
| `VERSION` | `0.16.0-rc.1` |
| `v0.16.0-rc.1` tag | `891dc5ca60ee62af579b5e70e5ad47fcd56f3cb4` |
| 当前 HEAD | `fd4ad6066fea81c63508fca5e15686071dc7a4ce` |
| HEAD 与 tag | HEAD 在 tag 之后 8 个提交；版本文件仍为 rc.1，因此版本字符串一致，但当前源码不等于该 tag 发布源码 |
| 工作区 | 审计开始时干净；分支 `main` 跟踪 `origin/main` |
| Phase 1 报告 | 仓库内未找到独立报告文件；Phase 1 依据来自此前审计对源码和测试的检查记录，不能视为可复核的独立审计制品 |
| 仓库级 `AGENTS.md` | 未找到；执行约束采用会话提供的指令 |
| 发布记录 | `CHANGELOG.md` 记录 rc.1；HEAD 上的后续修复尚未形成新版本记录 |

**结论边界：**以下“已实现”表示源码中存在对应实现，并有测试代码或调用链支持；不表示本轮重新执行了测试，也不表示真实 VPS 已验证。Phase 1 对 HY2 SNI 与 Xray 链接行为的结论是代码级结论，生产节点状态没有在本轮访问或复验。

Phase 1 相关结论摘要：

- Xray 分享链接路径已有运行配置对比；检测到漂移时拒绝输出可能过期的 Xray 链接。
- HY2 分享链接路径已有配置一致性保护；漂移或损坏时跳过 HY2 链接，并输出脱敏的差异字段诊断。
- HY2 TLS SNI 已与 Xray REALITY SNI 分离；`selfsigned-pin` 根据证书名称生成 HY2 SNI，避免复用 Xray SNI。
- 以上均为源码和自动化测试层面的证据；Karing 实际导入、真实 REALITY 握手及服务重启恢复仍需目标环境验证。

## 2. 分类定义

| 类别 | 定义 | 处理方式 |
|---|---|---|
| A | 已实现且有充分源码/测试依据 | 保留，不重复实现 |
| B | 已实现但存在已确认缺陷或安全缺口 | 优先修复 |
| C | 尚未实现且当前目标需要 | 在现有状态和 CLI 上最小增量新增 |
| D | 目标能力与现有架构/安全边界冲突 | 先定义兼容与所有权方案 |
| E | 当前版本并非必要，或缺乏足够决策依据 | 延后 |

## 3. 差距矩阵

| ID | 模块 | 当前实现 | 分类 | 风险 | 证据 | 建议 |
|---|---|---|---|---|---|---|
| A-01 | CLI 与节点管理 | `pnm` 入口和既有命令路由存在；本次没有发现必须重命名的命令 | A | — | `lib/common.sh`、`lib/node.sh`、`lib/output.sh` | 保持既有命令和参数语义；只做增量扩展 |
| A-02 | 双 Core 隔离 | Xray 与官方 Hysteria2 使用独立配置、systemd unit、服务账户及生命周期操作 | A | — | `lib/service.sh`、`lib/core-ops.sh`、`lib/check.sh` | 复用现有 Core 操作；禁止无条件联动重启 |
| A-03 | 安装事务与凭据幂等 | 安装流程有事务、Secret 初始化和已配置节点保护；重复安装不会将现有正常配置作为默认重置目标 | A | — | `lib/install.sh`、`lib/sandbox-install.sh`、`tests/unit/test_sandbox_install.sh` | 后续 Profile 切换复用事务，不复用“重装”作为切换实现 |
| A-04 | 服务账户 | 有账户策略校验、合法既有账户复用及事务回滚实现 | A | — | `lib/accounts.sh` 及账户单元测试 | 保持只回滚当前事务创建的资源 |
| A-05 | systemd 权限 | 两个 Core 使用非 root 账户；Xray 特权端口 capability 已纳入 unit；服务有加固配置 | A | — | `lib/service.sh`、unit 生成测试 | 不扩大 capability；Profile 变更不得重写 unit 无关字段 |
| A-06 | 链接与运行配置漂移 | Xray 和 HY2 链接均有运行配置一致性保护；HY2 SNI 已独立于 Xray | A | — | `lib/node.sh`、`lib/render.sh`、`lib/tls.sh`、node/TLS 测试 | 保留保护和现有 URI 格式；继续验证实际服务状态缺口见 G-01 |
| A-07 | SSH、Tailscale、UFW 边界 | 安装代码明确避免重置这些非 PNM 管理面；发布检查也覆盖危险操作模式 | A | — | `README.md`、`lib/install.sh`、`lib/transaction.sh`、release scan | 本计划不触碰这些设置；防火墙自动删除须另行建立所有权 |
| G-01 | 链接、Desired/Actual 一致性 | 链接检查配置文件是否匹配，但不能单凭文件对比证明服务仍在运行或进程已加载该文件；`node show` 对两个 Core 的运行状态和配置一致性呈现不对称 | B | P1 | `lib/node.sh` 的 show/links 路径；`lib/check.sh` 的 Core 检查；`lib/render.sh` 的配置比较 | 统一读取持久化期望值、运行配置与服务状态；漂移按脱敏字段报告。若文件可被外部改写且服务仍运行，评估用现有事务状态记录“已应用配置摘要”，避免另建配置数据库。链接在目标服务非 active 或一致性无法确认时拒绝对应 Core 链接。 |
| G-02 | 首次部署健康提交 | 部署提交前主要检查 service 状态，未充分保证 TCP/UDP 监听已经就绪 | B | P1 | `lib/deploy.sh` 部署健康/提交步骤；`lib/check.sh` 本地监听检查 | 在事务 commit 前复用本地监听检查：Xray TCP、HY2 UDP；失败必须保持未提交并回滚/留恢复状态。不得把本机监听宣传为公网可达。 |
| G-03 | Core 更新事务 | 当前 binary 会进入快照/回滚路径，但旧版本 binary 与版本元数据发布不是完全同一个原子事务 | B | P1 | `lib/core-ops.sh` 更新、快照和回滚步骤；`lib/transaction.sh` | 将旧 binary 与版本元数据的暂存和发布纳入同一事务，或使用原子版本目录/指针；失败注入验证旧 binary 与元数据仍配对。分别更新目标 Core，不触碰另一个。 |
| G-04 | 恢复流程验证 | 归档路径安全检查和事务恢复已存在；恢复前后的 HY2 配置/TLS 验证及完整 Core 健康验证不足 | B | P1 | `lib/core-ops.sh` restore 路径；`lib/render.sh` 候选配置验证；restore 测试 | 恢复前先对候选配置做已有验证；提交前检查目标服务和本地健康。任一步失败恢复原文件与服务状态，保留诊断材料。不要直接将不可信归档解压到系统根目录。 |
| G-05 | 资产工具预检 | 已预检部分下载、校验和解包工具，但 Core/TLS/账户/systemd 阶段使用的工具与 dry-run 依赖清单需要逐项对齐 | B | P2 | `lib/preflight.sh`、`lib/tls.sh`、`lib/service.sh`、`lib/accounts.sh` | 从实际调用链列出安装阶段外部命令；缺少必需工具时在事务开始前报告命令名和阶段。避免将运行时可选工具错误列为强依赖。 |
| G-06 | TLS 权限健康检查 | 安装与恢复代码会设置 HY2 TLS 文件权限，但 check 对私钥所有者、模式和服务账户可读性的覆盖不完整 | B | P2 | `lib/check.sh` 权限检查；`lib/core-ops.sh` 恢复权限设置；TLS 权限测试 | 检查证书/私钥权限策略与 `hysteria` 运行账户可读性；错误输出只给路径和策略，不显示私钥内容。 |
| G-07 | Profile Desired State | 当前安装按双核心路径执行；没有持久化 desired profile，也无 Profile 切换命令 | C | P1 | `lib/common.sh` CLI 路由；`lib/install.sh`、`lib/deploy.sh`；节点配置解析 | 复用节点配置格式，在 `node.conf` 增加可选 `CORE_PROFILE`，缺省按 dual 解释；新增兼容的 Profile 子命令/安装选项。切换只启停目标 Core，保留 binary、配置、证书和 Secret。Actual State 从服务状态及健康检查读取；Managed Resources 依赖事务记录/Unit 内容校验，不可仅看名字或文件存在。 |
| G-08 | 防火墙所有权与 Profile 联动 | PNM 当前不负责 UFW 规则生命周期；事务层也拒绝不支持的防火墙快照输入。按 Profile 自动删除端口规则会越过当前安全边界 | D | P1 | `README.md`、`lib/install.sh`、`lib/transaction.sh` | 在任何自动增删规则前先定义可验证的 PNM 规则所有权凭据和恢复机制。不得按端口号删除、reset UFW 或改 Tailscale 链。由于仓库没有专用防火墙模块，若批准可新增窄范围 `lib/firewall.sh` 及其单测；这是为隔离高风险所有权逻辑，而非通用抽象。该安全切片必须先于能删规则的 Profile 行为。 |
| G-09 | 资源检查 | `pnm check` 有系统/Core 本地检查，但缺少轻量内存、swap、Core RSS、CPU/load、OOM 诊断 | C | P2 | `lib/check.sh` 现有检查入口；未发现对应资源项 | 从 `/proc` 和 systemd 获取指标，仅输出 WARN 与数值，不自动停止服务或改 swap/kernel。可在 check 中按需添加函数，不增加运行依赖。 |
| G-10 | 外部业务验证 | 当前本地监听和 service 检查不能证明外部客户端能连；没有可配置可信探测器 | C | P2 | `lib/check.sh` 本地检查；外部连接测试未见实现 | 保留本地检查语义；只有配置可信探测端点/客户端后才执行外部检查。未配置时报告 `NOT CONFIGURED`，不得伪造 PASS，也不得输出凭据。 |
| G-11 | Secret 备份加密 | 含 Secret 备份有权限保护，但未见加密和密钥托管策略 | E | P2 | `lib/core-ops.sh` backup；README 的敏感数据提示 | 延后。先确定密钥来源、恢复演练和无人值守备份需求，不自行引入主密钥或外部依赖。 |
| G-12 | PNM 自身更新 | 当前更新命令管理 Core；未发现 PNM 自身更新器 | E | P3 | `lib/core-ops.sh` 更新路由、CLI 路由 | 延后，避免扩大本次双 Core 生命周期范围。 |
| G-13 | 发布文档 | 当前 HEAD 比 rc.1 tag 多 8 个提交，`CHANGELOG.md` 仍是 rc.1；发布前需要整理变更记录 | E | P3 | `VERSION`、`CHANGELOG.md`、Git tag/HEAD | 由版本发布阶段决定新版本号和变更记录；本计划不改版本、不打 tag、不发布。 |

## 4. 文件级修复清单

下表是建议范围，不代表本阶段已经修改。实现前仍须以开始 Phase 3 时的 HEAD 和实际调用链复核行号/函数名。

### G-01 — 链接与运行态一致性

- **类别/风险：** B / P1
- **证据与根因：** `lib/node.sh` 的 show/links 比对持久化值与运行配置，但配置文件一致不等同于服务 active 或该进程已加载当前文件；`lib/check.sh` 检查 service/监听，但没有统一用同一结果门控两个链接。
- **修改文件：** `lib/node.sh`、`lib/check.sh`、`lib/render.sh`、对应 `tests/unit/` node/check/render 测试。
- **最小修改：** 复用现有解析器输出脱敏字段差异；show 增加对称的 HY2 运行状态；links 按协议独立门控；必要时在现有成功 apply 状态中记录配置摘要和事务代次，不新增并行配置文件，除非确认现有事务状态无法表达。
- **兼容性：** 保留 CLI 命令及正常链接格式；`node show` 增加只读状态行；HY2 仍允许按既有部分成功语义省略，Xray 与 HY2 相互独立。
- **风险：** 服务状态检测可能使原先只根据配置输出的链接被拒绝；错误必须准确区分 drift、service down、状态未知。
- **测试：** 配置一致/漂移、服务 inactive、文件在 apply 后被修改、单 Core 故障不影响另一 Core 链接、敏感字段不出现在诊断中。
- **回滚：** 恢复上述函数与测试；不需要变更节点 Secret 或运行配置。
- **阶段：** Phase 3。

### G-02 — 首次部署健康提交

- **类别/风险：** B / P1
- **证据与根因：** `lib/deploy.sh` 在服务状态检查后提交部署；本机监听检查现存于 `lib/check.sh`，未完全作为部署 commit 条件。
- **修改文件：** `lib/deploy.sh`、`lib/check.sh`、`tests/unit/` deploy/check 测试。
- **最小修改：** 在事务提交前复用目标 Core 的本地配置与监听检查；失败沿现有 transaction rollback 处理。
- **兼容性：** 成功安装行为不变；失败安装将更早保持未提交状态。
- **风险：** 测试容器可能没有真实监听能力，使用模拟检查；真实 Debian systemd 验证另列。
- **测试：** active 但未监听、配置不合法、单个 Core 检查失败、回滚失败状态报告。
- **回滚：** revert 部署健康门控代码，不改服务配置。
- **阶段：** Phase 3。

### G-03 — Core 更新事务

- **类别/风险：** B / P1
- **证据与根因：** `lib/core-ops.sh` 的 binary 快照、旧版本归档和版本元数据文件写入存在事务边界不一致风险。
- **修改文件：** `lib/core-ops.sh`、如需则 `lib/transaction.sh`、`tests/unit/` core update 测试。
- **最小修改：** 把相关旧状态快照和元数据原子替换纳入单目标 Core 事务；不合并 Xray 与 HY2 更新。
- **兼容性：** 命令/版本输出维持；成功升级产物不变。
- **风险：** 磁盘空间不足或 rename 失败时必须保留可恢复旧版本。
- **测试：** binary 发布前失败、元数据替换失败、重启失败、健康失败，验证旧 binary/元数据成对恢复且另一 Core 未改变。
- **回滚：** 恢复 transaction manifest 后回滚单测；运行时由旧快照恢复。
- **阶段：** Phase 3。

### G-04 — Backup/restore 验证

- **类别/风险：** B / P1
- **证据与根因：** `lib/core-ops.sh` 有归档安全检查和事务恢复，但恢复验证对 HY2 配置/TLS 以及服务健康的覆盖不完整。
- **修改文件：** `lib/core-ops.sh`、`lib/render.sh`、相关 restore 测试。
- **最小修改：** 复用候选配置验证；按需恢复目标 Core，不扩大到 SSH/Tailscale/UFW；验证失败还原文件、权限及原服务状态。
- **兼容性：** 归档格式保持；拒绝原本可能被接受但无法验证的坏配置。
- **风险：** 老备份配置与当前 binary 兼容性；错误应在 apply 前说明。
- **测试：** 损坏归档、路径穿越、HY2 配置坏、TLS 缺失、服务恢复失败，确认保留诊断和原文件。
- **回滚：** revert 验证步骤；保留旧恢复流程可在受控情况下处理。
- **阶段：** Phase 3/6，建议在 Phase 3 补足已确认缺口，Phase 6 再做更广的恢复演练。

### G-05 — 安装依赖预检

- **类别/风险：** B / P2
- **证据与根因：** `lib/preflight.sh` 与各 stage 实际命令清单需要对齐。
- **修改文件：** `lib/preflight.sh`、依赖预检测试。
- **最小修改：** 基于调用链收敛必需命令映射，dry-run/preflight 在事务前报告缺失项。
- **兼容性：** 安装参数不变；必要工具缺失时更早失败。
- **风险：** 不应把仅诊断命令误标为必须安装依赖。
- **测试：** 逐个模拟关键命令缺失，确认无事务资源创建。
- **回滚：** 恢复依赖清单。
- **阶段：** Phase 3。

### G-06 — TLS 文件权限检查

- **类别/风险：** B / P2
- **证据与根因：** 安装/恢复设置 TLS 权限，运行健康检查未对私钥策略进行完整校验。
- **修改文件：** `lib/check.sh`、权限检查测试。
- **最小修改：** 检查实际配置路径、所有者、模式及 `hysteria` 账户可读性；证书动态模式按现有 TLS 模式返回适用状态。
- **兼容性：** 正常配置无输出格式破坏，仅增加健康项；错误不泄露密钥。
- **风险：** external-ca/ACME 模式不能假定存在固定文件。
- **测试：** 有效/过宽/错误属主/不可读/动态证书模式。
- **回滚：** 移除此新增检查项。
- **阶段：** Phase 3。

### G-07 — Profile

- **类别/风险：** C / P1
- **证据与根因：** 当前 CLI/安装状态没有 desired profile 字段或切换入口。
- **修改文件：** `lib/common.sh`、`lib/install.sh`、`lib/deploy.sh`、`lib/node.sh` 或现有 node config 模块、`lib/check.sh`、相关测试与用户文档。
- **最小修改：** 扩展现有 node.conf 可选状态键 `CORE_PROFILE`（缺省 dual）；以现有 service/core ops 完成 enable/disable；切换保留 Core 文件和所有 Secret；profile 状态仅在两端验证后提交。
- **兼容性：** 添加命令/参数，不删除既有入口。关键升级风险：rc.1 的旧配置解析器可能拒绝新增键，降级前需提供明确行为或兼容版本边界。
- **风险：** Desired/Actual/Managed 混淆会误停用户服务；不能仅凭 Unit 名称判定 PNM 所有权。活动 Profile 卸载语义也需定稿。
- **测试：** dual/reality/hy2 安装；双向切换；Secret/config 保留；中断重试；外部同名服务拒绝操作；失败回滚；禁用 Core 状态显示 SKIP。
- **回滚：** 切换回旧 Profile 并恢复服务 enable/active 状态；保留两套 Core 文件和 Secret。
- **阶段：** Phase 4，但依赖先完成 G-08 的所有权决策。

### G-08 — 防火墙所有权

- **类别/风险：** D / P1
- **证据与根因：** PNM 当前未拥有 UFW 生命周期；Profile 目标要求端口规则联动，和当前不碰用户规则边界冲突。
- **修改文件：** 若获批准，新建 `lib/firewall.sh` 和 `tests/unit/test_firewall.sh`；需要更新 `lib/transaction.sh` 快照策略及文档前先复核真实结构。
- **最小修改：** 只给 PNM 新建规则附带可验证所有权记录；预览变更；删除前同时验证记录与规则；无法验证时拒绝自动删。禁止端口号盲删、`ufw reset`、iptables flush、操作 Tailscale 链。
- **兼容性：** 默认不改变现有规则；已存在的同端口规则按未确认所有权处理。
- **风险：** UFW 规则索引变化与并发人工编辑；故须按规则内容加所有权标记/快照并在 apply 前重新核对。
- **测试：** 用户同端口规则、其他工具规则、Tailscale 链、重复应用、回滚、命令失败注入。
- **回滚：** 仅撤销所有权凭据可验证且由本次事务新增的规则；失败保留恢复清单，绝不扩大删除。
- **阶段：** Phase 6 安全切片，并且必须先于 Phase 4 中任何自动删除规则的 Profile 能力。

### G-09 — 资源健康指标

- **类别/风险：** C / P2
- **证据与根因：** `lib/check.sh` 尚无目标资源指标；项目支持低内存 VPS，但不应假设双 Core 无资源开销。
- **修改文件：** `lib/check.sh` 及 check fixture 测试。
- **最小修改：** 从 `/proc/meminfo`、进程状态和 systemd 读取 Total/Available/Swap/Core RSS/Load/OOM 可用指标，达到阈值时只 WARN 并列实值。
- **兼容性：** 不自动停服务、不改 swap/kernel，不新增重量级依赖。
- **风险：** 容器中 `/proc` 信息可能不完整；未知状态应为 WARN/unknown。
- **测试：** 合成 1GB/充足内存、缺少字段、进程 RSS 不可读、OOM 计数不可用。
- **回滚：** 移除资源检查，不影响 Core 操作。
- **阶段：** Phase 5。

### G-10 — 外部检查

- **类别/风险：** C / P2
- **证据与根因：** 本地 service/listen 无法证明公网路径和客户端协议握手；当前无可信探测器。
- **修改文件：** 优先扩展 `lib/check.sh` 和 CLI 现有 check 路由；若外部探测协议需要复杂状态，先评估再建新文件。
- **最小修改：** 只有显式配置探测器时执行；未配置输出 `NOT CONFIGURED`；凭据经受保护配置读取，不进日志。
- **兼容性：** 保留现有 `pnm check` 默认行为与退出码约定；新增选项必须先检查当前路由。
- **风险：** 探测端泄漏凭据、误把端口可达当协议成功。
- **测试：** 无探测器不得 PASS；探测失败、超时、脱敏；REALITY/HY2 分别报告。
- **回滚：** 移除可选外部检查入口，默认本地检查保持。
- **阶段：** Phase 5。

## 5. Phase 3～Phase 7 计划

### Phase 3 — 修复当前实现缺口

**Objective:** 修复 G-01～G-06，不引入 Profile 或新的外部依赖。\
**Dependencies:** 开始实施时复核 HEAD、工作区、调用链和测试框架；优先冻结节点链接现有输出格式。\
**Files:** `lib/node.sh`、`lib/render.sh`、`lib/check.sh`、`lib/deploy.sh`、`lib/core-ops.sh`、`lib/preflight.sh`、必要时 `lib/transaction.sh`；对应 `tests/unit/`。\
**Changes:** 运行配置/服务状态门控、部署前监听验证、更新回滚原子性、restore 候选验证、阶段依赖预检、TLS 私钥权限检查。\
**Compatibility:** 不修改 CLI 既有命令、节点配置格式、协议参数、端口、SSH/Tailscale/UFW；正常链接保持原格式。\
**Risks:** 服务状态与配置状态错误分类；安装测试桩和真实 systemd 行为差异。\
**Tests:** 既有单测、失败注入、敏感数据脱敏、`make check`、`make shellcheck`、`make release-check`。\
**Rollback:** 每个修复以小提交/小 diff 交付；本地可逐项 revert。运行时失败走现有事务恢复，不触碰用户配置。\
**Acceptance:** 单 Core 故障隔离；链接只对应可确认的已应用配置；服务 active 但未监听不得 commit；更新任何一步失败后目标 Core 旧 binary/config/service 状态恢复；缺工具在事务前失败。

### Phase 4 — Profile Desired State

**Objective:** 在现有节点状态上支持 `dual`、`reality`、`hy2`，默认 dual。\
**Dependencies:** Phase 3 稳定；G-08 所有权边界已明确。若暂不实现防火墙所有权，Profile 只能管理服务状态且明确不自动删除/创建规则。\
**Files:** 仅扩展现有 CLI、node config、install/deploy、service/core ops、check 及其测试；不新增平行状态库。\
**Changes:** 可选 `CORE_PROFILE`，旧配置缺省 dual；新增兼容接口；Actual State 独立读取；Managed Resources 通过事务/Unit 验证；切换只停止/禁用非目标 PNM Core，配置和 Secret 保留。\
**Compatibility:** 不删除命令；评估老版本解析新增键的降级风险；已有节点无字段时按 dual。\
**Risks:** 外部 Unit 冒名、状态提交顺序错误、切换中断。\
**Tests:** 三种新部署、所有转换、重复切换、失败恢复、Secret 不变、其他 Core 故障隔离、非目标 Core 显示 SKIP。\
**Rollback:** 恢复原 Desired Profile 和服务 enabled/active 状态，不删除 Core 资源。\
**Acceptance:** 状态只在目标 Core 验证通过后提交；失败/重试不会重建 Secret 或覆盖自定义配置。

### Phase 5 — 生命周期与健康观测

**Objective:** 完善 Core 独立操作、Profile 感知检查、轻量资源与可选外部验证。\
**Dependencies:** Phase 4 状态模型冻结；Phase 3 健康结果结构可复用。\
**Files:** 现有 Core 操作模块、`lib/check.sh`、CLI check/status 路由和单元测试。\
**Changes:** 对禁用 Core 返回 SKIP；资源指标只 WARN；无外部探测配置返回 NOT CONFIGURED；每 Core 更新/重启/日志命令沿用现有等价接口。\
**Compatibility:** 保留当前命令名和退出码；新增状态项为增量输出。\
**Risks:** 资源数字存在采样语义差异；外部探测需要用户选择信任端点和凭据方式。\
**Tests:** 检查状态映射、单核 Profile、低内存 fixture、超时/脱敏和 Core 隔离。\
**Rollback:** 各检查项可独立移除；不修改服务状态。\
**Acceptance:** 本机检查不冒充外部业务成功；未配置外部探测绝不 PASS；资源不足不触发自动停服。

### Phase 6 — 防火墙、事务恢复与 Secret 保护

**Objective:** 在安全所有权可验证的前提下，完善可恢复资源管理。\
**Dependencies:** Profile 若需要联动规则，G-08 必须先完成设计和失败注入；不得先实现自动删除。\
**Files:** 当前事务、Core backup/restore；防火墙能力获批后才新增 `lib/firewall.sh` 和对应测试；文档按实际功能更新。\
**Changes:** 管理资源收据、事务快照覆盖、恢复演练；备份加密仅在密钥托管决策后进入实施。\
**Compatibility:** 不更改 SSH/Tailscale/UFW 既有配置；不支持的外部资源明确拒绝自动处理。\
**Risks:** UFW 规则在人工编辑后索引变化；回滚失败必须保留诊断/恢复文件且不得报成功。\
**Tests:** 同端口用户规则、Tailscale 链、失败注入、备份损坏/路径穿越/权限、恢复服务状态。\
**Rollback:** 只恢复本事务持有的资源；无法证明所有权时保留资源并请求人工处置。\
**Acceptance:** 任何自动删除都有可验证所有权；失败回滚不会触碰管理员规则。

### Phase 7 — 回归、文档与交付

**Objective:** 覆盖兼容性、失败路径并记录生产验证边界。\
**Dependencies:** Phase 3～6 实际获批部分完成；不以计划替代未实现功能。\
**Files:** 现有 `tests/unit/`、Makefile 对应检查入口、README/CHANGELOG/运维文档；不在本阶段自动改版本。\
**Changes:** 扩展现有测试框架；记录 Debian 13 disposable VM 的操作清单和结果；发布准备另行授权。\
**Compatibility:** CLI 基线回归；确认 `pnm --help`、version/status/node/check/links 现有接口。\
**Risks:** 单元模拟无法覆盖 systemd、reboot、外部网络和真实客户端。\
**Tests:** `make check`、`make shellcheck`、`make release-check`；临时目录、假 systemd/网络命令；独立 Debian 13 VM 验证监听、重启、两种客户端连接。\
**Rollback:** 文档/测试变更可独立 revert；发布资产与版本 tag 不在本阶段自动生成。\
**Acceptance:** 本地测试与 VM 验证分别报告；不得把静态检查称为生产成功。

## 6. 依赖关系与并行建议

```text
Phase 3 配置/链接检查 ─┐
Phase 3 更新事务检查 ───┼─> Phase 4 Profile 状态和切换 ─> Phase 5 健康/资源能力
Phase 3 部署/恢复检查 ──┘                 ▲                     │
                                        │                     ▼
                         Phase 6 防火墙所有权先决切片 ───> Phase 7 回归与文档
```

- Phase 3 中，链接一致性、Core 更新事务可以并行分析；共享 `lib/check.sh`、`lib/core-ops.sh` 或测试文件的改动应串行集成。
- Profile 的服务切换实现依赖 Profile 状态模型；任何自动防火墙删除依赖 G-08 所有权验证，不能并行提前启用。
- 资源检查可在 Phase 4 状态模型确定后开发；Profile-aware SKIP 必须等状态来源冻结。
- Phase 7 的完整回归与文档收尾应在实现冻结后执行；真实 Debian VM 和客户端验证与本地单测并列报告，不相互替代。

## 7. 延后项与需决策事项

1. **Profile 降级兼容：** rc.1 旧解析器对新增 `CORE_PROFILE` 的处理方式，以及是否需要明确禁止降级到旧版。
2. **活动 Profile 的卸载语义：** 卸载是否必须显式确认停止目标 Core，且是否永远保留 Secret/用户配置。
3. **UFW 所有权：** 是否批准 PNM 创建带可验证所有权记录的规则；默认建议在批准前不自动删除既有规则。
4. **外部探测器：** 由谁提供、如何保护客户端凭据，以及是否需要单独测试节点。
5. **备份加密：** 密钥由用户、系统密钥环或外部 KMS 托管；决定前不引入加密依赖或主密钥。

## 8. Phase 2 总结

- **已实现、无需重复开发：** `pnm` CLI 基线、Xray/HY2 双 Core 独立服务和配置、安装事务及 Secret 保护、账户复用、systemd 最小权限、链接格式与配置漂移保护、HY2 独立 SNI、非 PNM 管理面安全边界。
- **已确认需要修复：** 部分检查/链接未将服务运行状态和配置文件状态统一起来；部署提交健康门槛、Core 更新元数据原子性、恢复配置/TLS 验证、安装工具依赖盘点、TLS 私钥健康校验需要补强。
- **当前必要的新能力：** Profile Desired State、Profile-aware health、低成本资源 WARN、可选外部业务检查；按依赖顺序增量实现。
- **架构冲突：** Profile 与当前不管理 UFW 的安全边界存在冲突；先定义可验证规则所有权，再决定是否启用防火墙自动联动。
- **建议延后：** 加密备份（缺少密钥托管决策）、PNM 自更新、版本号/发布记录整理。
- **风险数量：** P0：0；P1：6；P2：5；P3：2。这里按差距项风险分级计数，不表示 P0 风险不存在于项目其他未审计区域。
- **预计文件范围：** Phase 3 优先修改现有 `lib/node.sh`、`lib/render.sh`、`lib/check.sh`、`lib/deploy.sh`、`lib/core-ops.sh`、`lib/preflight.sh`、必要时 `lib/transaction.sh` 和对应现有测试；Profile 阶段扩展现有 CLI/config/service 模块；只有防火墙所有权方案获批后才新增专用模块。
- **推荐首个最小工作单元：** Phase 3 G-01：补齐 `node show`/`node links` 对运行服务状态与持久化、运行配置一致性的对称、脱敏诊断，并用本地临时配置测试。它直接覆盖已发生的旧链接风险，且不要求修改生产服务或配置格式。
- **需要用户决策：** Profile 降级与卸载语义、UFW 规则所有权、外部探测器信任方式、备份加密密钥托管。

**Phase 2 Status: COMPLETED**\
**Recommended Next Action: Phase 3 — Existing Defect Fixes**

本次仅新增本审计文档；没有修改源码、版本、tag 或 Release，没有连接生产 VPS，也没有执行自动化测试。进入 Phase 3 代码修改需按实施范围单独授权。
