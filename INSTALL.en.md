# Install guide

This is the full reference: entry-point selection, verification, migration from an older version, uninstalling, and troubleshooting.
**Just want it installed? Read [QUICKSTART.md](QUICKSTART.md).** Chinese original: [INSTALL.md](INSTALL.md).

| Item | Value |
|---|---|
| Target host | DSH `0.2.1-rc.2` (both DSH Desktop and dsh CLI) |
| Plugin version | `1.1.71-dsh0.2.1rc2-fix.2` |
| Prerequisites | Node.js ≥18 (≥22 to avoid a console flash on Windows); GitHub reachable, or the Release tarball already downloaded |
| Time required | About 2 minutes for the first install, plus one full DSH restart |
| Related docs | [QUICKSTART.md](QUICKSTART.md) · [FIXES.en.md](FIXES.en.md) · [FORK-NOTES.md](FORK-NOTES.md) · [CHANGELOG.md](CHANGELOG.md) |

# About this package

- Based on upstream [dsh-purge](https://github.com/YuJunZhiXue/dsh-purge) `1.1.71` (commit `6c1d638`, MIT)
- Plus 9 adapter fixes for **DSH Desktop 0.2.1-rc.2**, see [FIXES.en.md](FIXES.en.md)
- Same name and same version as upstream: **do not** run `pnpm update dsh-purge`, and do not click "Update" in the market — either one replaces these fixes with the upstream build

---

# I · Preparation

## 1.1 Check the host version

The fixes target **0.2.1-rc.2** (and are written version-adaptively). Do **not** install this on a DSH older than `0.2.0`.

## 1.2 Locate the install path and confirm the profile name

```powershell
# Where DSH lives (replace every <DSH install dir> below with what this finds)
Get-ChildItem "$env:LOCALAPPDATA\Programs","$env:ProgramFiles","D:\" -Filter "DSH Desktop.exe" -Recurse -ErrorAction SilentlyContinue -Depth 3 | Select -First 3 FullName

# Which profiles exist
Get-ChildItem "$env:USERPROFILE\.dsh\profiles" -Directory | Select Name
```

Note down two variables; later commands use them:

```powershell
$DSH_BIN = "<DSH install dir>\DSH Desktop.exe"
$DCLI    = "<DSH install dir>\resources\app\lib\desktop-cli.js"   # the only entry that can manage the desktop profile
```

## 1.3 Back up the profile (mandatory)

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop"
Copy-Item package.json  "package.json.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item pnpm-lock.yaml "pnpm-lock.yaml.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
```

---

# II · Installation

The three entry points differ in what they can do — check before choosing:

| Entry point | Installs the package | Writes `dsh.profile.bundles` | Enables this plugin |
|---|---|---|---|
| GUI Plugins page | ✅ | ✅ automatic | ✅ **recommended** |
| `<app>\lib\desktop-cli.js` | ✅ | ✅ automatic | ✅ |
| `<app>\node_modules\@deepseek-ai\dsh\lib\bin.js` | ❌ refused (desktop) | — | — |
| dsh-market | ✅ | ❌ | ❌ |
| `pnpm add` inside `profiles\desktop` | ✅ | ❌ | ❌ |

> **dsh-market's "Enable" cannot work for this plugin.** It only attempts a hot mount
> (`dshmarket/lib/routes.js:773`); on failure it leaves the plugin disabled and never writes
> `dsh.profile.bundles`. This plugin's patch carries `inject` and `config`, so the hot mount always
> fails. Use it to install/uninstall if you like — **enable from the GUI Plugins page**.
> See appendix A.1 for why.

## 2.1 Path A · GUI Plugins page (recommended)

1. Open the **Plugins page → Add plugin**.
2. Paste a Git URL, the Release archive URL, or an absolute local path.
3. When the install finishes, continue with section III (Enabling).

Before adding, the host performs a `git ls-remote` reachability check, 5-second timeout by default; it reports an unreachable network explicitly.
If that check is what stalls on a China network, use the tarball URL from 2.2, or set an HTTPS prefix under
**Settings → Plugins → Plugin configuration → GitHub accelerator**.

## 2.2 Path B · Desktop command line (`desktop-cli.js`)

The desktop `desktop` profile is locked to the Electron app, so a plain `dsh plugin --profile desktop …` is refused;
`desktop-cli.js` is the only entry that gets through. It must run under Electron's Node mode, and the easiest way is a tiny helper:

```bat
@echo off
REM dsh plugin helper for the desktop (reserved) profile.
REM Usage: dsh-plugin.bat plugin --profile desktop <pnpm-args...>
set ELECTRON_RUN_AS_NODE=1
"<DSH install dir>\DSH Desktop.exe" "<DSH install dir>\resources\app\lib\desktop-cli.js" %*
```

`%*` forwards quoted specs verbatim. Install:

```bat
dsh-plugin.bat plugin --profile desktop add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix.2"
```

If GitHub will not fetch, use the tarball (**stable URL, no version in it**, so later version bumps change neither this command nor these docs):

```bat
dsh-plugin.bat plugin --profile desktop add "https://github.com/Potato1008ypy/dsh-purge-0.2.1rc2-fix/releases/latest/download/dsh-purge-dsh0.2.1rc2-fix.tar.gz"
```

This path writes both `dependencies` and `dsh.profile.bundles`; no hand-editing `package.json`.

> The helper is not required to install, but verification, migration and uninstalling below all use it.
> Without it you must assemble the command by hand every time — see appendix A.2.

## 2.3 Path C · Plain DSH (no desktop lock)

On plain DSH the ordinary CLI works directly. The profile is usually `web`; substitute whatever 1.2 showed:

```bash
dsh plugin --profile web add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix.2"
```

Other differences are in appendix B.

## 2.4 Replacing an older build: uninstall first

Skip this section for a fresh install. When replacing, the uninstall steps in section VI **must be done first**, otherwise a duplicated `- insert:` block may survive.

---

# III · Enabling and taking effect

Installing only puts the files in place. This plugin needs two more steps before it does anything.

## 3.1 Enable on the Plugins page

Open the **Plugins page**, find `dsh-purge` and click **Enable**.
**Do not** click Enable in dsh-market: it only attempts a hot mount, which always fails for this plugin, and it does not register `bundles`.

## 3.2 Fully quit and restart DSH

`lib/**` and `cordis.patch.yml` are read from disk **only at startup**. Closing the window is not a restart; the process must fully exit and start again.

## 3.3 Patch the host: Clean → Apply

After the restart, click **dsh-purge → Clean → Apply** next to the session title.
On success DSH restarts itself once more. **This plugin never does it automatically** (`autoApplyOnStart: false`, see `lib/index.js:928`), so confirm it by hand after every reinstall or host upgrade.

---

# IV · Verification

## 4.1 The two `package.json` fields

Plain PowerShell reading JSON — no node or Electron needed:

```powershell
$p = Get-Content "$env:USERPROFILE\.dsh\profiles\desktop\package.json" -Raw | ConvertFrom-Json
'dep   : ' + $(if ($p.dependencies.'dsh-purge') { $p.dependencies.'dsh-purge' } else { 'MISSING <- problem' })
'bundle: ' + $(if (($p.dsh.profile.bundles) -contains 'dsh-purge') { 'has dsh-purge' } else { 'MISSING <- problem' })
```

Neither line may say `MISSING`. A missing `bundle` row is the number-one cause of "installed but nothing happened" — add `dsh-purge` to the `dsh.profile.bundles` array by hand.

## 4.2 Offline regression test

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-purge"
node test/fixes.test.mjs
```

Expected last line `全部通过：22 passed, 0 failed`, exit code `0`. Covers FIX-07 through FIX-09; needs neither the network nor the host's `yaml`.

## 4.3 The config block appears exactly once

```powershell
$env:ELECTRON_RUN_AS_NODE=1
& $DSH_BIN $DCLI --profile desktop --dump-config > "$env:TEMP\dump.txt" 2>&1
Select-String -Path "$env:TEMP\dump.txt" -Pattern '^- id: dsh-purge'
```

Exactly 4 rows: `dsh-purge` / `-redteam` / `-redteam-store` / `-redteam-ui`.
The panel should also show every item once; twice means a duplicated block — re-run the check mode from section V.

## 4.4 The host log is clean

Log: `%APPDATA%\DSH Desktop\logs\host\dsh-<today>.log`

⚠️ The log is **append-only**, so old warnings stay in the same file. Look only at the segment after this boot:
note the line count before restarting, then inspect only the new lines.

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

All four should read `clean`. Positive evidence of a successful boot is more convincing than grepping for absence:

```
[dsh-purge-redteam] redteam-mode: 就绪（数据目录默认 $DSH_HOME/redteam；预设 …；技能目录 …）
[dsh-purge-redteam] redteam-mode: declared for mode dropdown: 红队模式
```

## 4.5 Patch registry in the panel

Open the **dsh-purge settings panel**; the line should read:

```
补丁 / patches: 59/59 applied, 0 pending
```

The same place shows the shim directory, the backup, and `inject: prompt-inject.md` as `default`.
After a restart every patch layer should re-apply automatically with nothing pending; a pending entry means 3.3 has not been done.
That line is **panel output**, not `--dump-config` content — do not wait for it from the command in 4.3.

## 4.6 The working directory is right

The tail of the system prompt should read `Your working directory is <real path>.` — not `{{cwd}}`, not empty.

---

# V · Migrating from an older version: repair old presets

Upgrading from an older build may leave a stale preset copy carrying `toolFilter`. **A fresh install can skip this section.**

Run check mode first (reports, changes nothing):

```powershell
node "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-purge\dsh-purge-repair.mjs"
```

Add `--fix` once a problem is confirmed:

```powershell
node "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-purge\dsh-purge-repair.mjs" --fix
```

Typical output:

```
# check mode, with a dirty preset present
✗ C:\Users\<you>\.dsh\.agent-presets\redteam\agent.cordis.yml
  第 314 行: toolFilter: —— 写进 Config 会让整行 throw
发现 1 处问题，未修改（加 --fix 执行修复）。

# after --fix
  ✓ 已剥离（备份 agent.cordis.yml.dsh-purge-repair.bak）
已修复 1 个文件。**重启 DSH 生效**
```

Two things to note:

- **Use `node`** (confirm with `where node`), not `& $DSH_BIN`, or PowerShell throws the output away (appendix A.2).
- The repair tool needs a yaml parser. It first tries `DSH install dir\resources\app\node_modules\yaml\dist\index.js`;
  if DSH lives at a non-default path and you run it with a standalone node, it fails with
  `✗ 找不到 yaml 解析器`. In that case use the desktop app's own node:

  ```powershell
  $env:ELECTRON_RUN_AS_NODE=1
  & $DSH_BIN "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-purge\dsh-purge-repair.mjs" --fix > "$env:TEMP\repair.txt" 2>&1
  Get-Content "$env:TEMP\repair.txt"
  ```

---

# VI · Uninstalling

## 6.1 Preferred: the dsh-market "Installed" page

**Installed** page → find `dsh-purge` → **Uninstall**. It ultimately runs the same `plugin remove` (`routes.js:1444`) and adds three things that work in your favour:

| What the market adds | Why it helps |
|---|---|
| Removes it from `dsh.profile.bundles` | If pnpm exits non-zero and the plugin command never reconciles, it falls back to disk truth and drops the dangling row |
| Inspects the user `cordis.patch.yml` first | Keeps the next boot from dying on a dangling reference |
| Cleans up the patch rows it wrote | Only rows carrying `disabled:` |

There are two **409 guards** (neither is an error):

1. The user `cordis.patch.yml` is not a readable patch list → you can force through
2. The user `cordis.patch.yml` still `insert`s `dsh-purge` → **not forceable**; the market states plainly that it will not rewrite a user patch, so remove those rows by hand first

## 6.2 Alternative: the CLI

```bat
dsh-plugin.bat plugin --profile desktop remove dsh-purge
```

If it was never installed this exits with an error, which means you were clean rather than that the step failed:

```
[ERR_PNPM_CANNOT_REMOVE_MISSING_DEPS] Cannot remove 'dsh-purge': no such dependency found
```

## 6.3 Always check: a local-directory install leaves its folder behind

If the old dependency was a local-directory install like `file:../../plugins/dsh-purge`, `remove` does **not** delete that folder:

```powershell
Get-ChildItem "$env:USERPROFILE\.dsh\plugins" -ErrorAction SilentlyContinue
```

If `dsh-purge` is there, deal with it yourself (`Remove-Item -Recurse`, or rename it as a backup).

---

# VII · Troubleshooting

## 7.1 DSH will not open

Edit the profile's `package.json` and move `dsh-purge` out of `bundles` into `desktopDeselectedBundles`; DSH will start again:

```json
"profile": { "bundles": [ /* dsh-purge removed */ ] },
"desktopDeselectedBundles": ["dsh-purge"]
```

Then dig in. Having gone this route you can skip the `bundle` check in 4.1 — moving it out by hand already did the half the market command could not do.

## 7.2 Installed but nothing happens

Check in this order:

1. Does `dsh.profile.bundles` contain `dsh-purge` (4.1)? If not, it was never registered — enable it on the Plugins page (3.1)
2. Was DSH fully restarted (3.2), rather than just the window closed?
3. Has Clean → Apply been run (3.3)?
4. Does the panel report `59/59 applied, 0 pending` (4.5)?

## 7.3 Roll the whole thing back

Restore the 1.3 backup:

```powershell
cd "$env:USERPROFILE\.dsh\profiles\desktop"
Copy-Item (Get-ChildItem "package.json.bak-*" | Sort-Object LastWriteTime | Select -Last 1) package.json -Force
```

## 7.4 Last resort: copy the directory in by hand

```
dsh-purge-dsh0.2.1rc2-fix.tar.gz   ← extract, then drop the whole directory into
<DSH_HOME>\profiles\desktop\node_modules\dsh-purge\
```

## 7.5 Closing notes

- **No data is lost**: the profile directory, sessions and the `redteam` SQLite all live under `$DSH_HOME`, independent of the plugin version.
- **Hand-edited presets and prompts are not overwritten**: the host will not touch a user copy when the template changes, which is why old-format copies need the repair tool in section V.
- **Re-run the check mode from section V after upgrading DSH**: upstream `master` is still `1.1.71` and still carries these faults.
- **Do not delete `cordis.patch.yml.dshpurge.bak`**: the host's `loadOverlayPatches()` falls back to that `.dshpurge.bak` when it cannot read the main file.

---

# Appendices

## A · Three desktop constraints

These are host behaviours, not defects in this plugin. The main path above is enough for a normal install; they explain the symptoms when something goes wrong.

### A.1 · The desktop `desktop` profile is locked to the Electron app

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

Only the Electron carrier passing `manageDesktopProfile: true` gets through, and the only thing that does so is the desktop app's own
`<DSH install dir>\resources\app\lib\desktop-cli.js`. The GUI Plugins page takes the same gate.

The hot mount fails because the host's admission test accepts nothing but plain `- insert:` rows carrying `id` and `name`
(`parseSimplePatch()` in `dshmarket/lib/hot.js:146`), while this plugin's patch carries
`inject: [systemPrompt, tools]`, several `config:` blocks and one `!!js` expression.
`inject` is cordis's service-dependency declaration and removing it kills the injection, so the limitation cannot be worked around on the plugin side.

### A.2 · `DSH Desktop.exe` returns no stdout

`DSH Desktop.exe` is a **GUI-subsystem** binary, so PowerShell's `&` neither waits for it nor captures stdout and `$LASTEXITCODE` comes back empty;
`cmd /c` does not wait either, and `start /wait` gets no stdout. Therefore:

- To inspect state → read the JSON with plain PowerShell (4.1), no node or Electron needed
- To run a script → use `node`, or the `.bat` helper from 2.2; redirect to a file and read it back when necessary

### A.3 · Keep labels ASCII inside `.ps1` files

Snippets pasted straight into a PowerShell window are fine, but **when saved as `.ps1`, PowerShell 5.1 reads UTF-8-without-BOM as ANSI**
and dies with errors like "字符串缺少终止符" (missing string terminator). Use ASCII output labels in the snippets (`clean` / `MISSING <- problem`).

## B · Differences on plain DSH (not Desktop)

Plain DSH and DSH Desktop are the same package, `@deepseek-ai/dsh@0.2.1-rc.2`, and the `bundles` composition logic lives in it too. Three differences:

**① No desktop lock, so the ordinary CLI works** (appendix A.1 does not apply):

```bash
dsh plugin --profile web add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix.2"
```

**② The adapter switches to web automatically.** The plugin picks an adapter per surface:

```js
const ADAPTERS = { web, desktop };
export function hostAdapter(kind = detectSurface()) {
  return ADAPTERS[adapterFor(kind)] || web;   // anything non-desktop falls back to web
}
```

Measured: plain CLI → `web`; DSH Desktop → `desktop`. So FIX-05 (recognising `DSH Desktop.exe`) is inert but harmless on plain DSH; the other eight apply as usual.

**③ Restarting works differently.** Desktop has asar swapping and a "module already loaded" guard; plain DSH uses `web.js` process restart
(`restartArgv` + `spawnRestartHelper`). So on plain DSH, 3.2 matters even more — do not expect the panel action to be enough.
The log path differs too; find it where plain DSH actually writes it.

## C · Three behaviours that look like failures but are not

**① Desktop never enters a patch → restart → re-patch loop.** It is disabled in source on purpose:

```js
// lib/settle-policy.js
/** 桌面启动自愈不得 requestRestart / taskkill，否则 Cordis 会 INACTIVE_EFFECT。 */
export function settleMayRestart({ surface, sealed = false } = {}) {
  if (surface === "desktop") return false;
```

**② Installing refreshes the patch revision stamp.** `$DSH_HOME\dsh-purge\installed-rev` is rewritten from its old value to `apply:1.1.71` (`lib/reapply.js:18`).
That stamp feeds the host's alignment check — **do not edit it by hand**.

**③ pnpm cleaning up stray packages during install is normal.** A measured install reported `Packages: +1 -10` (10 leftovers swept);
neither the top-level dependency nor `bundles` was affected.
