# 发布前验收清单

本清单用于冻结发布候选、执行有限功能验收和作出发布决定，不授权安装、
依赖准备、故障注入、重启、Git 操作、版本变更或发布。实际执行必须使用已授权的
可丢弃测试目标；不在 ARM64 开发主机或生产节点上执行这些操作。
当前实现、测试结果和阻塞统一记录在 [TASKS](TASKS.md)。

## 1. 固定候选和验收范围

- [ ] 指定候选提交 SHA、版本、Core 当前/上一批准版本和各架构资产摘要。
      当前验收参考源码及各层结果见 TASKS，VERSION 为 `0.16.0-rc.1`；
      它不是未来发布候选自动通过的证明。
- [ ] 明确发布类型：测试预发布 RC，或声明特定平台生产可用的正式版。
- [ ] 按 OS/架构分别建记录，目标原生架构与资产一致，不使用模拟执行替代原生验收。
- [ ] 核对测试目标连接方式、UID、架构、PID1/systemd、挂载/虚拟化能力及重启路径；
      明确允许的安装、服务账户、四个既定故障和重启范围。
- [ ] 准备可信干净基线/克隆、匹配架构的两套批准 Core 资产、测试 DNS/证书及外部客户端。
      可信备份摘要独立保存；不使用生产凭据、生产备份或未知来源包。

Debian 与 Ubuntu 使用相同部署流程、通过条件和停止规则，覆盖四个发行版、
两种架构共八个组合。执行可先选择已有合格目标，不以某个发行版先完成为前提：

| 目标 | 当前证据 | 发布前安排 |
|---|---|---|
| Ubuntu22.04 amd64 / arm64 | 两架构管理主流程/CLI/Profiles/诊断/卸载通过；amd64 原生集成及真实重启通过 | ARM64 真实重启受 KVM 硬件阻塞；具体源码/门禁见 TASKS |
| Ubuntu24.04 amd64 / arm64 | 两架构管理主流程/CLI/Profiles/诊断/卸载通过；amd64 原生集成及真实重启通过 | ARM64 真实重启受 KVM 硬件阻塞；具体源码/门禁见 TASKS |
| Debian12 amd64 / arm64 | 两架构管理主流程通过；amd64 原生 systemd/Core 及真实重启通过 | ARM64 原生 Debian/Core 层及真实重启受 KVM 硬件阻塞 |
| Debian13 amd64 / arm64 | 两架构管理主流程通过；amd64 原生 systemd/Core 及真实重启通过 | ARM64 原生 Debian/Core 层及真实重启受 KVM 硬件阻塞 |

