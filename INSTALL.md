# 安装说明

本文件是完整参考：入口选择、验收步骤、旧版本迁移、卸载与故障排查。
**只想尽快装完，读 [QUICKSTART.md](QUICKSTART.md)**。英文版见 [INSTALL.en.md](INSTALL.en.md)。

| 项 | 值 |
|---|---|
| 适用宿主 | DSH `0.2.1-rc.2`（DSH Desktop 与 dsh CLI） |
| 插件版本 | `1.1.71-dsh0.2.1rc2-fix.7` |
| 前置条件 | Node.js ≥18（Windows 无闪窗需 ≥22）；可访问 GitHub，或已下载 Release 的 tarball |
| 预计耗时 | 首次安装约 2 分钟，另需一次 DSH 完整重启 |
| 相关文档 | [QUICKSTART.md](QUICKSTART.md) · [FIXES.md](FIXES.md) · [FORK-NOTES.md](FORK-NOTES.md) · [CHANGELOG.md](CHANGELOG.md) |

# 本包说明

- 基于上游 [dsh-purge](https://github.com/YuJunZhiXue/dsh-purge) `1.1.71`（commit `6c1d638`，MIT）
- 叠加 9 处针对 **DSH Desktop 0.2.1-rc.2** 的适配修复，见 [FIXES.md](FIXES.md)
- 与上游同名同版本，**不要**执行 `pnpm update dsh-purge`，也不要在市场点「更新」——都会用上游版本覆盖修复

---

# 一 · 准备

## 1.1 确认宿主版本

修复针对 `0.2.1-rc.2`（代码写成版本自适应），**不要**装到比 `0.2.0` 更老的 DSH 上。

## 1.2 确认安装路径与 profile 名

```powershell
# DSH 装在哪（下文所有 <DSH 安装目录> 都换成这里查到的路径）
Get-ChildItem "$env:LOCALAPPDATA\Programs","$env:ProgramFiles","D:\" -Filter "DSH Desktop.exe" -Recurse -ErrorAction SilentlyContinue -Depth 3 | Select -First 3 FullName

# profile 有哪些
Get-ChildItem "$env:USERPROFILE\.dsh\profiles" -Directory | Select Name
```

记下两个变量，后续命令会用到：

```powershell
$DSH_BIN = "<DSH 安装目录>\DSH Desktop.exe"
$DCLI    = "<DSH 安装目录>\resources\app\lib\desktop-cli.js"   # 唯一能管理 desktop profile 的入口
```

## 1.3 备份 profile（必做）

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop"
Copy-Item package.json  "package.json.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item pnpm-lock.yaml "pnpm-lock.yaml.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
```

---

# 二 · 安装

按推荐顺序，四条装法任选一条：

| 顺序 | 装法 | 装包 | 登记 `bundles` | 备注 |
|---|---|---|---|---|
| **1** | 2.0 `install.ps1` | ✅ | ✅ 自动 | 一条命令、自动探测；需先退出 DSH |
| **2** | 2.1 `pnpm add` | ✅ | ❌ | 最直接；装完手动启用一次 |
| **3** | 2.2 桌面端命令行 | ✅ | ✅ 自动 | 需放 helper；需先退出 DSH |
| **4** | 2.3 GUI「插件」页 | ✅ | ✅ 自动 | 仅 profile 未加载原生模块时可用 |

下面这些入口不要用于本插件：

| 入口 | 装包 | 登记 `dsh.profile.bundles` | 启用本插件 |
|---|---|---|---|
| `<app>\node_modules\@deepseek-ai\dsh\lib\bin.js` | ❌ 被拒（desktop） | — | — |
| dsh-market（插件市场） | ✅ | ❌ | ❌ |

> **dsh-market 的「启动」对本插件无效。** 它只尝试热挂载（`dshmarket/lib/routes.js:773`），失败即保持
> 禁用且不写 `dsh.profile.bundles`；本插件的 patch 含 `inject` 与 `config`，热挂载必然失败。
> 装/卸可以用它，**启用请走 2.0 或 2.2（它们会写 `bundles`）**，或手动登记。原因见附录 A.1。

## 2.0 一键安装（Windows）

`install.ps1` 把整条链路做完：

```
探测安装目录 → 判定桌面端 / 原版 CLI → 选出 profile → pnpm add → 写 dsh.profile.bundles
```

最后一步是关键：`dsh.profile.bundles` 一登记，插件重启后随 profile 自动加载，省掉手动到「插件」页点启用。

脚本还会做四件事，都在装之前或装之后立即发生：

| 行为 | 位置 / 说明 |
|---|---|
| **安装前快照** | `$DshHome\backups\install-<时间戳>\`，含 `package.json`、`pnpm-lock.yaml`、`pnpm-workspace.yaml`。取的是**装之前**的现场，可直接回滚 |
| **解除禁用** | 若 `dsh.desktopDeselectedBundles` 里有本插件，一并摘掉；只写 `bundles` 而留着禁用项，重启后仍是禁用状态 |
| **认 `DSH_HOME`** | 显式 `-DshHome` > 环境变量 `DSH_HOME` > 默认 `~\.dsh`；子进程沿用同一个值 |
| **兜底包缓存** | `-FromRelease` / git 兜底下载的包放在 `$DshHome\cache\plugins\`，**不放临时目录**——这个路径会被写进 `dependencies`，临时目录一清就装不回来 |
| **UTF-8 与路径定位** | 配置文件一律显式按 UTF-8 读写（5.1 默认按系统 ANSI 解码，无 BOM 的中文会被读坏）；改写只动 `dsh.profile.bundles` 与 `dsh.desktopDeselectedBundles` 两个数组，其它字段逐项比对不变才落盘 |

```powershell
# 先完全退出 DSH；脚本会检测，未退出则拒绝执行
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

没有仓库也行，一行拉取并执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -UseB https://raw.githubusercontent.com/BaiCaiGanGan/dsh-purge-0.2.1rc2-fix/main/install.ps1 -OutFile $env:TEMP\dsh-purge-install.ps1; & $env:TEMP\dsh-purge-install.ps1"
```

> **为什么不是 `irm … | iex`**：`irm` 把脚本读进内存时按系统 ANSI 解码，脚本里的中文会变成乱码；
> 必须先落成文件（字节不变、UTF-8 BOM 保留）再执行。想先看将做什么，把结尾换成 `-DryRun`。
> `raw.githubusercontent.com` 不可达时，把地址换成 jsDelivr 镜像：
> `https://cdn.jsdelivr.net/gh/BaiCaiGanGan/dsh-purge-0.2.1rc2-fix@main/install.ps1`
> （把 tag 换成 `main` 即跟随最新提交，但版本不再可复现。）

| 开关 | 作用 |
|---|---|
| `-DryRun` | 只打印将执行的命令，不改任何文件 |
| `-DshInstall "<目录>"` | 自动探测失败时手动指定 DSH 安装目录 |
| `-Mode cli` / `-Mode desktop` | 跳过自动判定，强制某条入口 |
| `-NoBundle` | 只装包、不写 `bundles`（等价裸 `pnpm add`，装完需手动启用） |
| `-Force` | DSH 仍在运行时也继续——会撞 `EPERM`，仅供排障 |
| `-SelfTest` | 对内置样例跑写入逻辑自检，不碰真实 profile |

脚本自带的保护：拒绝远端 tarball 地址（见 7.5）、改动前备份 `package.json`、写入后重新解析校验、失败即回滚、顺手清理 `*_tmp_*` 残留。

装完直接启动 DSH 即可。

## 2.1 路径 A · `pnpm add`（最直接）

```bash
pnpm add "github:BaiCaiGanGan/dsh-purge-0.2.1rc2-fix#main"
```

`pnpm add` 只写 `dependencies`，**不登记** `dsh.profile.bundles`，所以装完必须到「插件」页手动启用一次（第 3 节）。

> **不要用 Release 的 tarball 地址。** 宿主给 pnpm 带 `CI=true`，那条路径会写出缺 `integrity` 的锁文件条目，进而冻结整个 profile（成因与恢复见 7.5）。
> 网络受限时先把压缩包下载到本地，再装本地文件——pnpm 会为本地压缩包写入完整校验值：`pnpm add "file:D:\downloads\dsh-purge-dsh0.2.1rc2-fix.7.tar.gz"`。

## 2.2 路径 B · 桌面端命令行（`desktop-cli.js`）

桌面端的 `desktop` profile 被 CLI 锁定，普通 `dsh plugin --profile desktop …` 会被拒绝；
`desktop-cli.js` 是唯一放行入口。它需以 Electron 的 Node 模式运行，最省事的方式是放一个 helper：

```bat
@echo off
REM dsh plugin helper for the desktop (reserved) profile.
REM Usage: dsh-plugin.bat plugin --profile desktop <pnpm-args...>
set ELECTRON_RUN_AS_NODE=1
"<DSH 安装目录>\DSH Desktop.exe" "<DSH 安装目录>\resources\app\lib\desktop-cli.js" %*
```

`%*` 会原样转发带引号的 spec。装包：

```bat
dsh-plugin.bat plugin --profile desktop add "github:BaiCaiGanGan/dsh-purge-0.2.1rc2-fix#main"
```

> 上面是 `.bat` 里的写法。`::` 开头的行是**批处理注释**，粘进 PowerShell 会报「术语 '::' 不会被识别」。
> 在 PowerShell 里调用必须带 `.\` 前缀（`.\dsh-plugin.bat …`）或写完整路径——PowerShell 不从当前目录执行裸文件名。

GitHub 拉不动时，**不要改用 Release 的 tarball 地址**——宿主给 pnpm 带 `CI=true`，那条路径会写出缺 `integrity` 的锁文件条目，进而冻结整个 profile（成因与恢复见 7.5）。改用本地压缩包：

```bat
:: 先把 dsh-purge-dsh0.2.1rc2-fix.7.tar.gz 下载到本地，再装这个本地路径
dsh-plugin.bat plugin --profile desktop add "file:D:\downloads\dsh-purge-dsh0.2.1rc2-fix.7.tar.gz"
```

pnpm 会为本地压缩包写入完整校验值（`CI=true` 下实测同样如此）。若宿主拒绝 `file:` 这种 spec，改用 7.4 的离线目录方式。

这条路径会同时写入 `dependencies` 与 `dsh.profile.bundles`，无需手改 `package.json`。

> helper 不是安装的必需品，但后续验收、迁移、卸载会反复用到它。
> 不放 helper 也可以，但每次都要按附录 A.2 的写法手动拼命令。

## 2.3 路径 C · GUI「插件」页

1. 打开 **「插件」页 → 添加插件**。
2. 粘贴 Git 地址或本地绝对路径。
3. 安装完成后进入第 3 节「启用」。

宿主在添加前会执行一次 `git ls-remote` 连通性检查，默认 5 秒超时；网络不可达时会明确报错。
国内网络若卡在检查上，改用 2.1 的本地压缩包方式，或在 **设置 → 插件 → 插件配置 → GitHub 加速** 填一个 HTTPS 前缀。

> **限制（实测）**：profile 里一旦有被 DSH 加载的原生模块（如 `lightningcss-win32-x64-msvc`，随 web-ui 那类客户端 UI 插件进来），
> 安装会报 `ERR_PNPM_EPERM … rename '…_tmp_…'`：pnpm 要重命名该目录，而运行中的 DSH 正映射着里面的 `.node` 文件。
> GUI 安装要求 DSH 正在运行，构成死锁。这类环境改用 2.0 的脚本，或 2.1 / 2.2。

## 2.4 路径 D · 原版 DSH（无桌面锁）

原版 DSH 上普通 CLI 直接可用，profile 名通常是 `web`，按 1.2 的实际结果替换：

```bash
dsh plugin --profile web add "github:BaiCaiGanGan/dsh-purge-0.2.1rc2-fix#main"
```

其余差异见附录 B。

## 2.5 替换旧版本时：先卸载

全新安装跳过本节。替换安装时，下文第 6 节的卸载步骤**必须先做**，否则可能残留重复的 `- insert:` 块。

---

# 三 · 启用与生效

装包只让文件就位。本插件还需两步才真正生效。

## 3.1 在「插件」页启用

打开 **「插件」页**，找到 `dsh-purge` 并点「启动」。
**不要**在 dsh-market 里点「启动」：它只走热挂载，本插件必然失败，且不会登记 `bundles`。

## 3.2 完整退出并重启 DSH

`lib/**` 与 `cordis.patch.yml` **只在启动时读盘**。关窗口不算重启，需要完全退出进程再启动。

## 3.3 打补丁：清洗 → 应用

重启后，在会话标题旁点 **dsh-purge → 清洗 → 应用**。
补丁写入成功后 DSH 会自动再重启一次。**本插件不自动执行这一步**（`autoApplyOnStart: false`，见 `lib/index.js:928`），每次重装或升级宿主后都需手动确认一次。

---

# 四 · 验收

## 4.1 `package.json` 两行

用纯 PowerShell 读 JSON，不依赖 node 或 Electron：

```powershell
$p = Get-Content "$env:USERPROFILE\.dsh\profiles\desktop\package.json" -Raw | ConvertFrom-Json
'dep   : ' + $(if ($p.dependencies.'dsh-purge') { $p.dependencies.'dsh-purge' } else { 'MISSING <- problem' })
'bundle: ' + $(if (($p.dsh.profile.bundles) -contains 'dsh-purge') { 'has dsh-purge' } else { 'MISSING <- problem' })
```

两行都不应为 `MISSING`。缺 `bundle` 就是「装了但没生效」的头号原因——手动把 `dsh-purge` 加进 `dsh.profile.bundles` 数组即可。

## 4.2 离线回归测试

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-purge"
node test/fixes.test.mjs
```

期望末行 `全部通过：22 passed, 0 failed`，退出码 `0`。覆盖 FIX-07 至 FIX-09，不需要网络，也不需要宿主的 `yaml`。

## 4.3 配置块唯一

```powershell
$env:ELECTRON_RUN_AS_NODE=1
& $DSH_BIN $DCLI --profile desktop --dump-config > "$env:TEMP\dump.txt" 2>&1
Select-String -Path "$env:TEMP\dump.txt" -Pattern '^- id: dsh-purge'
```

应恰好 4 条：`dsh-purge` / `-redteam` / `-redteam-store` / `-redteam-ui`。
面板里每项也应只出现一次；出现两次说明有重复块，重跑第 5 节的检查模式。

## 4.4 宿主日志干净

日志位于 `%APPDATA%\DSH Desktop\logs\host\dsh-<今天>.log`。

⚠️ 日志是**追加**的，旧告警仍留在同一文件里。必须只看本次启动之后的那一段：
重启前记下行数，重启后只检查新增部分。

```powershell
$log = "$env:APPDATA\DSH Desktop\logs\host\dsh-$((Get-Date).ToString('yyyy-MM-dd')).log"
(Get-Content $log).Count          # 重启前记下这个数字，记为 N
# …完全退出 DSH 再启动…
$lines = Get-Content $log
$seg = $lines[N..($lines.Count - 1)]     # 把 N 换成刚才记下的数字
foreach ($pat in 'toolFilter is no longer supported',
                'patch: entry "dsh-purge" not found',
                'patch: entry "redteam-mode" not found',
                'declared but broken') {
  $n = ($seg | Select-String $pat -SimpleMatch).Count
  '{0,-45} {1}' -f $pat, $(if ($n) { "$n STILL PRESENT <- problem" } else { 'clean' })
}
```

四类告警都应为 `clean`。启动成功的正向证据比反向 grep 更可信：

```
[dsh-purge-redteam] redteam-mode: 就绪（数据目录默认 $DSH_HOME/redteam；预设 …；技能目录 …）
[dsh-purge-redteam] redteam-mode: declared for mode dropdown: 红队模式
```

## 4.5 面板补丁注册表

打开 **dsh-purge 的设置面板**，那一行应为：

```
补丁 / patches: 59/59 applied, 0 pending
```

同处还能看到 shim 目录、备份与 `inject: prompt-inject.md` 状态。重启后补丁层应全部自动重打、无 pending；有 pending 说明第 3.3 步还没做。
该行是**面板输出**，不是 `--dump-config` 的内容，不要用 4.3 的命令去等它。

## 4.6 工作目录正常

系统提示词尾部应为 `Your working directory is <真实路径>.`，不是 `{{cwd}}`，也不是空。

---

# 五 · 旧版本迁移：修复旧预设

从旧版本升级时，机器上可能残留一份带 `toolFilter` 的预设副本，需要剥离。
**全新安装可跳过本节。**

先跑检查模式（只报不改）：

```powershell
node "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-purge\dsh-purge-repair.mjs"
```

确有问题再加 `--fix`：

```powershell
node "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-purge\dsh-purge-repair.mjs" --fix
```

典型输出：

```
# 检查模式，有脏预设时
✗ C:\Users\<你>\.dsh\.agent-presets\redteam\agent.cordis.yml
  第 314 行: toolFilter: —— 写进 Config 会让整行 throw
发现 1 处问题，未修改（加 --fix 执行修复）。

# --fix 之后
  ✓ 已剥离（备份 agent.cordis.yml.dsh-purge-repair.bak）
已修复 1 个文件。**重启 DSH 生效**
```

两点注意：

- **必须用 `node`**（先 `where node` 确认），不要用 `& $DSH_BIN`，否则输出会被 PowerShell 丢弃（见附录 A.2）。
- 自愈工具需要一个 yaml 解析器。它会先尝试 `DSH 安装目录\resources\app\node_modules\yaml\dist\index.js`；
  若 DSH 装在非默认路径且用真 node 运行，会报 `✗ 找不到 yaml 解析器`。此时改用桌面端自带的 node：

  ```powershell
  $env:ELECTRON_RUN_AS_NODE=1
  & $DSH_BIN "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-purge\dsh-purge-repair.mjs" --fix > "$env:TEMP\repair.txt" 2>&1
  Get-Content "$env:TEMP\repair.txt"
  ```

---

# 六 · 卸载

## 6.1 首选：dsh-market 的「已安装」页

**已安装** 页 → 找到 `dsh-purge` → **卸载**。它底层执行同一条 `plugin remove`（`routes.js:1444`），并额外处理三件事：

| 市场额外做的事 | 价值 |
|---|---|
| 从 `dsh.profile.bundles` 移除 | pnpm 退出码非 0、插件命令未完成调和时，按磁盘真实情况兜底删掉悬空行 |
| 卸载前检查用户 `cordis.patch.yml` | 防止下次启动因悬空引用而崩 |
| 清它自己写过的补丁行 | 只删带 `disabled:` 的行 |

卸载有两道 **409 保护**，都不是错误：

1. 用户 `cordis.patch.yml` 读不成合法补丁列表 → 可选「强制卸载」穿过
2. 用户 `cordis.patch.yml` 通过 `insert` 引用了 `dsh-purge` → **不可强制**，市场明确不会自动改写用户补丁，需先手删那几行

## 6.2 备选：CLI

```bat
dsh-plugin.bat plugin --profile desktop remove dsh-purge
```

本来就未安装时该命令会报错退出，属正常：

```
[ERR_PNPM_CANNOT_REMOVE_MISSING_DEPS] Cannot remove 'dsh-purge': no such dependency found
```

## 6.3 卸完必查：本地目录装法要手动清

若原依赖是 `file:../../plugins/dsh-purge` 这类**本地目录装法**，`remove` 不会删那个目录：

```powershell
Get-ChildItem "$env:USERPROFILE\.dsh\plugins" -ErrorAction SilentlyContinue
```

存在 `dsh-purge` 时自行处理（`Remove-Item -Recurse`，或改名留作备份）。

---

# 七 · 故障排查

## 7.1 DSH 打不开了

编辑 profile 的 `package.json`，把 `dsh-purge` 从 `bundles` **移进** `desktopDeselectedBundles`，即可启动：

```json
"profile": { "bundles": [ /* 去掉 dsh-purge */ ] },
"desktopDeselectedBundles": ["dsh-purge"]
```

能打开之后再回头排查。走了这条路，4.1 的 `bundle` 检查可跳过——手动摘除本身就等价于完成登记。

## 7.2 装了但没生效

按顺序核对：

1. `dsh.profile.bundles` 是否含 `dsh-purge`（4.1）——没有就是没登记，回第 3.1 节用「插件」页启用
2. 是否完整重启过（3.2），而非只关窗口
3. 是否执行过「清洗 → 应用」（3.3）
4. 面板补丁注册表是否 `59/59 applied, 0 pending`（4.5）

## 7.3 整体回退

用 1.3 的备份覆盖回去：

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop"
Copy-Item (Get-ChildItem "package.json.bak-*" | Sort-Object LastWriteTime | Select -Last 1) package.json -Force
```

