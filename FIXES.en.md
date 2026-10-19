# FIXES.md — per-fix detail and how to verify

English counterpart of [FIXES.md](FIXES.md). It records all nine adapter fixes as **symptom → root cause (host evidence) → change → how to re-check**, for anyone merging them upstream or re-verifying them in their own environment.

Every fix is **version-adaptive**: it probes for the host structure first and steps aside when it is absent, so `0.2.0-rc.2` sees no regression.

| ID | Subject |
|---|---|
| FIX-01 | Bundle patch shape: duplicated `- insert:` block, plus a duplicate reference row upstream ships |
| FIX-02 | `toolFilter` / `persona` were removed from `tool-subagent`'s Config |
| FIX-03 | The host no longer registers a `cwd` prompt variable |
| FIX-04 | `#40 COMPLETE_PROMPT_KEEP_INJECT` anchor no longer matches |
| FIX-05 | `desktop-shell` cannot locate the main-process file |
| FIX-06 | When `assemble` throws, the entire prompt is dropped |
| FIX-07 | `hostFs` whitelist missed `closeSync` — not a single backup was ever written |
| FIX-08 | `tool-workflow` / `tool-ralph` left enabled — subagents recurse past `maxDepth: 1` |
| FIX-09 | `repairOfficialCliAfterUnpack()` called async from a sync function — fatal on Node 24 |
| Appendix A | The `retired` flag in the patch registry |
| Appendix B | Deliberately unchanged: Ctrl+Enter behaviour |
| Appendix C | Verification summary |

---

## FIX-01 · Bundle patch shape: duplicated `- insert:` block, plus a duplicate reference row upstream itself ships

**Symptoms**: DSH will not start; or it starts but the settings page renders every plugin config row twice; the same plugin gets mounted twice.

**Upstream check result first** (this was previously listed as unverified; it is now confirmed):

```bash
curl -sL https://raw.githubusercontent.com/YuJunZhiXue/dsh-purge/master/cordis.patch.yml | grep -c '^- insert:'
# -> 1       upstream has exactly ONE insert block, 70 lines; the "block written twice" problem
#            is NOT in upstream source
```

Upstream's 70 lines do contain **two `- id: dsh-purge` occurrences**, but they are not the same thing:

1. upstream lines 33–34 — a reference row carrying only `inject` (it contributes a config override);
2. upstream line 37 — the plugin row **inside** the insert block (carrying the full `config`).

With both present, the same batch of settings is declared twice. This fork drops (1) so configuration changes go through the panel into the **profile's own patch**.

**The extra break in the locally installed copy**: in the copy produced by installation, the `- insert:` block was **written twice in full** (see the quote in [FORK-NOTES.md](FORK-NOTES.md)), so all four plugin rows were inserted twice — this came from the install/write step and **does not match upstream's source shape**.

The host re-reads that file on every boot:

- `@deepseek-ai/dsh-app-boot/lib/index.js` → `loadProfileDirectory()` calls `bundlePatchPaths()` → `loadOverlayPatches()` per bundle;
- `loadOverlayPatches()` does `readFileSync` + `parsePatchList` **on every boot**, then hands it to `applyEntryPatches(data, patches, warn)`;
- `entryMap` is keyed by `{id, insert, name, ...}`, so one `id` appearing twice inserts two entries;
- two `dsh-purge-redteam-store` instances then fight over a single SQLite file.

**Fix**: delete the duplicated block, keeping a single `- insert:` block; drop upstream's duplicate reference row too. Final shape: **1 `- insert:` block / 4 plugin rows / 1 `system-prompt` config override**, 52 lines.

**Verify**:

```bash
# (1) shape: insert blocks should be 1, plugin rows should be 4
grep -c '^- insert:' cordis.patch.yml
grep '^    - id:' cordis.patch.yml

# (2) parse it with the host's own engine and confirm nothing is inserted twice
node -e "
const {pathToFileURL}=require('node:url'), path=require('node:path');
const APP=process.env.DSH_APP || process.argv[2];   // ← pass your <DSH install dir>/resources/app
import(pathToFileURL(path.join(APP,'node_modules/@deepseek-ai/dsh-app-boot/lib/index.js')).href).then((boot)=>{
  const dir=boot.resolveProfileDir('desktop', process.env.DSH_HOME||require('node:os').homedir()+'/.dsh');
  const p=boot.loadProfileDirectory('check', dir, path.join(APP,'package.json'));
  for(const l of p.layers) for(const patch of l.patches)
    if(Array.isArray(patch?.insert)) for(const r of patch.insert) console.log(r.id);
});"
```

