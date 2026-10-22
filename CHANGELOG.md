# 变更记录

本文件记录本分支（`Potato1008ypy/dsh-purge-0.2.1rc2-fix`）的版本变更。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循上游 `1.1.71` 并附加适配后缀。

## [未发布·改进]

这一轮针对"破甲看起来正常、其实失效"和"关键约束被长文稀释"两个问题。

### 修正

- **锚点漂移以前是静默的**。`patchStatus()` 会产出 `unmatched` / `pattern_not_found` / `missing_file` 等状态，
  但 `gatherState()` 只统计 applied / pending / skipped ——**前两类不进任何计数**。宿主升级改掉锚点后，
  补丁没打上，状态页照旧显示"0 待清洗"。现在新增 `classifyPatchOutcome()` 纯函数把状态归为
  applied / pending / drifted / skipped / failed 五类，`gatherState()` 输出 `patches_drifted`、
  `patches_failed` 与逐条明细，状态文本、CLI、`/redteam/api` 全部显式列出。
- **`overrideStatus()` 恒返回 "default"**，不描述磁盘：用户看不出文件在不在、是不是内置默认。
  改成三态 `missing` / `default` / `custom`，并新增 `override_plaintext_default` ——
  当默认提示词明文落在 `$DSH_HOME/prompt-inject.md` 时状态里直说（删掉不影响功能，注入回落加密槽）。

### 新增

- **末尾锚点（closing anchors）**：在注入正文结尾重申三条硬约束（请求即任务 / 不输出拒绝与免责 / 工具优先）。
  接点先后修正过两次：最初挂在 `ensureOperatorBody()`（只走兜底，等于没加），
  再挂 `hangOperatorPrompt()`（tier-2 才有），最后统一到 `refreshHungOperator()` 的返回处
  与四重兜底的 `norm()` —— host 侧 tier-1 读的正是 `refreshHungOperator().text`。
  只作用于注入链，不改用户文件；幂等（同一份正文只追加一次），`DSH_PURGE_ANCHOR=0` 可关闭。
- **`scripts/apply-and-verify.ps1`**：把"应用 + 挪归档 + 重启 + 判定"做成入库脚本（自动探测安装目录，
  `-VerifyOnly` 只查、`-InstallRoot` 指定路径、`-Profile` 选 desktop/web）。判定读 `gatherState()` 的
  `effective` / `patches_drifted` / `override_status`，不再靠人眼看数字。桌面上的快捷脚本改为薄封装，
  真正的逻辑随插件走，重装/升级后不会失效。
- 测试：`test/drift-classify.test.mjs`（16 项）、`test/override-status.test.mjs`（5 项）、
  `test/closing-anchor.test.mjs`（6 项）。`npm test` 现为 58 项。

### 已知未做

- 默认提示词 21,194 字符（≈6–9K tokens）的内容精简：涉及全局行为契约，需失败用例集做 A/B，未擅自替换。
- 审批/沙箱放开的审计日志：需要抓工具决策点，单独一轮。

## [未发布]

本轮是复核后的收口：一处"发布出去的客户端不是源码那一版"，一处"迁移写了但从来没执行"，外加元数据与回归网。

### 修正

