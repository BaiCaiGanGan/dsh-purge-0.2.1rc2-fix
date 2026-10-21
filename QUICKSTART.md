# 一页纸装机 · QUICKSTART

> 完整参考（含原版 DSH 差异、救援细节）：[INSTALL.md](INSTALL.md) · [INSTALL.en.md](INSTALL.en.md)
> English below: [One-page install](#one-page-install-english)

**实测环境**：DSH Desktop 2.0.18 / dsh 0.2.1-rc.2 · 2026-10-19 全程跑通
**插件版本**：`1.1.71-dsh0.2.1rc2-fix.7` · **文档索引**：[INSTALL.md](INSTALL.md) · [FIXES.md](FIXES.md) · [FORK-NOTES.md](FORK-NOTES.md) · [CHANGELOG.md](CHANGELOG.md)

---

## ⚠️ 三条会卡住你的坑

| # | 现象 | 原因 / 解法 |
|---|---|---|
| **1** | `dsh plugin --profile desktop …` 报 `managed exclusively by the Electron application` | 桌面端 `desktop` profile 被 Electron 锁了。**必须改用 `<DSH>\resources\app\lib\desktop-cli.js`** 或 GUI 面板 |
| **2** | `& $DSH_BIN -e "…"` 静默无输出，`$LASTEXITCODE` 为空 | `DSH Desktop.exe` 是 GUI 子系统程序，`&` 不等待不捕获 stdout。**查状态用纯 PowerShell 读 JSON，跑脚本用 `node` 或下面的 `.bat`** |
| **3** | 存成 `.ps1` 的中文片段报「字符串缺少终止符」 | PS 5.1 按 ANSI 读 UTF-8 无 BOM。**片段内标签一律 ASCII** |

---

## 准备

> **先把 `<DSH 安装目录>` 换成你自己的。** 下面两个变量和那个 `.bat` 里一共有 **3 处** 要替换。
> 用这一条查（本地程序目录 → Program Files → 常见盘符）：
>
> ```powershell
> Get-ChildItem "$env:LOCALAPPDATA\Programs","$env:ProgramFiles","D:\","C:\" `
>   -Filter "DSH Desktop.exe" -Recurse -ErrorAction SilentlyContinue -Depth 3 |
>   Select -First 3 FullName
> ```

```powershell
$DSH_BIN = "<DSH 安装目录>\DSH Desktop.exe"
$DCLI    = "<DSH 安装目录>\resources\app\lib\desktop-cli.js"
```

建 `dsh-plugin.bat`（后面所有 CLI 都走它，**两处路径同样要换**）：

```bat
@echo off
REM Usage: dsh-plugin.bat plugin --profile desktop <pnpm-args...>
set ELECTRON_RUN_AS_NODE=1
"<DSH 安装目录>\DSH Desktop.exe" "<DSH 安装目录>\resources\app\lib\desktop-cli.js" %*
```

---

## 1 · 备份

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop"
Copy-Item package.json  "package.json.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item pnpm-lock.yaml "pnpm-lock.yaml.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
```

## 2 · 卸旧版

**首选**：dsh-market **已安装** 页 → 卸载。

**DSH 打不开时**先编辑 `package.json` 把 `dsh-purge` 移进 `desktopDeselectedBundles`，就能开、能进面板：

```json
"profile": { "bundles": [ /* 去掉 dsh-purge */ ] },
"desktopDeselectedBundles": ["dsh-purge"]
```

**备选 CLI**：

```bat
dsh-plugin.bat plugin --profile desktop remove dsh-purge
```

> 本来没装会报 `ERR_PNPM_CANNOT_REMOVE_MISSING_DEPS`（exit 1）—— **正常，说明干净**。

**卸完必查**：本地目录装法会留残余（`Get-ChildItem "$env:USERPROFILE\.dsh\plugins"`），有就删。

```powershell
$p = Get-Content "$env:USERPROFILE\.dsh\profiles\desktop\package.json" -Raw | ConvertFrom-Json
'dep   : ' + $(if ($p.dependencies.'dsh-purge') { $p.dependencies.'dsh-purge' } else { '(removed)' })
'bundle: ' + $(if (($p.dsh.profile.bundles) -contains 'dsh-purge') { 'STILL PRESENT <- problem' } else { '(removed)' })
```

**两行都得是 `(removed)`。** 残留 bundle 行会让整个 profile 起不来。

## 3 · 装

最省事是一键脚本：自动探测安装目录、自动写 `bundles`，重启即生效。**先完全退出 DSH**。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

没有仓库就一行拉取执行（`irm … | iex` 不行，中文会乱码；必须先落盘）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -UseB https://raw.githubusercontent.com/Potato1008ypy/dsh-purge-0.2.1rc2-fix/v1.1.71-dsh0.2.1rc2-fix.7/install.ps1 -OutFile $env:TEMP\dsh-purge-install.ps1; & $env:TEMP\dsh-purge-install.ps1"
```

手动命令行（等价于脚本里的装包那一步，但不写 `bundles`，装完要手动启用）：

```bat
dsh-plugin.bat plugin --profile desktop add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix.7"
```

GitHub 拉不动就把压缩包下载到本地再装——**别用 tarball 地址**，宿主带 `CI=true`，那条路径会写出缺 `integrity` 的锁文件条目并冻结整个 profile（见 INSTALL.md 7.5）：

```bat
dsh-plugin.bat plugin --profile desktop add "file:D:\downloads\dsh-purge-dsh0.2.1rc2-fix.7.tar.gz"
```

> 实测 6.5 秒，`bundles` 自动写入。GUI 路线（受限，见 INSTALL.md 2.3）：「插件」页 → 添加插件。

更简单的手动替代（不用 helper、不用关 DSH，但装完要到「插件」页启用一次）：

```bash
pnpm add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix.7"
```

> **别用 dsh-market 点「启动」。** 它只走热挂载（本插件含 `inject`/`config`，必然失败），
> 且那条路径不写 `dsh.profile.bundles`——重启后依然是未启用。启用请用上面的一键脚本或 `.bat`（它们会写 `bundles`）；
> 走 `pnpm add` 的话，到 **GUI「插件」页 → 启动** 补一次。
> 判据就是第 4 步的 `bundle: has dsh-purge`。

## 4 · 确认 bundles

```powershell
$p = Get-Content "$env:USERPROFILE\.dsh\profiles\desktop\package.json" -Raw | ConvertFrom-Json
'dep   : ' + $(if ($p.dependencies.'dsh-purge') { $p.dependencies.'dsh-purge' } else { 'MISSING <- problem' })
'bundle: ' + $(if (($p.dsh.profile.bundles) -contains 'dsh-purge') { 'has dsh-purge' } else { 'MISSING <- problem' })
```

> 走了第 2 步的 `desktopDeselectedBundles` 分支，记得把它从那里**摘掉**。

## 5 · 修旧预设

```powershell
node "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-purge\dsh-purge-repair.mjs" --fix
```

> 先不带 `--fix` 跑一遍是检查模式。**必须用 `node`**，别用 `$DSH_BIN`。
> 报 `✗ 找不到 yaml 解析器`（exit 2）说明 DSH 不在默认路径 —— 改用桌面端自带 node（见 INSTALL.md 第 5 节）。

## 6 · 记下日志行数，然后重启

```powershell
$log = "$env:APPDATA\DSH Desktop\logs\host\dsh-$((Get-Date).ToString('yyyy-MM-dd')).log"
(Get-Content $log).Count        # ← 记下这个数字，记为 N
```

**完全退出 DSH 再启动。** `lib/**` 和 `cordis.patch.yml` 只在启动时读盘。

## 7 · 验证

**离线回归测试**

```bash
cd <DSH_HOME>/profiles/desktop/node_modules/dsh-purge
node test/fixes.test.mjs
```

期望末行 `全部通过：22 passed, 0 failed`。不需要网络。

**配置块唯一**

```bat
dsh-plugin.bat plugin --profile desktop list
```

**日志干净**（`N` 换成第 6 步记的数字）

```powershell
$log = "$env:APPDATA\DSH Desktop\logs\host\dsh-$((Get-Date).ToString('yyyy-MM-dd')).log"
$lines = Get-Content $log
$seg = $lines[N..($lines.Count - 1)]
foreach ($pat in 'toolFilter is no longer supported',
                'patch: entry "dsh-purge" not found',
                'patch: entry "redteam-mode" not found',
                'declared but broken') {
  $n = ($seg | Select-String $pat -SimpleMatch).Count
  '{0,-45} {1}' -f $pat, $(if ($n) { "$n STILL PRESENT <- problem" } else { 'clean' })
}
```

四类**都该是 `clean`**。正向证据：

```
[dsh-purge-redteam] redteam-mode: 就绪（数据目录默认 $DSH_HOME/redteam；…）
[dsh-purge-redteam] redteam-mode: declared for mode dropdown: 红队模式
```

**工作目录**：提示词尾部是 `Your working directory is <真实路径>.`，不是 `{ {cwd}}`。

**插件自检**：dsh-purge 设置面板里那行应是 `补丁 / patches: 59/59 applied, 0 pending`。

---

## 出问题怎么退

| 情况 | 做法 |
|---|---|
| DSH 打不开 | `package.json` 里把 `dsh-purge` 移进 `desktopDeselectedBundles` |
| 整个退回 | `Copy-Item (Get-ChildItem "package.json.bak-*" \| Sort-Object LastWriteTime \| Select -Last 1) package.json -Force` |
| 离线 | 解压 tarball，整个目录丢进 `<DSH_HOME>\profiles\desktop\node_modules\dsh-purge\` |

---

## 四个提醒

1. **千万别点市场的「更新」** —— 两边版本号都是 `1.1.71`，会把修复覆盖掉。
2. **数据不会丢** —— profile、会话、`redteam` 的 SQLite 都在 `$DSH_HOME` 下。
3. **别删 `cordis.patch.yml.dshpurge.bak`** —— 宿主主文件读不出来时会兜底读它。
4. **升级 DSH 后重跑第 5 步检查模式** —— 上游 `master` 仍是 `1.1.71`，仍带这些缺陷。

## 两个别误判成故障的现象

- **桌面端不会进「打补丁 → 重启 → 再打补丁」死循环**：`lib/settle-policy.js` 里 `settleMayRestart()` 在 `surface === "desktop"` 时直接返回 `false`。
- **pnpm 清残留包是正常的**：实测报过 `Packages: +1 -10`。另外 `$DSH_HOME\dsh-purge\installed-rev` 会刷成 `apply:1.1.71`，**别手动改**。

---

# One-page install (English)

> Full reference: [INSTALL.en.md](INSTALL.en.md) · [INSTALL.md](INSTALL.md)

**Verified on**: DSH Desktop 2.0.18 / dsh 0.2.1-rc.2 · 2026-10-19, all steps passed.

## ⚠️ Three gotchas that will stop you

| # | Symptom | Cause / fix |
|---|---|---|
| **1** | `dsh plugin --profile desktop …` → `managed exclusively by the Electron application` | The desktop `desktop` profile is locked to Electron. **Use `<DSH>\resources\app\lib\desktop-cli.js`** or the GUI panel |
| **2** | `& $DSH_BIN -e "…"` prints nothing; `$LASTEXITCODE` empty | `DSH Desktop.exe` is GUI-subsystem, so `&` neither waits nor captures stdout. **Read JSON with plain PowerShell; run scripts with `node` or the `.bat` below** |
| **3** | A Chinese-labelled snippet saved as `.ps1` → "missing string terminator" | PS 5.1 reads UTF-8-without-BOM as ANSI. **Keep snippet labels ASCII** |

## Setup

> **Replace `<DSH install dir>` with your own path first** — 3 places below (2 variables + the `.bat`).
> Find it with:
>
> ```powershell
> Get-ChildItem "$env:LOCALAPPDATA\Programs","$env:ProgramFiles","D:\","C:\" `
>   -Filter "DSH Desktop.exe" -Recurse -ErrorAction SilentlyContinue -Depth 3 |
>   Select -First 3 FullName
> ```

```powershell
$DSH_BIN = "<DSH install dir>\DSH Desktop.exe"
$DCLI    = "<DSH install dir>\resources\app\lib\desktop-cli.js"
```

```bat
@echo off
REM Usage: dsh-plugin.bat plugin --profile desktop <pnpm-args...>
set ELECTRON_RUN_AS_NODE=1
"<DSH 安装目录>\DSH Desktop.exe" "<DSH 安装目录>\resources\app\lib\desktop-cli.js" %*
```

## 1 · Back up

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop"
Copy-Item package.json  "package.json.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item pnpm-lock.yaml "pnpm-lock.yaml.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
```

## 2 · Uninstall the old build

**Preferred**: dsh-market **Installed** page → Uninstall.

**If DSH will not open**, first move `dsh-purge` from `bundles` into `desktopDeselectedBundles` in `package.json`, so it opens and the panel is reachable:

```json
"profile": { "bundles": [ /* dsh-purge removed */ ] },
"desktopDeselectedBundles": ["dsh-purge"]
```

**Or the CLI**:

```bat
dsh-plugin.bat plugin --profile desktop remove dsh-purge
```

> If it was never installed this exits 1 with `ERR_PNPM_CANNOT_REMOVE_MISSING_DEPS` — **normal, it means you were clean**.

**Then check**: a local-directory install leaves its folder behind (`Get-ChildItem "$env:USERPROFILE\.dsh\plugins"`) — delete it if present.

```powershell
$p = Get-Content "$env:USERPROFILE\.dsh\profiles\desktop\package.json" -Raw | ConvertFrom-Json
'dep   : ' + $(if ($p.dependencies.'dsh-purge') { $p.dependencies.'dsh-purge' } else { '(removed)' })
'bundle: ' + $(if (($p.dsh.profile.bundles) -contains 'dsh-purge') { 'STILL PRESENT <- problem' } else { '(removed)' })
```

**Both must read `(removed)`.** A leftover bundle row keeps the whole profile from starting.

## 3 · Install

Least work is the one-click script: it detects the install directory and writes `bundles`, so it takes effect on restart. **Fully quit DSH first.**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

No clone? Fetch and run it in one line (`irm … | iex` will not do — the Chinese text gets mangled; save it to a file first):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -UseB https://raw.githubusercontent.com/Potato1008ypy/dsh-purge-0.2.1rc2-fix/v1.1.71-dsh0.2.1rc2-fix.7/install.ps1 -OutFile $env:TEMP\dsh-purge-install.ps1; & $env:TEMP\dsh-purge-install.ps1"
```