Everything should appear exactly once.

**Already confirmed (2026-10-18)**: upstream `master`'s `cordis.patch.yml` has **no** duplicated insert block. So "the block was written twice" is a **local installation artifact, not an upstream bug**, which means:

1. when opening an upstream PR, this item should be rewritten as *"drop the duplicate `- id: dsh-purge` reference row"*, **not** *"fix a duplicated block"*;
2. `dsh-purge-repair.mjs`'s duplicate-block check still earns its place — it identifies **which write step** duplicated the block.

---

## FIX-02 · `toolFilter` / `persona` were removed from `tool-subagent`'s Config

**Symptoms**:

```
[E] [tool-subagent] Error: tool-subagent: toolFilter is no longer supported; configure persona
    and tool plugins in an Agent Preset and select it with agentPreset (spawn only)
    at Object.apply (…/@deepseek-ai/dsh-tool-subagent/lib/index.js:355:89)
[W] [agent-preset-registry] agent preset redteam: tool-subagent (…): tool-subagent: toolFilter …
[W] [dsh-purge-redteam] redteam-mode: declared but broken: tool-subagent (…)
```

Consequence: the red-team preset cannot mount → the preset is broken → delegation is dead.

**Root cause**: in `0.2.1-rc.2`, `@deepseek-ai/dsh-tool-subagent` deleted `persona` / `toolFilter` from its `Config`; merely seeing either key **throws**. The tool parameters no longer include `tool_filter` either (only `cwd` / `description` / `prompt` / `agent_preset` / `provider` / `model` / `reasoning_effort`).

`@deepseek-ai/dsh-subagent`'s `composition.toolFilter` can now be supplied **only by a runtime descriptor** (`lib/index.js:395`); plugin config cannot reach it at all — so on 0.2.1 the key has no alternative spelling and has to go. Leaf constraint falls back to `maxDepth: 1`: `resolveChildDepth()` rejects with `subagent depth N exceeds maxDepth M`.

**Fix** (two places):

- `presets/redteam/agent.cordis.yml`: drop `toolFilter: deny: [...]` from the `- id: tool-subagent` row, keep `maxDepth: 1`;
- `lib/redteam/index.js` → `repairDelegation()`: new `stripRetiredSubagentKeys(text)` that removes `toolFilter:` / `persona:` blocks **line-wise** and replaces the key line with an explanatory comment. Critical detail: comments inside the block are indented deeper than the key, so the removal must keep consuming lines only while `nextIndent >= indent.length` — otherwise it swallows a same-level trailing comment and yields broken YAML (`BAD_INDENT`).

**Verify**:

```bash
cd <DSH_HOME>/profiles/desktop/node_modules/dsh-purge
# the preset no longer carries an executable toolFilter
grep -n '^\s*toolFilter:' presets/redteam/agent.cordis.yml     # expect no output
# old-format presets are repaired automatically (put a toolFilter-bearing copy in a temp DSH_HOME)
DSH_HOME=<tmp> ELECTRON_RUN_AS_NODE=1 "<DSH>/DSH Desktop.exe" \
  -e "import('./lib/redteam/index.js').then((m)=>{console.log(JSON.stringify(m.installPreset({log:console.log})))})"
# expect: {"action":"repaired","repaired":"delegation+anchor-script"}
```

---

## FIX-03 · The host no longer registers a `cwd` prompt variable

**Symptoms**: `unknown prompt variable "{{cwd}}" in section "X"; registered variables: model, provider` → `renderPrompt` throws → **the whole batch of sections is dropped** (surfacing as "the persona fell off mid-task" or refusals). Or, after clearing `{{cwd}}` some other way, escaped residue like `Working directory: { {cwd}}.` is left in the prompt.

**Root cause**: in `0.2.1`, `@deepseek-ai/dsh-system-prompt` interpolates strictly — `interpolate()` **throws** on an unregistered variable — and `cwd` is **no longer registered by anyone** (only `provider` / `model` remain). The `assemble` context is `{ agent, scope: agent, signal }`, so the working directory has to be read from `context.agent.session.header.cwd`. Separately, `@deepseek-ai/dsh-working-directory` registers a runtime context `working-directory:current` with `required: true` and `interpolate: false`.