- **`client.js` 是旧构建产物**。`client.js` 由 `scripts/build-client.mjs` 从 `lib/redteam/client.js` 生成，最后一次改源码后没有重建：仓库里的 `client.js` 与上游 1.1.71 的 `client.js` **逐字节相同**，所以源码里这几处修复在发布物里根本不存在——① 桥接响应用 `res.json()` 直解，非 JSON 错误体（网关 HTML、5xx 纯文本）直接抛异常；② 导出下载后立即 `revokeObjectURL`，部分浏览器断流；③ 倒计时用裸 `setInterval`，弹窗关闭/组件卸载后回调仍在跑。重建后 `client.js` 498880 → 497767 字节，`test/client-build.test.mjs` 从此把"源码改了没重建"挡在提交前。
- **`migrate()` 里两个常量悬空**。`lib/redteam/schema.js` 的 `migrate()` 引用 `LEGACY_STAGE_MAP` 与 `SCOPE_SQL`，但两者原本只声明在 `store-core.js` 的模块作用域，schema.js 既没声明也没 import —— 运行期抛 `ReferenceError`，又被两处 `catch { }` 吞掉。后果是"迁移跑过了但什么都没写"：老库的 `attack_step.stage_code` 与 `asset.scope` 永远是 NULL，只能靠读侧 `COALESCE` 兜。现把两个常量移进 schema.js（它是 store-core 的下游，反向 import 会成环），store-core 从那里取并保持再导出。实测：`pivot → boundary`、`10.0.0.5 → internal` 回填生效。
- **`engines` 与运行时事实不符**。事实库用 `node:sqlite`（Node 22.5 引入，22.13 起免 flag），`engines.node` 却写 `>=18`：Node 18/20 上装得上、插件加载即失败。改为 `>=22.13.0`，并在 `install.ps1` 加一步运行时预检（低于 22.13 只告警不阻断，桌面端自带 Node 22.x 不受影响）。
- **`dsh.install` 指向上游仓库**。`repository` / `homepage` / `bugs` 都指本分支，唯独 `dsh.install.{tarball,zip,git}` 仍指 `YuJunZhiXue/dsh-purge`：市场一键装拿到的会是不适配 0.2.1-rc.2 的上游 master。三处统一到本分支。

### 回归网

- 新增 `test/migrate.test.mjs`（6 项）：常量可见性、stage_code 回填、scope 回填、迁移幂等、显式阶段不被覆盖。
- 新增 `test/fts-fallback.test.mjs`（2 项）：schema.js 注释里早已引用这个文件，实际并不存在；现补上，用 `REDTEAM_NO_FTS5=1` 强制走降级分支。
- 新增 `test/client-build.test.mjs`（2 项）：备份 → 重建 → 字节比对 → 还原，发布物与源码不再允许各走各的。
- 新增 `.github/workflows/ci.yml`：Node 22.13 上跑 `npm test`、重建后 `git diff --exit-code client.js`、`npm pack --dry-run`。
- README / README.zh-CN 版本徽章 `fix.2` → `fix.7`（与 `package.json` 对齐）。

## [1.1.71-dsh0.2.1rc2-fix.7] — 2026-10-21

两条问题由用户复核发现，先复现再修。本轮只动 `install.ps1`，插件运行时逻辑未变。

### 修正

- **配置文件按 ANSI 解码**。两个配置函数都用 `Get-Content -Path $Path -Raw`，Windows PowerShell 5.1 对没有 BOM 的 UTF-8 文件按系统代码页解码：中文字段会被写坏，实测更严重——引号被一并吞掉，`ConvertFrom-Json` 直接报「应为 `:` 或 `}`」，安装卡在写配置这一步（退出码 6）。改为显式 `-Encoding UTF8` 读取。
- **正则没有限定 JSON 路径**。原实现 `("bundles"\s*:\s*\[)` 只匹配文档里第一个同名键：若别处先出现 `"bundles"`，函数会误判「已登记」并返回 false，目标数组仍为空，最终校验报错而安装无法完成（用户给出的复现配置已实测命中偏移 13 的 `other.bundles`）。改为按 `dsh.profile.bundles` / `dsh.desktopDeselectedBundles` 的 JSON 路径解析后改写，落盘前逐项比对其它字段；顺带也不再需要文本手术，行尾风格（LF/CRLF）保持原样。
- **包校验按 OEM 代码页解码**。`Test-PackageTarball` 用 PowerShell 原生捕获 `tar` 输出，UTF-8 会被按 OEM 解码（本机 936）；`name`/`version` 恰好是 ASCII 才没出错。改为 `ProcessStartInfo` + `StandardOutputEncoding=UTF8` 按字节读。

### 自检

- `-SelfTest` 扩到 7 组断言：路径定位（含影子 `bundles`）、中文无损（无 BOM）、无 BOM 写回、原有 BOM 保留、幂等、空数组、缺 `bundles` 时明确报错。

