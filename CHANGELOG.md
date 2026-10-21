# 变更记录

本文件记录本分支（`Potato1008ypy/dsh-purge-0.2.1rc2-fix`）的版本变更。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循上游 `1.1.71` 并附加适配后缀。

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