自动准备入口见 [guest mainflow](../tests/integration/GUEST_MAINFLOW.md#automated-disposable-ci-preparation)：
独立 CI 从官方镜像生成模板，经实际 boot-only 核验后运行现有场景。八组合
管理主流程、Profiles、安装/卸载、TLS 和既定补偿场景已有指定源码的通过记录；
四个 amd64 KVM 的原生集成及同盘重启通过。ARM64 原生 Debian/重启和公网双协议
仍须独立收口，不据此勾选整份清单。实际 CI 结果
和失败原因仍须记入 TASKS，不再要求先人工提交旧私有模板才能开展该试跑。

## 2. 执行清单

每一行按实际 OS/架构分别记录 PASS、FAIL 或 BLOCKED；未执行不勾选。
U-01～U-08 的完整断言复用 [有限验收合同](ACCEPTANCE_PLAN.md#platform-closeout)，
沿用历史 ID，但适用于 Debian 和 Ubuntu，不追加 T-01～T-27 的全部组合。
先选已获准的一个原生目标跑通正常路径，再完成固定故障和重启，随后复用记录执行
其余七个组合；容器 CI、另一发行版或另一架构的结果不替代本组合的部署证据。

| 完成 | ID | 验证内容 | 必须满足的通过条件 |
|---|---|---|---|
| [ ] | R-01 / U-01 | 候选来源和仓库门禁 | 工作区干净；实际候选的 check、ShellCheck、release-check 及八组合 CI 成功；Debian 另在合格原生 root/systemd 测试目标执行既有 systemd/Core 集成检查，容器 PASS 不填为该层 PASS；保存退出码、跳过项和源码 SHA，重复门禁不重复计覆盖 |
| [ ] | R-02 | 用户安装入口 | 在干净目标安装已核对候选的 CLI/runtime；`pnm` 指向正确入口和库文件，版本/摘要符合候选。`install.sh` 安装 CLI，`pnm install` 安装 Core，二者分别核对；不依赖浮动 main |
| [ ] | U-02 | 初始化和首次双 Core 安装 | `pnm node init`、`pnm node validate`、dry-run、批准安装完整通过；dry-run 不变更管理资源；配置端口、实际进程/监听、applied、InvocationID、configured 与唯一提交一致；账户/TLS 权限真实正确 |
| [ ] | U-03 | 凭据和两种 TLS 模式 | selfsigned-pin 与 external-ca 各在干净克隆成功；重复安装拒绝且原凭据/TLS 不变；错配证书/私钥在事务前拒绝，不覆盖外部文件或隐式轮换 |
| [ ] | P-01 | Profiles 正常切换及既定补偿 | 实测 `dual→reality→hy2→dual`；服务 active/enabled 与选择一致，保留二进制、配置和凭据；未操作的 Core 不被额外重启/改写；验证现有选定的失败补偿，不增加故障排列 |
| [ ] | U-04 | 两 Core 独立 apply/restart | 两 Core 分别操作成功，另一 Core 的文件和 InvocationID 不变；外部 restart 后旧 applied 不能继续证明 ready，经验证 apply 后重新确认 |
| [ ] | U-05 | 更新和版本回滚 | 两 Core 分别完成不同批准版本 update→rollback；实际二进制、previous、版本元数据及 applied 配对；另一 Core 不受影响；资产与本机架构一致 |
| [ ] | U-06 | 可信备份和恢复 | 独立记录备份摘要；状态变更后在同架构恢复，配置/凭据/数字权限及服务策略正确；损坏包在执行候选/修改管理资源前拒绝；异架构包保持拒绝，不做迁移 |
| [ ] | U-07 | 固定四个拒绝/补偿场景 | 只执行缺 openssl、首次 HY2 启动失败、HY2 update 启动失败、restore 的 HY2 启动失败；使用独立干净克隆；断言原资源/账户/服务/applied/提交状态恢复且可重试 |
| [ ] | O-01 | 状态、资源和恢复诊断 | 实测 `pnm status`、`pnm check`、`pnm check --resources`、`pnm profile show`；配置/应用/运行状态可区分，禁用 Core 不误报故障；随既定失败场景核对 recovery list/inspect 的真实退出码、脱敏及只读性；未知状态不能伪报健康 |
| [ ] | U-08 | 真实同盘 VM 重启 | 保存独立启动证据；配置/凭据/版本/端口持久；旧 InvocationID 正确失效，各 Core 验证 apply 后重新确认；不能以重启服务、reexec 或重启 CI 控制器代替 |
| [ ] | C-01 | 外部双协议客户端 | 从获准外部客户端分别完成 REALITY 和 HY2 的握手与数据传输；记录服务端/客户端版本及网络条件；公网端口由操作者按授权管理，PNM 不自动改防火墙 |
| [ ] | X-01 | 正常卸载退出流程 | 在最终可丢弃克隆上分别执行已有单 Core 卸载；所需备份可识别且权限受保护，目标资源按现有所有权规则处理，另一 Core 保持正常；不追加卸载故障注入 |

`pnm node links` 的完整输出只在私有测试边界内交给客户端，不进入普通日志。
健康与监听检查以配置端口及当前 Profile 为准，不统一要求默认443/8443或两 Core 都 active。
O-01 的非 root WARN/UNKNOWN/权限拒绝应按实际权限判断；recovery 的退出0仅表示事务
写入阻塞检查清楚，不表示服务健康或已自动恢复。失败诊断不清除、重放或修改事务证据。

## 3. 证据和停止规则

每个执行项至少保留以下脱敏记录，完整敏感材料仅放在受保护的私有证据目录：

```text
ID / OS / architecture:
Candidate SHA / worktree delta / PNM version:
Kernel / systemd / native Core versions and approved hashes:
Command / exact exit / executed and skipped checks:
Before/after: files, numeric UID:GID:mode, service policy, InvocationID, applied, commit:
Result: PASS | FAIL | BLOCKED
Reason / private evidence reference:
```

- FAIL：只修已复现的根因，重跑受影响项目和必需门禁；源码变化后标明旧证据适用性。
- BLOCKED：记录缺少的目标、资产或授权，不当作 PASS，也不新增加固阶段。
- 凭据泄露、资源丢失、错误提交或恢复错误属于发布阻塞；不得靠延期、删收据、
  改 journal 或设置 configured 标记掩盖。
- 完成固定清单后输出一次 OS/架构收口表和明确延期项，不继续扩大边界组合。

## 4. 发布决定与交付

**RC 测试预发布：** 候选来源和 R-01 通过、没有已确认的阻塞缺陷，且发布说明明确列出
全部未验收项时，可以提交 RC 发布审批；未执行的功能仍不能标为通过。

**生产正式版：** 对每个声明为已验证的平台，以上适用功能项全部 PASS，且没有未关闭的
安全、数据丢失或恢复缺陷，才可提交正式发布审批。Ubuntu 通过不替代 Debian，amd64
通过不替代 arm64。若正式版声明当前完整支持矩阵已验收，八个组合均须满足条件；
缺任一组合则整体仍不满足该声明。若希望缩小本次正式发布的已验证范围，必须单独
确认并同步发布说明和支持声明，不能默认将 Debian 排除。RC 必须明确仍未验收的组合。

实际发布前再完成以下交付项：

- [ ] 汇总各平台验收表、G-01～G-06 处置、未决问题、明确延期及运维限制，
      发布者确认对应 RC/正式版结论。
- [ ] 获得版本变更授权后同步 VERSION 与 CHANGELOG，冻结最终候选；最终候选门禁通过。
- [ ] 审查待发布文件和差异，无密钥、完整分享链接、备份、日志或临时测试产物。
- [ ] 与仓库所有者确认安全设置及私密漏洞报告渠道；未核实项明确记录，不擅自改账号设置。
- [ ] 核对说明中的安装 ref 指向获准候选/tag，备份敏感性、同架构恢复、人工防火墙及
      人工恢复边界准确；不承诺自动跨进程恢复、跨架构迁移或未实现功能。
- [ ] 对具体候选取得发布授权后，创建 annotated tag 并从该 tag 发布源码；
      不自动打 tag、不上传旧工作区归档、不部署生产节点。

发布结论以 TASKS 中逐项、逐平台的最新证据为准，不能将此清单的定义当作通过记录。
ARM64 真实重启、未完成的验收项及外部客户端结果仍约束正式版声明。