## [1.1.71-dsh0.2.1rc2-fix.6] — 2026-10-21

`install.ps1` 的六个缺陷，全部先复现再修。

### 修正

- **单 profile 被截成首字符**。`$profiles = Get-ProfileCandidates` 在只有一个 profile 时被 PowerShell 展开成字符串，`$profiles[0]` 取到的是第一个字符。实测：只有 `web` 时报 `profile：w（可选：web）`，随后 `$profileDir` 指向不存在的 `profiles\w`。改为 `@(Get-ProfileCandidates)`。
- **备份太晚且不含锁文件**。备份原先在安装之后做，快照里已经含新装的依赖，回滚不回安装前状态；`pnpm-lock.yaml` 完全没有备份。现在安装前先快照 `package.json` / `pnpm-lock.yaml` / `pnpm-workspace.yaml` 到 `$DshHome\backups\install-<时间戳>\`，另保留一份仅用于「写 bundles 失败回滚」的临时快照，成功后删除。
- **不解除 `desktopDeselectedBundles`**。原先只往 `bundles` 里加，若插件同时在禁用列表里，脚本报成功而插件仍被禁用（实测 `bundles: [..., "dsh-purge"]` 与 `deselected: ["dsh-purge"]` 并存）。新增 `Remove-DeselectedEntry` 文本级摘除并二次校验。
- **忽略 `DSH_HOME`**。参数默认写死 `~\.dsh`，随后又覆盖子进程的 `DSH_HOME`，用自定义数据目录的用户会装到错误位置。改为 `-DshHome` > `DSH_HOME` > `~\.dsh`。
- **兜底包落在 %TEMP%**。该路径会写进 `dependencies`，临时目录被清理后重装/恢复依赖找不到包。改为落在 `$DshHome\cache\plugins\`（不可写时退回 `%LOCALAPPDATA%\dsh-purge\cache`）。
- **写入带 BOM 的 JSON**。PowerShell 5.1 的 `Set-Content -Encoding UTF8` 会写 BOM，宿主 `JSON.parse` 直接失败（实测首字符 U+FEFF、`JSON.parse: FAIL`）。改为按原文件是否带 BOM 精确写回，默认无 BOM。

### 其他

- `-SelfTest` 扩充：无 BOM 写回、禁用项摘除、幂等、缺键容错。
- 版本号 `.5` → `.6`。

## [1.1.71-dsh0.2.1rc2-fix.5] — 2026-10-21

### 修正

- **pnpm 日志里的 `✅` 显示成 `鉁?`**。`desktop-cli` 的输出由 `Invoke-DesktopCli` 捕获，未指定编码时 .NET Framework 按系统 OEM 码页（简中 936）解码，UTF-8 的 `✅`（`E2 9C 85`）被拆成 `鉁`（`U+9241`）+ `?`。实测：同一段输出用默认解码首字符是 `37441`，指定 UTF-8 后是 `9989`（`U+2705`）。
  现在给 `StandardOutputEncoding` / `StandardErrorEncoding` 显式指定 UTF-8；`dsh` CLI 分支则只在这一次调用期间把 `[Console]::OutputEncoding` 切到 65001，读完在 `finally` 里还原，不影响脚本自身的中文输出。
- 版本号 `.4` → `.5`。

## [1.1.71-dsh0.2.1rc2-fix.4] — 2026-10-21

基线同上。补一条网络兜底，其余同 `.3`。

### 新增

- **git 不通时的自动兜底**：`install.ps1` 检测到 `ERR_PNPM_GIT_RESOLVE_FAILED`（或 `unable to access` / `Failed to connect` / 超时）后，自动下载本版本发布包并按本地 `file:` 重试一次。发布包按 `ghfast.top` → `gh-proxy.com` → 直连 顺序尝试，下载后校验包名与版本，通过才使用。
- **`-FromRelease` / `-AssetUrl`**：直接走发布包安装，或指定任意可达地址。
- 起因（实测）：目标机器上 `raw.githubusercontent.com` 可通、`github.com:443` 21 秒超时，`github:` 源因此装不上。`file:` 本地压缩包在 `CI=true` 下依然会写入完整 `integrity`，所以这条兜底不会踩 `ERR_PNPM_MISSING_TARBALL_INTEGRITY`。

### 变更

- 版本号 `.3` → `.4`。

## [1.1.71-dsh0.2.1rc2-fix.3] — 2026-10-21

基线同上。本轮只改安装链路与文档，插件运行时逻辑未动。

### 新增

- **`install.ps1` 一键安装脚本**：自动探测 DSH 安装目录（运行中进程 / 常见安装位置 / 注册表），判定桌面端与原版 CLI，选出 profile，执行 `pnpm add`，写入 `dsh.profile.bundles`，最后重新解析校验、失败回滚。开关：`-DryRun`、`-DshInstall`、`-Mode`、`-NoBundle`、`-Force`、`-SelfTest`。脚本自身会拒绝远端 tarball 地址，并在 DSH 仍在运行时拒绝执行。
- **INSTALL 7.5 节**：`ERR_PNPM_MISSING_TARBALL_INTEGRITY` 的成因与恢复。成因是宿主以 `CI=true`（冻结模式）调 pnpm，`pnpm add <远端 tarball 地址>` 因此只写 `tarball`、不写 `integrity`；等到真正取字节时（换机器、空 store、`--frozen-lockfile`）pnpm 拒绝，并因校验收敛而冻结整个 profile 的安装与卸载。恢复方式是从 `importers`、`packages`、`snapshots` 三处摘掉该条，**不要**删整个锁文件。
- **一行安装（不用 clone）**：`powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -UseB <raw url> -OutFile …; & …"`。
  不用 `irm … | iex`：`irm` 按系统 ANSI 解码，脚本内的中文会变成乱码，必须先落盘（字节不变、UTF-8 BOM 保留）再执行。文档同时给出 jsDelivr 镜像地址。