## 7.4 离线兜底：直接拷目录

```
dsh-purge-dsh0.2.1rc2-fix.tar.gz   ← 解压后整个目录放入
<DSH_HOME>\profiles\desktop\node_modules\dsh-purge\
```

## 7.5 安装时报 `ERR_PNPM_MISSING_TARBALL_INTEGRITY`

```
[ERR_PNPM_MISSING_TARBALL_INTEGRITY] Cannot install package "dsh-purge@https://…tar.gz":
its lockfile entry has no "integrity" field, so pnpm cannot verify the downloaded tarball.
```

**成因。** 宿主调用 pnpm 时带 `CI=true`（冻结模式）。在这个环境下执行 `pnpm add <远端 tarball 地址>`，pnpm 会把依赖写进锁文件，但 `resolution` 里只有 `tarball`、**没有 `integrity`**——冻结模式跳过了取包与校验那一步。等到真正需要取字节时（换机器、清空 store、`--frozen-lockfile`），pnpm 无法校验内容，于是拒绝。又因为这项校验先于任何 add/remove 执行，**整个 profile 的安装与卸载全部被拒**，连卸载它自己都做不到。

GitHub 源（`github:…`）与本地 `file:` 压缩包都不会触发：前者 pnpm 认得，后者它手上有字节可算。