**Fix** (belt and braces; prefer the first):

1. `lib/identity.js` → `cwdSentence(context)`: **when an assembly context is available, emit a literal** — `Your working directory is <path>.` — no placeholder involved. This survives whatever the host does to its variable machinery next.
2. `ensureCwdPromptVariable(prompt)`: when the host registers no `cwd`, the plugin registers it itself via `prompt.variable("cwd", provider)` (the provider reads `agent.session.header.cwd`, returns an empty string when unavailable, and never throws), and `escapeDshInterpolation()`'s allow-list is widened from `["model","provider"]` to include `cwd`.

**Note**: every `"Working directory: {{cwd}}. "` replacement text inside `stripHarnessPersona()` became `""`, to avoid rendering that sentence twice alongside the working-directory runtime context.

**Verify**:

```bash
# assemble once; the tail must be a real path with no { {cwd}} residue
ELECTRON_RUN_AS_NODE=1 "<DSH>/DSH Desktop.exe" -e "
import('./lib/identity.js').then((m)=>{
  const asm={sections:[
    {name:'deployment:persona-prefix',text:'… Your working directory is {{cwd}}. ',order:10100},
    {name:'deployment:persona-suffix',text:'',order:10200}],contexts:[],tools:[],variables:{model:'m'}};
  const out=m.rewritePromptAssembly(asm,'',{context:{agent:{session:{header:{cwd:'D:\\\\demo'}}}}});
  for(const s of out.sections) console.log(s.name, JSON.stringify(s.text));
});"
# expect suffix = "Your working directory is D:\\demo."
```

---

## FIX-04 · `#40 COMPLETE_PROMPT_KEEP_INJECT` anchor no longer matches

**Symptoms**: in `patchStatus`, `#40` reads `skipped` (in non-strict mode it found no match in the existing file) → in complete mode the purge inject is swallowed.

**Root cause**: the host's `@deepseek-ai/dsh-system-prompt/lib/index.js` changed `assemble()`:

```js
const transformed = await this.ctx.waterfall(scopeTarget(this, scope), "system-prompt/assemble", assembly, context, () => Promise.resolve(assembly));
if (completeSection === void 0 && !runtimeContextSuppressed) return transformed;
const requiredContexts = new Set([...contextByName.values()].filter((entry) => entry.required === true).map((entry) => entry.name));
return { ...transformed,
  sections: completeSection === void 0 ? transformed.sections : [completeSection],
  contexts: runtimeContextSuppressed ? transformed.contexts.filter((entry) => requiredContexts.has(entry.name)) : transformed.contexts };
```

The literal the old patch looked for — `contexts: runtimeContextSuppressed ? [] : transformed.contexts` — **no longer exists**; 0.2.1 keeps only `required: true` contexts.

**Fix**: the replacement body moved into `completePromptInjectBody(contextsLine)` (its default argument is still the old spelling), and `#40` gained a `0.2.1`-shaped pattern that matches the block above (including `const requiredContexts = …` and the filtered `contexts` line), replaces it with an IIFE call to `completePromptInjectBody("<the host's contexts line>")`, and splices the `const requiredContexts = …` line back in after the first newline.

**Verify**:

```bash
ELECTRON_RUN_AS_NODE=1 "<DSH>/DSH Desktop.exe" lib/audit-apply.mjs 40
# expect: changed (+NNN bytes) + "✓ result parses as ESM", failures: 0
```

---

## FIX-05 · `desktop-shell` cannot locate the main-process file

**Symptoms**: the `desktop-shell` family reports `missing_file` in `patchStatus`; every patch that edits `lib/main.js` silently does nothing.

**Root cause**: `isOfficialHarnessExecutable()` only recognised executable names like `deepseek-harness`, while the desktop build's executable is **`DSH Desktop.exe`** — so `officialShellMain()` returned an empty string.

**Fix**: `lib/desktop.js` gains `OFFICIAL_DESKTOP_BASES = new Set(["dsh desktop.exe", "dsh-desktop.exe", "dsh desktop", "dsh-desktop"])` and the matcher is relaxed to `/^dsh[\s._-]*desktop(\.exe)?$/`.