### 变更

- **安装方式推荐顺序重排**：一键脚本 → `pnpm add` → 桌面端命令行 → GUI「插件」页。GUI 由「推荐」降为「受限」：profile 里一旦有被 DSH 加载的原生模块（如 `lightningcss-win32-x64-msvc`），pnpm 重命名该目录必报 `ERR_PNPM_EPERM`，而 GUI 安装又要求 DSH 正在运行，构成死锁。
- 文档里所有「用 Release tarball 地址安装」的建议改为 GitHub 源或本地 `file:` 压缩包；本地压缩包会写入完整 `integrity`（`CI=true` 下实测同样如此）。
- INSTALL 章节重编：2.1 `pnpm add`、2.2 桌面端命令行、2.3 GUI、2.4 原版 DSH、2.5 替换旧版本；交叉引用同步。

### 修正

- 补上 `::` 是批处理注释、不能粘进 PowerShell，以及 PowerShell 调用 `dsh-plugin.bat` 需带 `.\` 前缀的说明。
- GUI 安装在同一页「启动」的措辞改为「启用请走会写 `bundles` 的路径」，避免指向已降级的入口。

## [1.1.71-dsh0.2.1rc2-fix.2] — 2026-10-21

基线：上游 `1.1.71`（commit `6c1d638`）。宿主目标：DSH `0.2.1-rc.2`。

### 新增

- **FIX-07**：`extract-asar.js` 新增 `HOST_FD` 表，单独装配 fd 类方法（`closeSync`、`fsyncSync`、`fdatasyncSync`、`readSync`、`writeSync`、`futimesSync`、`ftruncateSync`）。此前 `hostFs` 缺 `closeSync`，`backupAll()` 的占位句柄无法释放，Windows 下 rename 报 `EPERM`，导致不生成任何 `.dshpurge.bak`。
- **FIX-08**：`presets/redteam/agent.cordis.yml` 将 `tool-workflow` / `tool-ralph` 置为 `disabled: true`（`workflow-ptc` 引擎保留）。二者此前未禁用，子代理可经 `workflow` 绕过 `maxDepth: 1` 递归。
- **FIX-08（自愈）**：`lib/redteam/index.js` 新增 `repairLeafBoundary()`，在非 `force` 路径就地修补已落地的旧预设，保留使用方其它编辑，且幂等。
- 离线回归测试 `test/fixes.test.mjs`（22 项断言，零依赖），接入 `npm test`；`package.json` 的 `files` 增加 `test`。
- `CHANGELOG.md`；README 重构为「正式说明 + 附录 A 上游原文」。

### 修复

- **FIX-09**：`lib/desktop.js` 的 `repairOfficialCliAfterUnpack()` 改用 `atomicWriteSync()`。原实现于同步函数内调用 async `atomicCopyFile()` 且未 `await`，reject 经 `unhandledRejection` 升级为 `uncaughtException`，桌面端点「应用」即 `fatal load failure`。

### 变更

- `package.json` 版本号 `1.1.71` → `1.1.71-dsh0.2.1rc2-fix.2`；补齐 `author` / `contributors` / 仓库 URL / `dshTarget: 0.2.1-rc.2`。
- 文档术语统一：修复项改用稳定编号 `FIX-01` … `FIX-09`。

### 说明

- 发布产物 `dsh-purge-dsh0.2.1rc2-fix.2.tar.gz`；同一 Release 另附同内容的 `dsh-purge-dsh0.2.1rc2-fix.tar.gz` 作为兼容别名，使旧文档中的下载 URL 继续可用。

## [1.1.71-dsh0.2.1rc2-fix] — 2026-10-19

基线：上游 `1.1.71`（commit `6c1d638`）。宿主目标：DSH `0.2.1-rc.2`。

### 修复

- **FIX-01**：`cordis.patch.yml` 合并重复的 `- insert:` 块（1 个 insert 块 / 4 个插件行）。
- **FIX-02**：预设模板移除 `toolFilter` / `persona`（`0.2.1-rc.2` 已从 `tool-subagent` 的 Config 删除该键），并在 `repairDelegation()` 中增加行式剥离以迁移旧格式预设。
- **FIX-03**：插件自行注册 `cwd` 提示词变量；persona 段优先写入字面路径。
- **FIX-04**：补 `0.2.1` 形态的 `#40 COMPLETE_PROMPT_KEEP_INJECT` 锚点；替换体抽为 `completePromptInjectBody()`。
- **FIX-05**：`isOfficialHarnessExecutable` 认可 `DSH Desktop.exe` / `dsh-desktop.exe`。
- **FIX-06**：`assemble()` 异常时按注册顺序重建段表，仅丢弃插值失败的 section。

### 新增

- 补丁注册表新增 `retired` 标记，区分「未命中」与「已退役」（终态 `applied 66 / na 15 / pending 1`）。
- `dsh-purge-repair.mjs` 改为路径自定位，不写死 DSH 安装路径。
- `FIXES.md` / `FIXES.en.md` / `FORK-NOTES.md` / `INSTALL.md` / `INSTALL.en.md` / `QUICKSTART.md`。

### 说明

- 首个发布版本，产物 `dsh-purge-dsh0.2.1rc2-fix.tar.gz`。

---

## 未变更项（有意保留）

| 项 | 现状 | 理由 |
|---|---|---|
| Ctrl+Enter 行为（补丁 `#85` / `#86`） | UI 发送一律走新 turn（`followup`），不打断当前轮次 | 用于抑制「二轮立刻发送被拒」的竞态；回退为 `agent.steer` 会重新引入该竞态。详见 [README.zh-CN.md](README.zh-CN.md) 的「已知限制与设计取舍」 |
| 上游提示词内容 | 未改写 | 本分支只做宿主适配，不改变产品行为 |
| 上游版本号 `1.1.71` | 保留为语义基线，追加适配后缀 | 便于与上游对照；也因此须避免 `pnpm update`（见 README） |