**恢复。** 把出问题的那条从两个文件里摘掉，再用可靠方式重装。**不要删整个 `pnpm-lock.yaml`**——那会让其余插件全部重新解析版本。要摘的共三处：`importers` 下的依赖条目、`packages` 与 `snapshots` 下的同名键。

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop"
Copy-Item package.json  "package.json.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item pnpm-lock.yaml "pnpm-lock.yaml.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Select-String -Path pnpm-lock.yaml -Pattern "dsh-purge" -Context 0,4   # 先看清是哪几处
```

摘干净后按 2.1（`pnpm add`）或 2.2（桌面端命令行）重装。判据：`pnpm install --frozen-lockfile` 不再报这个错。

报错形态随 pnpm 版本不同：11.20 及更早一次只点名一条；11.21 起由供应链检查一次列出全部违规条目。

## 7.6 收尾提醒

- **数据不会丢**：profile 目录、会话与 `redteam` 的 SQLite 都在 `$DSH_HOME` 下，与插件版本无关。
- **手改过的预设/提示词不会被覆盖**：宿主遵循「模板改了不动用户副本」，所以旧格式需用第 5 节的自愈工具单独处理。
- **升级 DSH 后重跑第 5 节的检查模式**：上游 `master` 仍是 `1.1.71`，缺陷依旧存在。
- **别删 `cordis.patch.yml.dshpurge.bak`**：宿主 `loadOverlayPatches()` 有兜底，主文件读不出时会去读它。

---

# 附录

## A · 桌面端的三条限制

这些是宿主行为，不是本插件的缺陷。日常安装按正文走即可；出问题时需要它们来解释现象。

### A.1 · 桌面端的 `desktop` profile 被 CLI 锁定

```bash
dsh plugin --profile desktop list
# error: profile "desktop" is managed exclusively by the Electron application
```

源码依据（`@deepseek-ai/dsh/lib/bin.js`）：

```js
function rejectElectronProfile(program, profile) {
  if (profile.toLowerCase() === "desktop")
    program.error('error: profile "desktop" is managed exclusively by the Electron application');
}
// 调用点：if (!manageDesktopProfile) rejectElectronProfile(program, profile);
```

只有 Electron 载体传入 `manageDesktopProfile: true` 才放行，而唯一的放行者是桌面端自带的
`<DSH 安装目录>\resources\app\lib\desktop-cli.js`。GUI「插件」页走的是同一条放行路径。

热挂载之所以失败，是因为宿主的准入判定只接受纯 `- insert:` + `id`/`name` 行
（`dshmarket/lib/hot.js:146` 的 `parseSimplePatch()`），而本插件的 patch 含
`inject: [systemPrompt, tools]`、多个 `config:` 与一处 `!!js` 表达式。
其中 `inject` 是 cordis 的服务依赖声明，删掉注入即失效，因此该限制无法在插件侧规避。

### A.2 · `DSH Desktop.exe` 不回传 stdout

`DSH Desktop.exe` 是 **GUI 子系统程序**，PowerShell 的 `&` 既不等待也不捕获 stdout，`$LASTEXITCODE` 会是空；
`cmd /c` 同样不等待，`start /wait` 拿不到 stdout。因此：

- 查状态 → 用纯 PowerShell 读 JSON（4.1），不依赖 node 或 Electron
- 跑脚本 → 用 `node`，或 2.2 的 `.bat` helper；必要时把输出重定向到文件再读

### A.3 · 存成 `.ps1` 时不要用中文标签

片段直接粘进 PowerShell 窗口执行没问题，但**存成 `.ps1` 后 PowerShell 5.1 会按 ANSI 读取无 BOM 的 UTF-8 中文**，
报「字符串缺少终止符」一类语法错误。片段中的输出标签一律用 ASCII（`clean` / `MISSING <- problem`）。

## B · 原版 DSH（非 Desktop）的差异

原版 DSH 与 DSH Desktop 是同一个包 `@deepseek-ai/dsh@0.2.1-rc.2`，`bundles` 组合逻辑也在这个包里。差异三处：

**① 没有桌面锁，普通 CLI 直接可用**（附录 A.1 不适用）：

```bash
dsh plugin --profile web add "github:BaiCaiGanGan/dsh-purge-0.2.1rc2-fix#main"
```

**② 适配器自动切到 web**。插件按 surface 选适配器：

```js
const ADAPTERS = { web, desktop };
export function hostAdapter(kind = detectSurface()) {
  return ADAPTERS[adapterFor(kind)] || web;   // 非桌面一律回退 web
}
```

实测判定：原版 CLI → `web`；DSH Desktop → `desktop`。因此 FIX-05（认同 `DSH Desktop.exe`）在原版上无作用也不出错，其余照常生效。

**③ 重启方式不同**。桌面端有 asar 拆换与「模块已加载」守卫；原版走 `web.js` 的进程重启（`restartArgv` + `spawnRestartHelper`）。
所以原版上第 3.2 节更要老实执行，不能只依赖面板操作。日志路径也不同，按实际位置查找。

## C · 容易误判为故障的三个机制

**① 桌面端不会进入「打补丁 → 重启 → 再打补丁」的死循环**，源码中明确禁用：

```js
// lib/settle-policy.js
/** 桌面启动自愈不得 requestRestart / taskkill，否则 Cordis 会 INACTIVE_EFFECT。 */
export function settleMayRestart({ surface, sealed = false } = {}) {
  if (surface === "desktop") return false;
```

**② 安装会刷新补丁版本戳**。`$DSH_HOME\dsh-purge\installed-rev` 会从旧值刷成 `apply:1.1.71`（`lib/reapply.js:18`）。
该戳与宿主的对齐判断有关，**不要手动修改**。

**③ 安装时 pnpm 顺手清理残留包是正常现象**。曾实测出现 `Packages: +1 -10`（清掉 10 个残留），顶层依赖与 `bundles` 均未受影响。
