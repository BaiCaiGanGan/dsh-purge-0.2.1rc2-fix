# 安装说明（DSH Desktop 0.2.1-rc.2）

英文版见 [INSTALL.en.md](INSTALL.en.md)。

> **本文件依据第二台机器的实机复现流程修订**（2026-10-19，DSH Desktop 2.0.18 / dsh 0.2.1-rc.2，全程跑通）。
> 三条修正见下方 [⚠️ 三条会卡住你的坑](#-三条会卡住你的坑) —— 尤其第 1 条：**桌面端的 `desktop` profile 不能用普通 CLI 管理**。

## 这个包是什么

- 基于上游 [dsh-purge](https://github.com/YuJunZhiXue/dsh-purge) `1.1.71`（commit `6c1d638`，MIT）
- 叠加 6 处针对 **DSH Desktop 0.2.1-rc.2** 的适配修复 —— 见 [FORK-NOTES.md](FORK-NOTES.md) 与 [FIXES.md](FIXES.md)
- **不要**直接 `pnpm add dsh-purge`，那是上游未修复版

## 第 0 步 · 确认版本

修复针对 **0.2.1-rc.2**（代码写成版本自适应）。**不要**装到比 `0.2.0` 更老的 DSH 上。

---

## ⚠️ 三条会卡住你的坑

### 坑 1 · 桌面端的 `desktop` profile 被 CLI 锁了

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

**只有 Electron 载体传入 `manageDesktopProfile: true` 才放行**，而唯一的放行者是桌面端自带的封装：

```
<DSH 安装目录>\resources\app\lib\desktop-cli.js
```

**兜底要么用它，要么走 GUI 的插件面板。** 对照表：

| 入口 | `--profile desktop` | 其它 profile（`web` 等） |
|---|---|---|
| `<app>\node_modules\@deepseek-ai\dsh\lib\bin.js` | ❌ 被拒 | ✅ 可用 |
| `<app>\lib\desktop-cli.js` | ✅ **唯一入口** | ✅ 可用 |
| GUI 插件面板 | ✅ | ✅ |
| dsh-market「已安装」页 | ✅ | ✅ |

### 坑 2 · 在 PowerShell 里 `& "DSH Desktop.exe" -e "…"` 会静默无输出

`DSH Desktop.exe` 是 **GUI 子系统程序**，PowerShell 的 `&` 既不等待、也不捕获 stdout；`$LASTEXITCODE` 会是空。`cmd /c` 同样不等待，`start /wait` 拿不到 stdout。

**所以：**

- 查状态 → 用**纯 PowerShell 读 JSON**（见第 5 步），不依赖 node / Electron
- 跑脚本 → 用 **`node`**，或者下面那个 `.bat`

### 坑 3 · 存成 `.ps1` 的片段里不要用中文标签

代码直接粘进 PowerShell 窗口执行没问题，但**存成 `.ps1` 时 PowerShell 5.1 会按 ANSI 读 UTF-8 无 BOM 的中文**，直接报「字符串缺少终止符」之类的语法错误。

片段里的输出标签一律写 **ASCII**（`clean` / `MISSING <- problem`）。

---

## 第 1 步 · 找路径、确认 profile 名

```powershell
# DSH 装在哪（不在 D:\DSH Desktop 时才需要）
Get-ChildItem "$env:LOCALAPPDATA\Programs","$env:ProgramFiles","D:\" -Filter "DSH Desktop.exe" -Recurse -ErrorAction SilentlyContinue -Depth 3 | Select -First 3 FullName

# profile 有哪些
Get-ChildItem "$env:USERPROFILE\.dsh\profiles" -Directory | Select Name
```

然后设两个变量：

```powershell
$DSH_BIN = "D:\DSH Desktop\DSH Desktop.exe"
$DCLI    = "D:\DSH Desktop\resources\app\lib\desktop-cli.js"   # 唯一能管理 desktop profile 的入口
```

## 第 2 步 · 放一个 helper（强烈建议）

后面所有「跑 CLI」都用它，绕开坑 2。任意目录建 `dsh-plugin.bat`，**路径换成你机器上的**：

```bat
@echo off
REM dsh plugin helper for the desktop (reserved) profile.
REM Usage: dsh-plugin.bat plugin --profile desktop <pnpm-args...>
set ELECTRON_RUN_AS_NODE=1
"D:\DSH Desktop\DSH Desktop.exe" "D:\DSH Desktop\resources\app\lib\desktop-cli.js" %*
```

`%*` 能正确转发带引号的 github spec，实测通过：

```bat
dsh-plugin.bat plugin --profile desktop list
dsh-plugin.bat plugin --profile desktop add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix"
```

## 第 3 步 · 备份（必做）

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop"
Copy-Item package.json  "package.json.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item pnpm-lock.yaml "pnpm-lock.yaml.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
```

## 第 4 步 · 卸载旧版（替换安装时才需要）

### 首选：dsh-market 的卸载

界面：**已安装** 页 → 找到 `dsh-purge` → **卸载**。

它底层调的就是同一条命令（`routes.js:1444` `runPlugin(config.profile, ['remove', name])`），另外多做的部分对你有好处：

| 市场多做的事 | 价值 |
|---|---|
| 从 `dsh.profile.bundles` 移除 | pnpm 退出码非 0、插件命令没完成调和时，按磁盘真实情况兜底删掉悬空行 |
| 卸载前检查用户 `cordis.patch.yml` | 防止下次启动因悬空引用而崩 |
| 清它自己写过的补丁行 | 只删带 `disabled:` 的行 |

**但要先看 DSH 现在能不能打开：**

- **能开** → 直接用市场卸载
- **开不了**（旧版本的重复 `- insert:` 块会让 profile 组装失败）→ 先编辑 profile 的 `package.json`，把 `dsh-purge` 从 `bundles` **移进** `desktopDeselectedBundles`，就能开、也能进市场面板，再卸载

  ```json
  "profile": { "bundles": [ /* 去掉 dsh-purge */ ] },
  "desktopDeselectedBundles": ["dsh-purge"]
  ```

  > 走了这条路，第 6 步「确认 bundles」可以跳过 —— 手动摘掉本身就完成了市场那条命令没做到的那一半。

市场卸载有两道 **409 保护**（都不是错误）：

1. 用户 `cordis.patch.yml` 读不成合法补丁列表 → 可「强制卸载」穿过
2. 用户 `cordis.patch.yml` 通过 `insert` 引用了 `dsh-purge` → **不可强制**，市场明确「不会自动改写用户补丁」，得先手删那几行

### 备选：CLI

```bat
dsh-plugin.bat plugin --profile desktop remove dsh-purge
```

> **本来就没装的话这条会报错退出**，这是正常的，说明干净，不是失败：
> ```
> [ERR_PNPM_CANNOT_REMOVE_MISSING_DEPS] Cannot remove 'dsh-purge': no such dependency found
> ```

### 卸完必查：本地目录装法要手动清

如果原来的依赖是 `file:../../plugins/dsh-purge` 这种**本地目录装法**，`remove` 不会删那个目录：

```powershell
Get-ChildItem "$env:USERPROFILE\.dsh\plugins" -ErrorAction SilentlyContinue
```

有 `dsh-purge` 就自己处理掉（`Remove-Item -Recurse` 或改名留作备份）。

## 第 5 步 · 装修复版

```bat
dsh-plugin.bat plugin --profile desktop add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix"
```

**实测 6.5 秒**，`bundles` 会自动写入，不用手改 `package.json`。

**GitHub 拉不动时**（国内网络）换 tarball：

```bat
dsh-plugin.bat plugin --profile desktop add "https://github.com/Potato1008ypy/dsh-purge-0.2.1rc2-fix/releases/latest/download/dsh-purge-dsh0.2.1rc2-fix.tar.gz"
```

> 这是**稳定地址**，不带版本号 —— 以后升级版本，命令和文档都不用改。
> GUI 路线：**插件面板 → 添加插件** → 粘贴上面任一条 → 安装 → 立即启用。
>
> 宿主装插件走的是 pnpm，`github:` 这种源会先做一次 GitHub 连通性检查（默认 5 秒超时）。
> 国内网络下如果卡在检查上，直接用上面那条 tarball 地址，或到
> **设置 → 插件 → 插件配置 → GitHub 加速** 填一个 HTTPS 前缀。

## 第 6 步 · 确认 bundles（最后一道保险）

**纯 PowerShell 读 JSON，不依赖 node / Electron**（避开坑 2）：

```powershell
$p = Get-Content "$env:USERPROFILE\.dsh\profiles\desktop\package.json" -Raw | ConvertFrom-Json
'dep   : ' + $(if ($p.dependencies.'dsh-purge') { $p.dependencies.'dsh-purge' } else { 'MISSING <- problem' })
'bundle: ' + $(if (($p.dsh.profile.bundles) -contains 'dsh-purge') { 'has dsh-purge' } else { 'MISSING <- problem' })
```

装完立刻应该长这样（CLI 自己写的）：

```
dep   : github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix
bundle: has dsh-purge
```

**两行都不能是 `MISSING`。** 漏了 `bundles` 就是「装了但没生效」的头号原因 —— 缺的话手动加进 `dsh.profile.bundles` 数组。

## 第 7 步 · 修旧预设

机器上很可能有一份**带 `toolFilter` 的旧预设副本**，剥掉它：

```powershell
node "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-purge\dsh-purge-repair.mjs" --fix
```

> **必须用 `node`**（先 `where node` 确认），**别用 `& $DSH_BIN`** —— 输出会被 PowerShell 丢掉（坑 2）。
>
> 自愈工具需要一个 yaml 解析器。它会先试 `DSH 安装目录\resources\app\node_modules\yaml\dist\index.js`，
> 所以**DSH 装在非默认路径、又用真 node 跑时**，找不到解析器就会报
> `✗ 找不到 yaml 解析器`。这时改用桌面端自带的 node：
> ```powershell
> $env:ELECTRON_RUN_AS_NODE=1; & $DSH_BIN "...\dsh-purge-repair.mjs" --fix
> ```
> （把输出重定向到文件再看，绕开坑 2。）

不带 `--fix` 就是**检查模式**，只报不改。装完先跑检查模式更稳：

```
# 检查模式，有脏预设时
✗ C:\Users\<你>\.dsh\.agent-presets\redteam\agent.cordis.yml
  第 314 行: toolFilter: —— 写进 Config 会让整行 throw
发现 1 处问题，未修改（加 --fix 执行修复）。

# --fix 之后
  ✓ 已剥离（备份 agent.cordis.yml.dsh-purge-repair.bak）
已修复 1 个文件。**重启 DSH 生效**
```

## 第 8 步 · 完全退出 DSH 再启动

`lib/**` 和 `cordis.patch.yml` **只在启动时读盘**，不重启不生效。

---

## 验证

### 1 · 配置块唯一

```bat
dsh-plugin.bat plugin --profile desktop list
```

应看到 `dsh-purge@1.1.71`。离线查看组合结果（不启服务）：

```powershell
$env:ELECTRON_RUN_AS_NODE=1
& $DSH_BIN $DCLI --profile desktop --dump-config > "$env:TEMP\dump.txt" 2>&1
Select-String -Path "$env:TEMP\dump.txt" -Pattern '^- id: dsh-purge'
```

应恰好 4 条：`dsh-purge` / `-redteam` / `-redteam-store` / `-redteam-ui`。打开面板也该每项只出现一次；出现两次 → 重跑第 7 步的检查模式。

### 2 · 宿主日志干净

日志：`%APPDATA%\DSH Desktop\logs\host\dsh-<今天>.log`

⚠️ **日志是追加的，旧告警还留在同一个文件里。** 别整文件 grep 就以为没修好，要**只看本次启动之后**的那一段。

**最可靠的做法**：重启前记下行数，重启后只看新增部分。

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

四类告警**都应该是 `clean`**。

启动成功的正向证据（正向全绿比反向 grep 更可信）：

```
[dsh-purge-redteam] redteam-mode: 就绪（数据目录默认 $DSH_HOME/redteam；预设 …；技能目录 …）
[dsh-purge-redteam] redteam-mode: declared for mode dropdown: 红队模式
```

### 3 · 工作目录正常

系统提示词尾部应该是 `Your working directory is <真实路径>.` —— 不是 `{ {cwd}}`，也不是空。

### 4 · 插件自检（在设置面板里看）

打开 **dsh-purge 的设置面板**，里面那一行补丁注册表应该是：

```
补丁 / patches: 59/59 applied, 0 pending
```

同处还能看到 shim 目录、备份、`inject: prompt-inject.md` 状态为 `default`。
**重启后补丁层应当全部自动重打、没有 pending** —— 有 pending 就说明要走面板上的「应用」。

> 这一行长这样（源码 `lib/index.js:152`）：`` `补丁 / patches: ${applied}/${total} applied, ${pending} pending` ``。
> 它是**面板输出**，不是 `--dump-config` 的输出 —— 别用上面那条命令去等这行字。

---

## 出问题按这个顺序退

**① DSH 打不开了** → 编辑 profile 的 `package.json`，把 `dsh-purge` 从 `bundles` **移进** `desktopDeselectedBundles`（见第 4 步）。能打开之后再回头查。

**② 想整个退回** → 用第 3 步的备份覆盖回去：

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop"
Copy-Item (Get-ChildItem "package.json.bak-*" | Sort-Object LastWriteTime | Select -Last 1) package.json -Force
```

**③ 实在不行：离线拷目录**

```
dsh-purge-dsh0.2.1rc2-fix.tar.gz   ← 解压后整个目录丢进
<DSH_HOME>\profiles\desktop\node_modules\dsh-purge\
```

---

## 两个已确认的机制（免得你误判成故障）

**① 桌面端不会进「打补丁 → 重启 → 再打补丁」的死循环。** 源码里明确禁掉了：

```js
// lib/settle-policy.js
/** 桌面启动自愈不得 requestRestart / taskkill，否则 Cordis 会 INACTIVE_EFFECT。 */
export function settleMayRestart({ surface, sealed = false } = {}) {
  if (surface === "desktop") return false;
```

**② 安装会刷新补丁版本戳。** `$DSH_HOME\dsh-purge\installed-rev` 会从旧值刷成 `apply:1.1.71`（`lib/reapply.js:18`）。这个戳和宿主的对齐判断有关，**别手动改它**。

**③ 安装时 pnpm 顺手清残留包是正常的。** 实测报过 `Packages: +1 -10`（清掉 10 个残留），顶层依赖与 `bundles` 都没受影响。

---

## 原版 DSH（非 Desktop）上的差异

原版 DSH 和 DSH Desktop 是**同一个包** `@deepseek-ai/dsh` `0.2.1-rc.2`，`bundles` 组合逻辑也在这个包里。差异只有三处：

**① 没有桌面锁，普通 CLI 直接可用**（坑 1 不适用）：

```bash
dsh plugin --profile web add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix"
```

profile 名通常是 `web`（`dsh web` = `dsh --profile web`），按第 1 步的实际结果替换。

**② 适配器自动切到 web。** 插件按 surface 选适配器：

```js
const ADAPTERS = { web, desktop };
export function hostAdapter(kind = detectSurface()) {
  return ADAPTERS[adapterFor(kind)] || web;   // 非桌面一律回退 web
}
```

实测判定：原版 CLI → `web`；DSH Desktop → `desktop`。所以**第 5 处修复（认同 `DSH Desktop.exe`）在原版上是无作用也不出错**的，其余五处照常生效。

**③ 重启方式不同。** 桌面端有 asar 拆换与「模块已加载」守卫；原版走 `web.js` 的进程重启（`restartArgv` + `spawnRestartHelper`）。**所以原版上第 8 步更要老实做**，别指望面板点一下就够。

日志路径也不同，按原版实际位置找。

---

## 收尾提醒

- **千万别点市场的「更新」** —— 你 fork 和上游版本号都是 `1.1.71`，一键更新会把修复覆盖掉。等这类 fork 进入精选列表后就没这个风险了（市场按仓库区分同名插件）。
- **数据不会丢** —— profile 目录、会话、`redteam` 那个 SQLite 都在 `$DSH_HOME` 下，与插件版本无关。
- **手改过的预设/提示词不会被覆盖** —— 宿主「模板改了不动用户副本」，所以第 7 步才要用自愈工具单独处理旧格式。
- **升级 DSH 后重跑第 7 步的检查模式**。上游 `master` 还是 `1.1.71`，仍然带着这些缺陷。
- **别删 `cordis.patch.yml.dshpurge.bak`** —— 宿主 `loadOverlayPatches()` 有兜底：主文件读不出来时会去读这个 `.dshpurge.bak`。