**Verify**: `desktop-shell` should resolve to `…\resources\app\lib\main.js`, and its status should move from `missing_file` to `skipped`/`applied`.

---

## FIX-06 · When `assemble` throws, the entire prompt is dropped

**Symptoms**: as soon as the host's `system-prompt/assemble` throws (say, the unknown variable from item 3), the fallback returns `{ sections: [], contexts: [], tools: [] }` — **the whole system prompt disappears**, surfacing as "the persona fell off" / refusals.

**Root cause**: the inner `catch` of `installAssembleGuard` swallowed the error into an empty section table.

**Fix**: new `literalSectionFallback(context)` rebuilds the section table in host registration order from `prompt.layers.global` + `promptChainLayers(prompt, context?.scope)`, drops every section that **fails to interpolate** (decided by `textInterpolates(text, variables)`), marks the survivors `interpolate: false`, and returns `{ sections, contexts: [], tools: [] }`. Only if the rebuild itself fails does it fall back to the empty table.

**Verify**: make the host throw once (for example, temporarily add a section with an unregistered variable) and confirm the output still carries the `dsh-purge` and capabilities sections, with no `{ {var}}` residue.

---

> Items 7–9 came in as **cross-pollination**: a line-by-line comparison against
> [`evilevil/dsh-purge-021rc2`](https://github.com/evilevil/dsh-purge-021rc2).
> That branch sits on upstream 1.1.72 and fixed three more defects that still exist on our 1.1.71 base.
> Each item below states its provenance and where we diverge.

## FIX-07 · `hostFs` whitelist missed `closeSync` → not a single backup was ever written; restore/uninstall dead

**Symptoms**: after Apply there is **not one `.dshpurge.bak`** anywhere under the host tree, so "restore" has nothing to restore and uninstall cannot roll back. The UI may not even complain — the error is swallowed by `try{}catch{}`.

**Root cause**: `HOST_SYNC` in `lib/extract-asar.js` never listed `closeSync`, and `hostFs` is generated from that very table:

```js
for (const method of HOST_SYNC) hostFs[method] = route(method, false);
```

Not in the table → **`hostFs.closeSync` does not exist at all**. Yet `backupAll()` needs it to release the placeholder handle:

```js
placeholderFd = fs.openSync(bak, "wx");                          // placeholder, race-free
try { fs.closeSync(placeholderFd); } catch { /* ignore */ }       // <- TypeError, swallowed
await atomicCopyFile(fp, bak);                                   // <- handle still open
```

With the handle leaked, the rename fails with **EPERM** on Windows, `atomicCopyFile` fails, and the backup gets `unlinkSync`-ed away — nothing survives. `fsyncSync` / `readSync` belong to the same atomic read/write path and were missing too.

**Fix**: a separate `HOST_FD` table — fd-based methods take a **file descriptor, not a path**, so they must not go through `route()` (which would probe asar with `String(fd)` and pollute the probe cache):

```js
const HOST_FD = [
  "closeSync", "fsyncSync", "fdatasyncSync", "readSync", "writeSync",
  "futimesSync", "ftruncateSync",
];
for (const method of HOST_FD) hostFs[method] = (...args) => nodeFs[method](...args);
```

An fd is a process-level OS handle and `node:fs` / `original-fs` share one descriptor table, so close/read/fsync work no matter which side `openSync` routed to. The path-based `truncateSync` / `utimesSync` were added to `HOST_SYNC` alongside.

> Provenance: #127 / #106 in `evilevil/dsh-purge-021rc2`. It keeps fd and path methods in one table routed through `route()`; we split them so no fd is ever probed as a path.

**Verify**: run `backupAll()` twice over the same targets:

```
before: made 0 | errors 4 | .bak 0    first error EPERM: operation not permitted, rename
after:  made 4 | errors 0 | .bak 4    second run made 0 (wx hits EEXIST, idempotent)
```

```js
import { hostFs } from "./lib/extract-asar.js";
console.log(typeof hostFs.closeSync, typeof hostFs.readSync);  // both "function"
```

## FIX-08 · `tool-workflow` / `tool-ralph` left enabled → subagents can recurse past `maxDepth: 1`

**Symptoms**: the redteam preset claims "subagents are leaves", yet a child can still delegate further.

**Root cause**: that boundary used to come from `toolFilter.deny: [subagent_fork, workflow, ralph]`, and `toolFilter` is gone in 0.2.1-rc.2. Replacing it with `maxDepth: 1` only closed **one** path:

- ✅ child calls `tool-subagent` → `resolveChildDepth` reports `subagent depth 2 exceeds maxDepth 1`
- ❌ child calls `workflow` / `ralph` → a different path entirely

Because `dsh-workflow-ptc`'s `childRequest()` builds the spawn request with only `prompt / provider / model / schema` and **no `maxDepth`** (that file mentions `maxDepth` zero times), so it lands on `@deepseek-ai/dsh-tool-subagent`'s schema `.default(10)`.

And children **inherit the parent preset's tool table** (`agentPreset` omitted = inherit the parent agent's current preset), so if the preset enables `tool-workflow`, the child really does hold that tool.

