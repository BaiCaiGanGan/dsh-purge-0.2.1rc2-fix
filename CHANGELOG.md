# 变更记录

本文件记录本分支（`Potato1008ypy/dsh-purge-0.2.1rc2-fix`）的版本变更。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循上游 `1.1.71` 并附加适配后缀。

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
