# FIXES.md — per-fix detail and how to verify

English version of [FIXES.md](FIXES.md). Written for people who want to **merge these fixes upstream** or **check them independently**. Every entry gives **symptom → root cause (host-side evidence) → fix → verification**.

All fixes are written **version-adaptively**: they probe for the host structure first and step aside when it is absent, so `0.2.0-rc.2` does not regress.

---

## 1. Bundle patch shape: duplicated `- insert:` block, plus a duplicate reference row upstream itself ships

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
const APP='D:/DSH Desktop/resources/app';
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

## 2. `toolFilter` / `persona` were removed from `tool-subagent`'s Config

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

## 3. The host no longer registers a `cwd` prompt variable

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

## 4. `#40 COMPLETE_PROMPT_KEEP_INJECT` anchor no longer matches

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

## 5. `desktop-shell` cannot locate the main-process file

**Symptoms**: the `desktop-shell` family reports `missing_file` in `patchStatus`; every patch that edits `lib/main.js` silently does nothing.

**Root cause**: `isOfficialHarnessExecutable()` only recognised executable names like `deepseek-harness`, while the desktop build's executable is **`DSH Desktop.exe`** — so `officialShellMain()` returned an empty string.

**Fix**: `lib/desktop.js` gains `OFFICIAL_DESKTOP_BASES = new Set(["dsh desktop.exe", "dsh-desktop.exe", "dsh desktop", "dsh-desktop"])` and the matcher is relaxed to `/^dsh[\s._-]*desktop(\.exe)?$/`.

**Verify**: `desktop-shell` should resolve to `…\resources\app\lib\main.js`, and its status should move from `missing_file` to `skipped`/`applied`.

---

## 6. When `assemble` throws, the entire prompt is dropped

**Symptoms**: as soon as the host's `system-prompt/assemble` throws (say, the unknown variable from item 3), the fallback returns `{ sections: [], contexts: [], tools: [] }` — **the whole system prompt disappears**, surfacing as "the persona fell off" / refusals.

**Root cause**: the inner `catch` of `installAssembleGuard` swallowed the error into an empty section table.

**Fix**: new `literalSectionFallback(context)` rebuilds the section table in host registration order from `prompt.layers.global` + `promptChainLayers(prompt, context?.scope)`, drops every section that **fails to interpolate** (decided by `textInterpolates(text, variables)`), marks the survivors `interpolate: false`, and returns `{ sections, contexts: [], tools: [] }`. Only if the rebuild itself fails does it fall back to the empty table.

**Verify**: make the host throw once (for example, temporarily add a section with an unregistered variable) and confirm the output still carries the `dsh-purge` and capabilities sections, with no `{ {var}}` residue.

---

## Appendix: the `retired` flag in the patch registry

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

## How to check this set of fixes yourself

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