**Fix**: add `disabled: true` to both rows in `presets/redteam/agent.cordis.yml` (the `workflow-ptc` engine stays mounted; only the tools are removed). The five redteam execution roles run through `tool-subagent(spawn)` and do not need them.

> Provenance: `evilevil/dsh-purge-021rc2`. Our old comment claimed "② the child's tool table never had workflow / ralph engines (this preset doesn't install them)" — factually wrong, now corrected.

**Verify**:

```
tool-workflow : disabled
tool-ralph    : disabled
workflow-ptc  : ENABLED
```

## FIX-09 · `repairOfficialCliAfterUnpack()` called async from a sync function → fatal on Node 24

**Symptoms**: clicking Apply in the desktop app ends in `dsh: fatal load failure`; the host dies.

**Root cause**: the function is synchronous but calls async `atomicCopyFile()` without `await`:

```js
try { atomicCopyFile(fp, bak); } catch { /* backup failure is not fatal */ }   // sync catch cannot see it
```

`atomicCopyFile` returns a Promise; a synchronous `try/catch` never observes the rejection, which surfaces through Node 24's `unhandledRejection` and is escalated to `uncaughtException`.

**Fix**: use `atomicWriteSync()` — same "temp file + rename" atomic write, fully synchronous — and drop `atomicCopyFile` from the `desktop.js` import:

```js
try { atomicWriteSync(bak, fs.readFileSync(fp)); } catch { /* backup failure is not fatal */ }
```

> Provenance: #119 in `evilevil/dsh-purge-021rc2`. It made the function `async`, added `await`, and updated the call sites in `core.js` / `index.js`. We changed the **call site** instead — swapping async for a synchronous equivalent keeps the signature and the whole call chain untouched, a strictly smaller blast radius, with byte-identical output.

**Verify**: call both forms against a path that must fail:

```
old: unhandledRejection fires -> Error: ENOENT ... (escalates to uncaughtException under Node 24/Electron)
new: throws synchronously, caught by try/catch: ENOENT
happy path: backup is byte-identical to the source = true
```

---

## Appendix A · The `retired` flag in the patch registry

`patchAppliesHere()` gained `if (patch?.retired) return false;`. Rows flagged `retired` report `na` instead of `skipped`. Retired rows (each carries a rationale comment):

| id | why it is retired |
|---|---|
| `#32` `#53` | web-face copy; the desktop profile never reaches it |
| `#45` `#46` `#82` `#83` `#84` | one and the same "desktop shell patch chain". In 0.2.1, `resources/app/lib/main.js` is already a bundled artifact, and none of the anchors (`exitPromise`, `dsh desktop host exited with`, that `@deepseek-ai/dsh-api-gateway/stream-protocol` import) exist any more; host lifecycle moved into `@deepseek-ai/dsh`, and the shutdown path became `ProfileMaterializationError` + `result` |
| `#80` | the minimal preset is not present in the desktop profile |
| `#77` | the host ships its own `isRewindMarker` / `rewindVisibleEntries`; `append()` was refactored and the old anchor no longer matches |

**This is not "switching features off" — it separates two states.** Previously those rows reported `skipped`, mixed in with patches that genuinely failed to apply, so it was impossible to tell which ones needed work. Afterwards:

```
applied 66 / na 15 / pending 1     (#40 only lands in complete mode)
```

---

## Appendix B · Deliberately unchanged: Ctrl+Enter behaviour

**Conclusion: kept as is, on purpose.**

### Current behaviour

The session-controller branch on `request.mode` is rewritten by this repository's cleanup patches:

| Patch | Location | Effect |
|---|---|---|
| `#85 SESSION_PROMPT_ALWAYS_FOLLOWUP` | `lib/core.js` | Replaces `if (mode === "steer") agent.steer(...) else agent.followup(...)` entirely with `agent.followup(message)` |
| `#86` | `lib/core.js` | The first `replace` likewise forces `agent.followup(message)`; the third `replace` keeps `steer()`'s next-step semantics |

Measured in the live host log, `[dsh-purge-85]` hits once and `[dsh-purge-86]` twice, so both patches are applied.

### Effect

A UI send always opens a new turn; Ctrl+Enter does **not** interrupt the current turn, it queues the next one.

### Why it stays

This rewrite is not a defect fix but a **behavioural race patch**: it suppresses the "immediate second message is rejected" race (`#85`'s `desc` records it as "消 steer→next-step 竞态（二轮立刻发被拒根因）"). Later upstream versions reverted to `agent.steer`; matching that revert here would reintroduce the race.

### How to revert

Two edits, both in `lib/core.js`:

1. The `replace` of `#85`: restore the `mode === "steer"` branch.
2. The first `replace` of `#86`: likewise, stop forcing `followup`.

After reverting, re-run `lib/audit-apply.mjs` to confirm the hit state, and re-test the back-to-back second-message scenario.

---
## Appendix C · Verification summary

Start with the bundled regression test (it locks in items 7–9; no network, no host `yaml` needed):

```bash
cd <DSH_HOME>/profiles/desktop/node_modules/dsh-purge
node test/fixes.test.mjs          # same as npm test
```

Expected last line: `全部通过：22 passed, 0 failed`, exit code 0.

Everything else:

```bash
cd <DSH_HOME>/profiles/desktop/node_modules/dsh-purge

# does the patch match, and is the result still valid ESM? (reads memory, writes nothing)
ELECTRON_RUN_AS_NODE=1 "<DSH>/DSH Desktop.exe" lib/audit-apply.mjs 40,83

# does the preset row's config satisfy the host Config schema?
ELECTRON_RUN_AS_NODE=1 "<DSH>/DSH Desktop.exe" lib/audit-preset-config.mjs

# do any patches miss their target during composition? (attributed per owner)
ELECTRON_RUN_AS_NODE=1 "<DSH>/DSH Desktop.exe" lib/audit-compose.mjs
```

> These three scripts are **not shipped in the release package** (the `files` field excludes them).
> To check things on your own machine, copy them over from a development checkout, or re-derive them from their logic.

### Checking FIX-07 … FIX-09 (no extra scripts needed)

```js
// (1) item 7: are the fd methods actually installed?
import { hostFs } from "./lib/extract-asar.js";
for (const m of ["closeSync", "fsyncSync", "readSync", "writeSync"])
  console.log(m, typeof hostFs[m]);            // all should be "function"
```

```js
// (2) item 8: are the two tools removed from the preset?
import fs from "node:fs";
import YAML from "yaml";
const doc = YAML.parse(fs.readFileSync("presets/redteam/agent.cordis.yml", "utf8"));
const ids = [];
(function walk(n) {
  if (!Array.isArray(n)) return;
  for (const x of n) {
    if (x && typeof x === "object") {
      if (x.id) ids.push([x.id, x.disabled === true]);
      if (Array.isArray(x.config)) walk(x.config);
    }
  }
})(doc);
for (const want of ["tool-workflow", "tool-ralph", "workflow-ptc", "tool-subagent"])
  console.log(want, ids.filter(([i]) => i === want).map(([, d]) => (d ? "disabled" : "ENABLED")));
// expect: tool-workflow / tool-ralph = disabled, workflow-ptc / tool-subagent = ENABLED
```

```js
// (3) item 9: after backupAll, are there really .bak files on disk?
import { backupAll } from "./lib/core.js";
const r = await backupAll("<DSH>/resources/app/node_modules/@deepseek-ai");
console.log("made:", r.made.length, "errors:", r.errors.length);
// expect made > 0 and errors 0, with *.dshpurge.bak appearing next to the targets
```

```powershell
Get-ChildItem "<DSH>\resources\app" -Recurse -Filter *.dshpurge.bak | Measure-Object
```

> The other half of item 9 is simply **not crashing**: after Apply the host is still alive, with no
> `fatal load failure` and no `unhandledRejection` / `uncaughtException` in the logs.