Manual command line (the install step alone — no `bundles`, so enable by hand afterwards):

```bat
dsh-plugin.bat plugin --profile desktop add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix.7"
```

If GitHub will not fetch, download the archive and install it locally — **do not use the tarball URL**: the host passes `CI=true`, and that path writes a lockfile entry without `integrity` and freezes the whole profile (see INSTALL.en.md 7.5):

```bat
dsh-plugin.bat plugin --profile desktop add "file:D:\downloads\dsh-purge-dsh0.2.1rc2-fix.7.tar.gz"
```

> Measured 6.5 s; `bundles` is written automatically. GUI route (limited — see INSTALL.en.md 2.3): **Plugins panel → Add plugin**.

A simpler manual alternative (no helper, no quitting DSH, but you must enable it once on the Plugins page):

```bash
pnpm add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix.7"
```

## 4 · Confirm the bundle row

```powershell
$p = Get-Content "$env:USERPROFILE\.dsh\profiles\desktop\package.json" -Raw | ConvertFrom-Json
'dep   : ' + $(if ($p.dependencies.'dsh-purge') { $p.dependencies.'dsh-purge' } else { 'MISSING <- problem' })
'bundle: ' + $(if (($p.dsh.profile.bundles) -contains 'dsh-purge') { 'has dsh-purge' } else { 'MISSING <- problem' })
```

