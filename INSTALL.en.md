# Install guide (DSH Desktop 0.2.1-rc.2)

English version of [INSTALL.md](INSTALL.md).

## What this package is

- Based on upstream [dsh-purge](https://github.com/YuJunZhiXue/dsh-purge) `1.1.71` (commit `6c1d638`, MIT)
- Plus 6 adapter fixes for **DSH Desktop 0.2.1-rc.2** — see [FORK-NOTES.md](FORK-NOTES.md) and [FIXES.en.md](FIXES.en.md)
- **Do not** run plain `pnpm add dsh-purge` — that installs the unfixed upstream build

## Step 0 · Check your version

The fixes target **0.2.1-rc.2** (and are written version-adaptively), but do **not** install this on a DSH older than `0.2.0`.

## Step 1 · Install the package

```bash
cd <DSH_HOME>/profiles/desktop          # DSH_HOME defaults to ~/.dsh
```

Three ways, pick one:

```bash
# A. from the Release tag (recommended: the address is fixed and does not follow main)
pnpm add https://github.com/Potato1008ypy/dsh-purge-0.2.1rc2-fix/releases/latest/download/dsh-purge-dsh0.2.1rc2-fix.tar.gz

# A2. via a git spec (the host runs a GitHub reachability check first, 5 s default)
pnpm add "github:Potato1008ypy/dsh-purge-0.2.1rc2-fix#v1.1.71-dsh0.2.1rc2-fix"

# B. from the tarball attached to the Release
pnpm add file:/path/to/dsh-purge-1.1.71-dsh0.2.1rc2-fix.tar.gz
#    downloads: https://github.com/Potato1008ypy/dsh-purge-0.2.1rc2-fix/releases

# C. copy the directory (offline machine)
cp -r dsh-purge <DSH_HOME>/profiles/desktop/node_modules/
```

> With several profiles (not just `desktop`), **each profile you use needs its own copy**.

## Step 2 · Register it as a bundle (the step people miss)

Edit `<DSH_HOME>/profiles/desktop/package.json`:

```json
{
  "dsh": {
    "profile": {
      "bundles": [ "@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app", "dshmarket", "dsh-purge" ]
    },
    "desktopDeselectedBundles": []
  }
}
```

**Both conditions must hold**:

1. `dsh-purge` is in `dsh.profile.bundles` (**sitting in `dependencies` alone is not enough**)
2. `dsh-purge` is **not** in `desktopDeselectedBundles`

Most "I installed it but nothing happened" cases die on these two fields.

> **The easier route**: DSH's **Plugins panel → Add plugin** accepts a git address, a tarball, or a local absolute path, and writes `dsh-purge` into `bundles` for you (the host's `installBundle()` calls `selectBundle(name, true)` as soon as the install finishes). Then you never touch these two fields by hand.

## Step 3 · Sync presets, then restart

```bash
# Presets come in two copies — a plugin template and your own user copy.
# Editing the template does not overwrite an existing user copy, so hand
# old-format presets to the self-repair tool:
ELECTRON_RUN_AS_NODE=1 "<DSH install dir>/DSH Desktop.exe" \
  <DSH_HOME>/profiles/desktop/node_modules/dsh-purge/dsh-purge-repair.mjs --fix
```

Then **fully quit and restart DSH** (`lib/**` and `cordis.patch.yml` are read from disk only at startup).

---

## How to verify

### 1. The plugin actually mounted

Host log: `%APPDATA%\DSH Desktop\logs\host\dsh-<date>.log`

You should be able to find these, **each appearing exactly once**:

```
[dsh-purge-redteam] redteam-mode: 就绪（数据目录默认 $DSH_HOME/redteam；…）
[dsh-purge-redteam] redteam-mode: declared for mode dropdown: 红队模式
```

These should **no longer** appear:

```
[W] [root] patch: entry "dsh-purge" not found
[E] [tool-subagent] Error: tool-subagent: toolFilter is no longer supported
[W] [agent-preset-registry] agent preset redteam: … is broken
```

### 2. The settings page no longer double-renders

Open the dsh-purge panel: every config item should appear **once**. Still twice → run the self-repair tool.

### 3. The working directory is right

The tail of the system prompt should read `Your working directory is <path>.` — not `{ {cwd}}`, not empty.

---

## Rescuing a broken install

### A. DSH will not open (startup hangs or crashes)

**Get it open first** — edit `<DSH_HOME>/profiles/desktop/package.json` and move `dsh-purge` from `bundles`
**into** `desktopDeselectedBundles`:

```json
{
  "dsh": {
    "profile": { "bundles": [ /* dsh-purge removed */ ] },
    "desktopDeselectedBundles": ["dsh-purge"]
  }
}
```

**Then fix the root cause**:

```bash
ELECTRON_RUN_AS_NODE=1 "<DSH install dir>/DSH Desktop.exe" \
  <DSH_HOME>/profiles/desktop/node_modules/dsh-purge/dsh-purge-repair.mjs --fix
```

Finally move `dsh-purge` back from `desktopDeselectedBundles` into `bundles`, and restart.

### B. `cordis.patch.yml` is gone entirely

The host's `loadOverlayPatches()` has a fallback: when it cannot read the main file it reads
**`cordis.patch.yml.dshpurge.bak`** from the same directory. So do **not** delete that `.dshpurge.bak`.

### C. Just look, change nothing

```bash
ELECTRON_RUN_AS_NODE=1 "…/DSH Desktop.exe" <…>/dsh-purge-repair.mjs
```

Exit codes: `0` fine · `1` problems left unfixed · `2` environment error.

---

## Notes

- **After upgrading DSH, re-run the self-repair tool in check mode.** Upstream `master` is still `1.1.71` and still carries these faults.
- **Do not run `pnpm update dsh-purge`** — it reverts to the unfixed upstream build.
- The self-repair tool depends on a `yaml` parser. It first tries DSH's own
  `resources/app/node_modules/yaml/dist/index.js`, so **run it with DSH's node**:
  `ELECTRON_RUN_AS_NODE=1 "…/DSH Desktop.exe" dsh-purge-repair.mjs`.
