# Install guide (DSH Desktop 0.2.1-rc.2)

> **In a hurry? See the one-page version: [QUICKSTART.md](QUICKSTART.md)** (this file is the full reference, with rescue detail and plain-DSH differences).

English version of [INSTALL.md](INSTALL.md).

> **Revised from a real end-to-end run on a second machine** (2026-10-19, DSH Desktop 2.0.18 / dsh 0.2.1-rc.2, all steps passed).
> The three gotchas are in [⚠️ Three gotchas that will stop you](#-three-gotchas-that-will-stop-you) — especially #1:
> **the desktop `desktop` profile cannot be managed by the ordinary CLI.**

## What this package is

- Based on upstream [dsh-purge](https://github.com/YuJunZhiXue/dsh-purge) `1.1.71` (commit `6c1d638`, MIT)
- Plus 6 adapter fixes for **DSH Desktop 0.2.1-rc.2** — see [FORK-NOTES.md](FORK-NOTES.md) and [FIXES.en.md](FIXES.en.md)
- **Do not** run plain `pnpm add dsh-purge` — that installs the unfixed upstream build

## Step 0 · Check your version

The fixes target **0.2.1-rc.2** (and are written version-adaptively). Do **not** install this on a DSH older than `0.2.0`.

---

## ⚠️ Three gotchas that will stop you

### Gotcha 1 · The desktop `desktop` profile is locked to the Electron app

```bash
dsh plugin --profile desktop list
# error: profile "desktop" is managed exclusively by the Electron application
```

Source (`@deepseek-ai/dsh/lib/bin.js`):

```js
function rejectElectronProfile(program, profile) {
  if (profile.toLowerCase() === "desktop")
    program.error('error: profile "desktop" is managed exclusively by the Electron application');
}
// call sites:  if (!manageDesktopProfile) rejectElectronProfile(program, profile);
```

**Only the Electron carrier passing `manageDesktopProfile: true` gets through**, and the only thing that does so is the desktop app's own launcher:

```
<DSH install dir>\resources\app\lib\desktop-cli.js
```

**Use that, or the GUI plugin panel.** Which entry point works where:

| Entry point | `--profile desktop` | Other profiles (`web`, …) |
|---|---|---|
| `<app>\node_modules\@deepseek-ai\dsh\lib\bin.js` | ❌ refused | ✅ works |
| `<app>\lib\desktop-cli.js` | ✅ **the only way** | ✅ works |
| GUI plugin panel | ✅ | ✅ |
| dsh-market "Installed" page | ✅ | ✅ |

### Gotcha 2 · `& "DSH Desktop.exe" -e "…"` silently prints nothing in PowerShell

`DSH Desktop.exe` is a **GUI-subsystem** binary, so PowerShell's `&` neither waits for it nor captures stdout, and `$LASTEXITCODE` comes back empty. `cmd /c` does not wait either, and `start /wait` gets no stdout.

**Therefore:**

- To inspect state → read the **JSON with plain PowerShell** (step 6), no node / Electron needed
- To run a script → use **`node`**, or the `.bat` below

### Gotcha 3 · Keep labels ASCII inside `.ps1` files

Snippets pasted straight into a PowerShell window are fine, but **when saved as `.ps1`, PowerShell 5.1 reads UTF-8-without-BOM as ANSI** and dies with errors like "字符串缺少终止符" (missing string terminator).

Use **ASCII output labels** in the snippets (`clean` / `MISSING <- problem`).

---

## Step 1 · Locate paths, confirm the profile name

```powershell
# Where DSH lives (only needed if it is not at D:\DSH Desktop)
Get-ChildItem "$env:LOCALAPPDATA\Programs","$env:ProgramFiles","D:\" -Filter "DSH Desktop.exe" -Recurse -ErrorAction SilentlyContinue -Depth 3 | Select -First 3 FullName

# Which profiles exist
Get-ChildItem "$env:USERPROFILE\.dsh\profiles" -Directory | Select Name
```

Then set two variables:

```powershell
$DSH_BIN = "D:\DSH Desktop\DSH Desktop.exe"
$DCLI    = "D:\DSH Desktop\resources\app\lib\desktop-cli.js"   # the only entry that can manage the desktop profile
```

## Step 2 · Drop in a helper (strongly recommended)

Every "run the CLI" step below uses it, sidestepping gotcha 2. Create `dsh-plugin.bat` anywhere, **with your own paths**:

```bat
@echo off
REM dsh plugin helper for the desktop (reserved) profile.
REM Usage: dsh-plugin.bat plugin --profile desktop <pnpm-args...>
set ELECTRON_RUN_AS_NODE=1
"D:\DSH Desktop\DSH Desktop.exe" "D:\DSH Desktop\resources\app\lib\desktop-cli.js" %*
```

`%*` forwards quoted github specs correctly; verified:

```bat
dsh-plugin.bat plugin --profile desktop list
dsh-plugin.bat plugin --profile desktop add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix"
```

## Step 3 · Back up (mandatory)

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop"
Copy-Item package.json  "package.json.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item pnpm-lock.yaml "pnpm-lock.yaml.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
```

## Step 4 · Uninstall the old build (only when replacing)

### Preferred: uninstall from dsh-market

In the GUI: **Installed** page → find `dsh-purge` → **Uninstall**.

It ultimately calls the very same command (`routes.js:1444` → `runPlugin(config.profile, ['remove', name])`), and what it adds on top works in your favour:

| What the market adds | Why it helps |
|---|---|
| Removes it from `dsh.profile.bundles` | If pnpm exits non-zero and the plugin command never reconciles, it falls back to disk truth and drops the dangling row |
| Inspects the user `cordis.patch.yml` first | Keeps the next boot from dying on a dangling reference |
| Cleans up the patch rows it wrote | Only rows carrying `disabled:` |

**But first check whether DSH opens right now:**

- **It opens** → just uninstall from the market
- **It does not open** (the old build's duplicated `- insert:` block breaks profile composition) → edit the profile's `package.json` first and move `dsh-purge` **out of** `bundles` **into** `desktopDeselectedBundles`; then DSH opens, the market page is reachable, and you can uninstall

  ```json
  "profile": { "bundles": [ /* dsh-purge removed */ ] },
  "desktopDeselectedBundles": ["dsh-purge"]
  ```

  > Having gone that route, you can skip step 6 — moving it out by hand already did the half the market command could not do.

The market uninstall has two **409 guards** (neither is an error):

1. The user `cordis.patch.yml` is not a readable patch list → you can force through
2. The user `cordis.patch.yml` still `insert`s `dsh-purge` → **not forceable**; the market states plainly that it will not rewrite a user patch, so remove those rows by hand first

### Alternative: the CLI

```bat
dsh-plugin.bat plugin --profile desktop remove dsh-purge
```

> **If it was never installed this exits with an error**, which just means you were clean, not that the step failed:
> ```
> [ERR_PNPM_CANNOT_REMOVE_MISSING_DEPS] Cannot remove 'dsh-purge': no such dependency found
> ```

### Always check: a local-directory install leaves its folder behind

If the old dependency was a local-directory install like `file:../../plugins/dsh-purge`, `remove` does **not** delete that folder:

```powershell
Get-ChildItem "$env:USERPROFILE\.dsh\plugins" -ErrorAction SilentlyContinue
```

If `dsh-purge` is there, deal with it yourself (`Remove-Item -Recurse`, or rename it as a backup).

## Step 5 · Install the fixed build

```bat
dsh-plugin.bat plugin --profile desktop add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix"
```

**Measured: 6.5 seconds.** `bundles` is written automatically; no hand-editing `package.json`.

**If GitHub will not fetch** (China networks), use the tarball:

```bat
dsh-plugin.bat plugin --profile desktop add "https://github.com/Potato1008ypy/dsh-purge-0.2.1rc2-fix/releases/latest/download/dsh-purge-dsh0.2.1rc2-fix.tar.gz"
```

> That is the **stable URL** — no version in it, so later version bumps change neither the command nor these docs.
> GUI route: **Plugins panel → Add plugin** → paste either line → Install → Enable now.
>
> Installing goes through pnpm, and a `github:` source first runs a GitHub reachability check (5 s timeout by default).
> If that check is what stalls, use the tarball line, or set an HTTPS prefix under
> **Settings → Plugins → Plugin configuration → GitHub accelerator**.

## Step 6 · Confirm the bundle row (the last safety net)

**Plain PowerShell reading JSON — no node or Electron** (avoids gotcha 2):

```powershell
$p = Get-Content "$env:USERPROFILE\.dsh\profiles\desktop\package.json" -Raw | ConvertFrom-Json
'dep   : ' + $(if ($p.dependencies.'dsh-purge') { $p.dependencies.'dsh-purge' } else { 'MISSING <- problem' })
'bundle: ' + $(if (($p.dsh.profile.bundles) -contains 'dsh-purge') { 'has dsh-purge' } else { 'MISSING <- problem' })
```

Right after a successful install it looks like this (written by the CLI itself):

```
dep   : github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix
bundle: has dsh-purge
```

**Neither line may say `MISSING`.** A missing `bundles` row is the number-one cause of "installed but nothing happened" — add it to the `dsh.profile.bundles` array by hand if needed.

## Step 7 · Repair old presets

The machine probably also holds a **stale preset copy carrying `toolFilter`**. Strip it:

```powershell
node "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-purge\dsh-purge-repair.mjs" --fix
```

> **Use `node`** (confirm with `where node`), **not `& $DSH_BIN`** — PowerShell throws its output away (gotcha 2).
>
> The repair tool needs a yaml parser. It first tries
> `DSH install dir\resources\app\node_modules\yaml\dist\index.js`, so **if DSH is installed at a
> non-default path and you run it with a standalone node**, it fails with
> `✗ 找不到 yaml 解析器` (exit 2). In that case use the desktop app's own node:
> ```powershell
> $env:ELECTRON_RUN_AS_NODE=1; & $DSH_BIN "...\dsh-purge-repair.mjs" --fix > "$env:TEMP\repair.txt" 2>&1; Get-Content "$env:TEMP\repair.txt"
> ```
> (redirect to a file and read it back — that gets around gotcha 2.)

Without `--fix` it is **check mode**: reports, changes nothing. Running check mode first is the safer habit:

```
# check mode, with a dirty preset present
✗ C:\Users\<you>\.dsh\.agent-presets\redteam\agent.cordis.yml
  第 314 行: toolFilter: —— 写进 Config 会让整行 throw
发现 1 处问题，未修改（加 --fix 执行修复）。

# after --fix
  ✓ 已剥离（备份 agent.cordis.yml.dsh-purge-repair.bak）
已修复 1 个文件。**重启 DSH 生效**
```

## Step 8 · Fully quit DSH and start it again

`lib/**` and `cordis.patch.yml` are read from disk **only at startup**; nothing takes effect without a restart.

---

## Verification

### 1 · The config block appears exactly once

```bat
dsh-plugin.bat plugin --profile desktop list
```

You should see `dsh-purge@1.1.71`. To view the composed tree offline (no server started):

```powershell
$env:ELECTRON_RUN_AS_NODE=1
& $DSH_BIN $DCLI --profile desktop --dump-config > "$env:TEMP\dump.txt" 2>&1
Select-String -Path "$env:TEMP\dump.txt" -Pattern '^- id: dsh-purge'
```

Exactly 4 rows: `dsh-purge` / `-redteam` / `-redteam-store` / `-redteam-ui`. The settings panel should also show every item once; twice → re-run step 7's check mode.

### 2 · The host log is clean

Log: `%APPDATA%\DSH Desktop\logs\host\dsh-<today>.log`

⚠️ **The log is append-only, so old warnings stay in the same file.** Do not grep the whole file and conclude the fix failed — look only at the segment **after this boot**.

**The most reliable way**: note the line count before restarting, then look only at the new lines.

```powershell
$log = "$env:APPDATA\DSH Desktop\logs\host\dsh-$((Get-Date).ToString('yyyy-MM-dd')).log"
(Get-Content $log).Count          # note this number before restarting -> N
# …fully quit DSH, start it again…
$lines = Get-Content $log
$seg = $lines[N..($lines.Count - 1)]     # replace N with the number you noted
foreach ($pat in 'toolFilter is no longer supported',
                'patch: entry "dsh-purge" not found',
                'patch: entry "redteam-mode" not found',
                'declared but broken') {
  $n = ($seg | Select-String $pat -SimpleMatch).Count
  '{0,-45} {1}' -f $pat, $(if ($n) { "$n STILL PRESENT <- problem" } else { 'clean' })
}
```

All four should read `clean`.

Positive evidence that the boot succeeded (better than grepping for absence):

```
[dsh-purge-redteam] redteam-mode: 就绪（数据目录默认 $DSH_HOME/redteam；预设 …；技能目录 …）
[dsh-purge-redteam] redteam-mode: declared for mode dropdown: 红队模式
```

### 3 · The working directory is right

The tail of the system prompt should read `Your working directory is <real path>.` — not `{ {cwd}}`, not empty.

### 4 · Plugin self-check (in the settings panel)

Open the **dsh-purge settings panel**. The patch-registry line should read:

```
补丁 / patches: 59/59 applied, 0 pending
```

The same place shows the shim directory, the backup, and `inject: prompt-inject.md` as `default`.
**After a restart every patch layer should re-apply automatically with nothing pending** — anything pending means you need the panel's Apply.

> That line is built as `` `补丁 / patches: ${applied}/${total} applied, ${pending} pending` `` (source `lib/index.js:152`).
> It is **panel output**, not `--dump-config` output — do not wait for it from the command above.

---

## Rescuing a broken install

**① DSH will not open** → edit the profile's `package.json` and move `dsh-purge` from `bundles` **into** `desktopDeselectedBundles` (see step 4). Once it opens, dig in.

**② Roll the whole thing back** → restore the step-3 backup:

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop"
Copy-Item (Get-ChildItem "package.json.bak-*" | Sort-Object LastWriteTime | Select -Last 1) package.json -Force
```

**③ Last resort: copy the directory in by hand (offline install)**

```
dsh-purge-dsh0.2.1rc2-fix.tar.gz   ← extract, then drop the whole directory into
<DSH_HOME>\profiles\desktop\node_modules\dsh-purge\
```

---

## Two confirmed behaviours (so you do not misread them as failures)

**① Desktop never enters a patch → restart → re-patch loop.** It is disabled in source on purpose:

```js
// lib/settle-policy.js
/** 桌面启动自愈不得 requestRestart / taskkill，否则 Cordis 会 INACTIVE_EFFECT。 */
export function settleMayRestart({ surface, sealed = false } = {}) {
  if (surface === "desktop") return false;
```

**② Installing refreshes the patch revision stamp.** `$DSH_HOME\dsh-purge\installed-rev` is rewritten from its old value to `apply:1.1.71` (`lib/reapply.js:18`). That stamp feeds the host's alignment check — **do not edit it by hand**.

**③ pnpm cleaning up stray packages is normal.** A measured install reported `Packages: +1 -10` (10 leftovers swept); neither the top-level dependency nor `bundles` was affected.

---

## Differences on plain DSH (not Desktop)

Plain DSH and DSH Desktop are **the same package**, `@deepseek-ai/dsh` `0.2.1-rc.2`, and the `bundles` composition logic lives in it too. Only three things differ:

**① No desktop lock, so the ordinary CLI works** (gotcha 1 does not apply):

```bash
dsh plugin --profile web add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix"
```

The profile is usually `web` (`dsh web` = `dsh --profile web`); substitute whatever step 1 showed.

**② The adapter switches to web automatically.** The plugin picks an adapter per surface:

```js
const ADAPTERS = { web, desktop };
export function hostAdapter(kind = detectSurface()) {
  return ADAPTERS[adapterFor(kind)] || web;   // anything non-desktop falls back to web
}
```

Measured: plain CLI → `web`; DSH Desktop → `desktop`. So **fix 5 (recognising `DSH Desktop.exe`) is inert but harmless on plain DSH**; the other five apply as usual.

**③ Restarting works differently.** Desktop has asar swapping and a "module already loaded" guard; plain DSH uses `web.js` process restart (`restartArgv` + `spawnRestartHelper`). **So on plain DSH, step 8 matters even more** — do not expect the panel's restart to be enough.

The log path differs too; find it where plain DSH actually writes it.

---

## Closing notes

- **Never click the market's "Update"** — your fork and upstream are both `1.1.71`, so a one-click update overwrites the fixes. That risk goes away once a fork like this lands in the curated catalog (the market tells same-named plugins apart by repository).
- **No data is lost** — the profile directory, sessions and the `redteam` SQLite all live under `$DSH_HOME`, independent of the plugin version.
- **Hand-edited presets and prompts are not overwritten** — the host will not touch a user copy when the template changes, which is exactly why step 7 exists to handle old-format copies separately.
- **Re-run step 7's check mode after upgrading DSH.** Upstream `master` is still `1.1.71` and still carries these faults.
- **Do not delete `cordis.patch.yml.dshpurge.bak`** — the host's `loadOverlayPatches()` falls back to that `.dshpurge.bak` when it cannot read the main file.