> If you used the `desktopDeselectedBundles` route in step 2, remove `dsh-purge` from it now.

## 5 · Repair old presets

```powershell
node "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-purge\dsh-purge-repair.mjs" --fix
```

> Run it once without `--fix` first for check mode. **Use `node`**, not `$DSH_BIN`.
> `✗ 找不到 yaml 解析器` (exit 2) means DSH is not at the default path — use the desktop app's own node instead (INSTALL.en.md section V).

## 6 · Note the log line count, then restart

```powershell
$log = "$env:APPDATA\DSH Desktop\logs\host\dsh-$((Get-Date).ToString('yyyy-MM-dd')).log"
(Get-Content $log).Count        # note this number as N
```

**Fully quit DSH and start it again.** `lib/**` and `cordis.patch.yml` are read from disk only at startup.

## 7 · Verify

**Offline regression test**

```bash
cd <DSH_HOME>/profiles/desktop/node_modules/dsh-purge
node test/fixes.test.mjs
```

Expected last line `全部通过：22 passed, 0 failed`. No network needed.

**One config block only**

```bat
dsh-plugin.bat plugin --profile desktop list
```

**Clean log** (replace `N` with the number from step 6)

```powershell
$log = "$env:APPDATA\DSH Desktop\logs\host\dsh-$((Get-Date).ToString('yyyy-MM-dd')).log"
$lines = Get-Content $log
$seg = $lines[N..($lines.Count - 1)]
foreach ($pat in 'toolFilter is no longer supported',
                'patch: entry "dsh-purge" not found',
                'patch: entry "redteam-mode" not found',
                'declared but broken') {
  $n = ($seg | Select-String $pat -SimpleMatch).Count
  '{0,-45} {1}' -f $pat, $(if ($n) { "$n STILL PRESENT <- problem" } else { 'clean' })
}
```

All four should read `clean`. Positive evidence:

```
[dsh-purge-redteam] redteam-mode: 就绪（数据目录默认 $DSH_HOME/redteam；…）
[dsh-purge-redteam] redteam-mode: declared for mode dropdown: 红队模式
```

**Working directory**: the prompt tail should read `Your working directory is <real path>.`, not `{ {cwd}}`.

**Plugin self-check**: the dsh-purge settings panel should show `补丁 / patches: 59/59 applied, 0 pending`.

---

## Rescuing

| Situation | Action |
|---|---|
| DSH will not open | move `dsh-purge` into `desktopDeselectedBundles` in `package.json` |
| Roll everything back | `Copy-Item (Get-ChildItem "package.json.bak-*" \| Sort-Object LastWriteTime \| Select -Last 1) package.json -Force` |
| Offline | extract the tarball, drop the directory into `<DSH_HOME>\profiles\desktop\node_modules\dsh-purge\` |

## Four reminders

1. **Never click the market's "Update"** — both versions are `1.1.71`, so it overwrites the fixes.
2. **No data is lost** — the profile, sessions and the `redteam` SQLite live under `$DSH_HOME`.
3. **Do not delete `cordis.patch.yml.dshpurge.bak`** — the host falls back to it when the main file is unreadable.
4. **Re-run step 5's check mode after upgrading DSH** — upstream `master` is still `1.1.71` with these faults.

## Two things that look like failures but are not

- **Desktop never loops patch → restart → re-patch**: in `lib/settle-policy.js`, `settleMayRestart()` returns `false` outright when `surface === "desktop"`.
- **pnpm sweeping stray packages is normal**: a measured install reported `Packages: +1 -10`. Also `$DSH_HOME\dsh-purge\installed-rev` is rewritten to `apply:1.1.71` — **do not edit it by hand**.
