# FIXES.md — 逐条说明与验证方法

本文件逐条记录九处适配修复：**症状 → 根因（宿主侧证据）→ 改动 → 复核方法**。面向需要把这些修复合并回上游、或在自有环境复核的使用方。

所有修复均写成**版本自适应**：先探测宿主是否存在对应结构，不存在则不介入，因此对 `0.2.0-rc.2` 不产生回归。

| 编号 | 主题 |
|---|---|
| FIX-01 | bundle patch 形状：重复 `- insert:` 块，以及上游自带的重复引用行 |
| FIX-02 | `toolFilter` / `persona` 已从 `tool-subagent` 的 Config 中删除 |
| FIX-03 | 宿主不再注册 `cwd` 提示词变量 |
| FIX-04 | `#40 COMPLETE_PROMPT_KEEP_INJECT` 锚点失配 |
| FIX-05 | `desktop-shell` 定位不到主进程文件 |
| FIX-06 | `assemble` 抛错时整个提示词被丢空 |
| FIX-07 | `hostFs` 白名单漏 `closeSync` — 备份一份都写不出来，还原/卸载全废 |
| FIX-08 | `tool-workflow` / `tool-ralph` 没禁用 — 子代理能绕过 `maxDepth: 1` 递归 |
| FIX-09 | `repairOfficialCliAfterUnpack()` 同步函数里调 async，Node 24 升级成 fatal |
| 附录 A | 补丁注册表的 `retired` 标记 |
| 附录 B | 未变更项：Ctrl+Enter 行为 |
| 附录 C | 复核方法汇总 |

---

## FIX-01 · bundle patch 形状：重复 `- insert:` 块，以及上游自带的重复引用行

**症状**：DSH 启动不了；或能启动但设置页里插件配置渲染成两块；同一个插件被挂载两次。

**先说上游核查结果（此前标为未验证，现已核实）**：

```bash
curl -sL https://raw.githubusercontent.com/YuJunZhiXue/dsh-purge/master/cordis.patch.yml | grep -c '^- insert:'
# → 1       上游只有 1 个 insert 块，70 行；上游源码里没有「块被写两遍」这个问题
```

上游那 70 行里确实有**两处 `- id: dsh-purge`**，但它们不是同一种东西：
① 上游第 33–34 行是一条只写 `inject` 的引用行（给配置补覆盖项）；
② 上游第 37 行才是插入块里的插件行（带整份 `config`）。
两者并存时，同一批设置被声明两遍。本 fork 删掉了 ①，配置改动统一交给面板写进 profile 自己的 patch。

**本机那份的额外故障**：安装出来的副本里 `- insert:` 块**被整体写了两遍**（见 `FORK-NOTES.md` 引文），
四个插件行各插入两次 —— 这是安装/写盘环节引入的，**不是上游源码的形状**。宿主
`@deepseek-ai/dsh-app-boot/lib/index.js` 的 `loadProfileDirectory()` 对每个 bundle 调用
`bundlePatchPaths()` → `loadOverlayPatches()`，后者每次启动都 `readFileSync` + `parsePatchList`，
再交给 `applyEntryPatches(data, patches, warn)`；`entryMap` 按 `{id, insert, name, ...}` 建，
同一个 `id` 出现两次就会插入两条。两个 `dsh-purge-redteam-store` 实例还会抢同一个 SQLite 文件。

**改法**：删掉重复的那一份，只保留一个 `- insert:` 块；同时去掉上游那条重复的引用行。
最终形状：**1 个 `- insert:` 块 / 4 条插件行 / 1 条 `system-prompt` 配置覆盖**，共 52 行。

**验证**：

```bash
# ① 结构：insert 块应为 1，插件行应为 4
grep -c '^- insert:' cordis.patch.yml
grep '^    - id:' cordis.patch.yml

# ② 用宿主自己的引擎解析，确认没有重复插入
node -e "
const {pathToFileURL}=require('node:url'), path=require('node:path');
const APP=process.env.DSH_APP || process.argv[2];   // ← 传你的 <DSH 安装目录>/resources/app
import(pathToFileURL(path.join(APP,'node_modules/@deepseek-ai/dsh-app-boot/lib/index.js')).href).then((boot)=>{
  const dir=boot.resolveProfileDir('desktop', process.env.DSH_HOME||require('node:os').homedir()+'/.dsh');
  const p=boot.loadProfileDirectory('check', dir, path.join(APP,'package.json'));
  for(const l of p.layers) for(const patch of l.patches)
    if(Array.isArray(patch?.insert)) for(const r of patch.insert) console.log(r.id);
});"
```

每行只应出现一次。

> **已核实（2026-10-18）**：上游 `master` 的 `cordis.patch.yml` **没有**重复 insert 块，只有 1 个。
> 所以「块被写两遍」是**本机安装产物**，不是上游 bug —— 这意味着：
> ① 给上游提 PR 时，这一条应当**改写成「去掉那条重复的 `- id: dsh-purge` 引用行」**，而不是「修重复块」；
> ② `dsh-purge-repair.mjs` 的重复块检查仍然有用 —— 它能查出是哪一步写盘把块写了两次。

---

## FIX-02 · `toolFilter` / `persona` 已从 `tool-subagent` 的 Config 中删除

**症状**：

```
[E] [tool-subagent] Error: tool-subagent: toolFilter is no longer supported; configure persona
    and tool plugins in an Agent Preset and select it with agentPreset (spawn only)
    at Object.apply (…/@deepseek-ai/dsh-tool-subagent/lib/index.js:355:89)
[W] [agent-preset-registry] agent preset redteam: tool-subagent (…): tool-subagent: toolFilter …
[W] [dsh-purge-redteam] redteam-mode: declared but broken: tool-subagent (…)
```

后果：红队预设整行挂不上 → 预设 broken → 派活全废。

**根因**：`@deepseek-ai/dsh-tool-subagent` 在 `0.2.1-rc.2` 的 `Config` 里删掉了
`persona` / `toolFilter`，检测到就 throw。工具参数里也没有 `tool_filter` 了（只剩
`cwd` / `description` / `prompt` / `agent_preset` / `provider` / `model` / `reasoning_effort`）。

`@deepseek-ai/dsh-subagent` 的 `composition.toolFilter` 现在**只能由运行时描述符**传入
（`lib/index.js:395`），插件配置里根本够不着 —— 所以这个键在 0.2.1 上没有任何替代写法，
只能删。叶子约束改由 `maxDepth: 1` 兜底：`resolveChildDepth()` 会直接拒绝
`subagent depth N exceeds maxDepth M`。

**改法**（两处）：

- `presets/redteam/agent.cordis.yml`：删掉 `- id: tool-subagent` 行里的 `toolFilter: deny: [...]`，保留 `maxDepth: 1`
- `lib/redteam/index.js` 的 `repairDelegation()`：新增 `stripRetiredSubagentKeys(text)`，
  **按行**删掉 `toolFilter:` / `persona:` 块，并把键行替换成解释性注释。行式删除的关键细节：
  块内注释的缩进比键深，必须只在 `nextIndent >= indent.length` 时继续吞行，
  否则会把同级的块后注释一起删掉、YAML 直接坏掉（`BAD_INDENT`）

**验证**：

```bash
cd <DSH_HOME>/profiles/desktop/node_modules/dsh-purge
# 预设不再含可执行的 toolFilter
grep -n '^\s*toolFilter:' presets/redteam/agent.cordis.yml     # 应无输出
# 老格式预设能被自动修好（把带 toolFilter 的副本放进临时 DSH_HOME）
DSH_HOME=<tmp> ELECTRON_RUN_AS_NODE=1 "<DSH>/DSH Desktop.exe" \
  -e "import('./lib/redteam/index.js').then((m)=>{console.log(JSON.stringify(m.installPreset({log:console.log})))})"
# 期望：{"action":"repaired","repaired":"delegation+anchor-script"}
```

---

## FIX-03 · 宿主不再注册 `cwd` 提示词变量

**症状**：`unknown prompt variable "{{cwd}}" in section "X"; registered variables: model, provider`
→ `renderPrompt` 抛错 → 整批 sections 被丢（表现为"任务到一半苏醒 / 拒答"）。或者用别的办法
清掉 `{{cwd}}` 之后，提示词里留下 `Working directory: { {cwd}}.` 这种转义残渣。

**根因**：`0.2.1` 的 `@deepseek-ai/dsh-system-prompt` 严格插值，`interpolate()` 遇到未注册变量
直接 throw；而 `cwd` 这个变量在 0.2.1 里**没有**人注册了（只剩 `provider` / `model`）。
`assemble` 的上下文是 `{ agent, scope: agent, signal }`，所以工作目录要从
`context.agent.session.header.cwd` 取；另外 `@deepseek-ai/dsh-working-directory` 注册了一个
`required: true`、`interpolate: false` 的 `working-directory:current` 运行时上下文。

**改法**（双保险，优先第一条）：

1. `lib/identity.js` 的 `cwdSentence(context)`：**有组装上下文时直接取值写成字面量**
   `Your working directory is <路径>.`，压根不用占位符。这样宿主以后怎么改变量机制都不受影响。
2. `ensureCwdPromptVariable(prompt)`：宿主没注册 `cwd` 时，插件自己
   `prompt.variable("cwd", provider)` 注册回来（provider 读 `agent.session.header.cwd`，
   取不到返回空串，绝不抛），并把 `escapeDshInterpolation()` 的放行名单从
   `["model","provider"]` 扩到含 `cwd`。

**注意**：`stripHarnessPersona()` 里所有 `"Working directory: {{cwd}}. "` 的替换文本都改成了 `""`
—— 避免和工作目录运行时上下文重复渲染同一句。

**验证**：

```bash
# 组装一次，确认尾部是真实路径、没有 { {cwd}} 残渣
ELECTRON_RUN_AS_NODE=1 "<DSH>/DSH Desktop.exe" -e "
import('./lib/identity.js').then((m)=>{
  const asm={sections:[
    {name:'deployment:persona-prefix',text:'… Your working directory is {{cwd}}. ',order:10100},
    {name:'deployment:persona-suffix',text:'',order:10200}],contexts:[],tools:[],variables:{model:'m'}};
  const out=m.rewritePromptAssembly(asm,'',{context:{agent:{session:{header:{cwd:'D:\\\\demo'}}}}});
  for(const s of out.sections) console.log(s.name, JSON.stringify(s.text));
});"
# 期望 suffix = "Your working directory is D:\\demo."
```

---

## FIX-04 · `#40 COMPLETE_PROMPT_KEEP_INJECT` 锚点失配

**症状**：`patchStatus` 里 #40 是 `skipped`（非严格模式在已存在的文件里没命中）→
complete 模式下 purge 注入被吞。

**根因**：宿主 `@deepseek-ai/dsh-system-prompt/lib/index.js` 的 `assemble()` 改了：

```js
const transformed = await this.ctx.waterfall(scopeTarget(this, scope), "system-prompt/assemble", assembly, context, () => Promise.resolve(assembly));
if (completeSection === void 0 && !runtimeContextSuppressed) return transformed;
const requiredContexts = new Set([...contextByName.values()].filter((entry) => entry.required === true).map((entry) => entry.name));
return { ...transformed,
  sections: completeSection === void 0 ? transformed.sections : [completeSection],
  contexts: runtimeContextSuppressed ? transformed.contexts.filter((entry) => requiredContexts.has(entry.name)) : transformed.contexts };
```

老补丁找的那句字面量 `contexts: runtimeContextSuppressed ? [] : transformed.contexts` **已经不存在了**。
0.2.1 改成只保留 `required: true` 的上下文。

**改法**：把替换体抽成 `completePromptInjectBody(contextsLine)`（默认值仍是老写法），
`#40` 增加一个 0.2.1 形态的 pattern：匹配上面 398-405 那段（含 `const requiredContexts = …`
和过滤后的 `contexts` 行），替换成一个 IIFE 调用 `completePromptInjectBody("<宿主 contexts 行>")`，
并把 `const requiredContexts = …` 那行拼回第一个换行之后。

**验证**：

```bash
ELECTRON_RUN_AS_NODE=1 "<DSH>/DSH Desktop.exe" lib/audit-apply.mjs 40
# 期望：changed (+NNN bytes) + "✓ result parses as ESM"，failures: 0
```

---

## FIX-05 · `desktop-shell` 定位不到主进程文件

**症状**：`patchStatus` 里 `desktop-shell` 系列报 `missing_file`；所有改 `lib/main.js` 的补丁静默失效。

**根因**：`isOfficialHarnessExecutable()` 只认 `deepseek-harness` 一类的可执行名，
而桌面版的可执行文件叫 **`DSH Desktop.exe`**，于是 `officialShellMain()` 返回空串。

**改法**：`lib/desktop.js` 增加 `OFFICIAL_DESKTOP_BASES = new Set(["dsh desktop.exe", "dsh-desktop.exe", "dsh desktop", "dsh-desktop"])`
并放宽正则到 `/^dsh[\s._-]*desktop(\.exe)?$/`。

**验证**：`desktop-shell` 应解析到 `…\resources\app\lib\main.js`，状态从 `missing_file` 变 `skipped`/`applied`。

---

## FIX-06 · assemble 抛错时整个提示词被丢空

**症状**：宿主 `system-prompt/assemble` 一抛（比如上面第 3 条的未知变量），兜底返回
`{ sections: [], contexts: [], tools: [] }` —— **整个系统提示词消失**，表现就是"人格掉了 / 拒答"。

**根因**：`installAssembleGuard` 的内层 catch 直接吞成空段表。

**改法**：新增 `literalSectionFallback(context)`：按宿主注册顺序从 `prompt.layers.global` +
`promptChainLayers(prompt, context?.scope)` 重建段表，丢掉所有**插值过不了**的段
（用 `textInterpolates(text, variables)` 判定），幸存段标 `interpolate: false`，
返回 `{ sections, contexts: [], tools: [] }`；重建不出来才退回空段表。

**验证**：让宿主抛一次（例如临时造一个含未注册变量的段），确认输出仍有 `dsh-purge` 与
capabilities 段，且没有 `{ {var}}` 残渣。

---

> 第 7–9 条是**取长补短**时并进来的：来自对
> [`evilevil/dsh-purge-021rc2`](https://github.com/evilevil/dsh-purge-021rc2) 的逐条比对。
> 它基于上游 1.1.72，多修了三条我们 1.1.71 基线上仍在的缺陷。下面每条都标注了来源与我们的差异。

## FIX-07 · `hostFs` 白名单漏 `closeSync` → 备份一份都写不出来，还原/卸载全废

**症状**：应用之后宿主目录下**一个 `.dshpurge.bak` 都没有**；点"还原"没东西可还原，
卸载也回滚不回去。界面上不一定报错——错误被 `try{}catch{}` 吞掉了。

**根因**：`lib/extract-asar.js` 的 `HOST_SYNC` 白名单漏了 `closeSync`，而 `hostFs` 的方法
是照这张表生成的：

```js
for (const method of HOST_SYNC) hostFs[method] = route(method, false);
```

不在表里 → **`hostFs.closeSync` 根本不存在**。而 `backupAll()` 用它释放占位句柄：

```js
placeholderFd = fs.openSync(bak, "wx");                          // 建占位，防 overwrite 竞态
try { fs.closeSync(placeholderFd); } catch { /* ignore */ }       // ← TypeError，静默吞掉
await atomicCopyFile(fp, bak);                                   // ← 句柄没释放
```

句柄泄漏后 Windows 上 rename 报 **EPERM**，`atomicCopyFile` 失败 → 备份被 `unlinkSync` 清掉
→ 一份都不剩。`fsyncSync` / `readSync` 属同一批原子读写路径，一起缺。

**改法**：新增 `HOST_FD` 表并单独安装 —— fd 类方法的第一个参数是**文件描述符不是路径**，
不能交给 `route()`（否则会把 `String(fd)` 当路径去探 asar，还污染探针缓存）：

```js
const HOST_FD = [
  "closeSync", "fsyncSync", "fdatasyncSync", "readSync", "writeSync",
  "futimesSync", "ftruncateSync",
];
for (const method of HOST_FD) hostFs[method] = (...args) => nodeFs[method](...args);
```

fd 是进程级 OS 句柄，`node:fs` 与 `original-fs` 共用同一张描述符表，所以无论 `openSync`
当初路由到哪一侧，close / read / fsync 都成立。同时把 path 类的 `truncateSync` /
`utimesSync` 补进 `HOST_SYNC`。

> 来源：`evilevil/dsh-purge-021rc2` 的 #127 / #106。它把 fd 类和 path 类混在一张表里、
> 都走 `route()`；我们拆成两张表，避免拿 fd 去探 asar。

**验证**：对同一批目标文件跑两次 `backupAll()`：

```
修前：made 0 | errors 4 | .bak 0    首个错误 EPERM: operation not permitted, rename
修后：made 4 | errors 0 | .bak 4    第二次 made 0（wx 命中 EEXIST，幂等）
```

```js
// 直接确认方法有没有被装上
import { hostFs } from "./lib/extract-asar.js";
console.log(typeof hostFs.closeSync, typeof hostFs.readSync);  // 都应为 "function"
```

## FIX-08 · `tool-workflow` / `tool-ralph` 没禁用 → 子代理能绕过 `maxDepth: 1` 递归

**症状**：红队预设号称"子智能体是叶子节点"，但子代理实际上还能继续往下派活。

**根因**：这条约束原来由 `toolFilter.deny: [subagent_fork, workflow, ralph]` 提供，
而 `toolFilter` 在 0.2.1-rc.2 已删除。换成 `maxDepth: 1` 之后只堵住了**一条**路径：

- ✅ 子会话调 `tool-subagent` → `resolveChildDepth` 报 `subagent depth 2 exceeds maxDepth 1`
- ❌ 子会话调 `workflow` / `ralph` → 它们走另一条路

因为 `dsh-workflow-ptc` 的 `childRequest()` 组 spawn 请求时只带
`prompt / provider / model / schema`，**不带 `maxDepth`**（该文件里 `maxDepth` 出现 0 次），
于是落到 `@deepseek-ai/dsh-tool-subagent` schema 的 `.default(10)`。

而子会话**继承父预设的工具表**（`agentPreset` 省略 = inherit the parent agent's current
preset），所以预设里开着 `tool-workflow`，子代理手上就真有这个工具。

**改法**：`presets/redteam/agent.cordis.yml` 里给这两行加 `disabled: true`（引擎
`workflow-ptc` 保留不动，只摘工具）。红队五个执行角色走 `tool-subagent(spawn)`，不依赖它们。

> 来源：`evilevil/dsh-purge-021rc2`。
> 我们原来那段注释写着"② 子会话工具目录里本来就没有 workflow / ralph 的引擎（本预设没给子层装）"
> —— 与事实相反，已一并改正。

**验证**：

```bash
# 预设应仍可解析、没有重复 id，且两工具为 disabled
node -e "…"   # 见「复核这套修复的方法」
```

期望输出：`tool-workflow : disabled` / `tool-ralph : disabled` / `workflow-ptc : ENABLED`。

## FIX-09 · `repairOfficialCliAfterUnpack()` 同步函数里调 async，Node 24 升级成致命错

**症状**：桌面端点"应用"后 `dsh: fatal load failure`，宿主直接挂。

**根因**：该函数是同步的，却在里面调 async 的 `atomicCopyFile()` 且不 `await`：

```js
try { atomicCopyFile(fp, bak); } catch { /* 写不了 bak 不致命 */ }   // ← sync catch 抓不住
```

`atomicCopyFile` 返回 Promise，reject 时同步 `try/catch` 完全捕获不到，经 Node 24 的
`unhandledRejection` 升级成 `uncaughtException`。

**改法**：改用同样是「临时文件 + rename」原子写、但全程同步的 `atomicWriteSync()`，
顺手把 `atomicCopyFile` 从 `desktop.js` 的 import 里去掉：

```js
try { atomicWriteSync(bak, fs.readFileSync(fp)); } catch { /* 写不了 bak 不致命 */ }
```

> 来源：`evilevil/dsh-purge-021rc2` 的 #119。它把函数改成 `async` + 补 `await`，并同步改
> `core.js` / `index.js` 的调用点；我们改的是**调用处**——把 async 换成同步等价物，
> 函数签名不动，调用链零改动，波及面更小。产物字节一致。

**验证**：对一个必定失败的路径调用两种写法：

```
旧写法：unhandledRejection 触发 → Error: ENOENT … （Node 24/Electron 里升级为 uncaughtException）
新写法：同步抛出、被 try/catch 正常捕获：ENOENT
正常路径：bak 与原文字节一致 = true
```

---

## 附：补丁注册表的 `retired` 标记

`patchAppliesHere()` 新增：`if (patch?.retired) return false;`，`retired` 的行报 `na` 而不是 `skipped`。
标记为退役的（每行都带退役理由注释）：

| id | 为什么退役 |
|---|---|
| `#32` `#53` | web 面文案，桌面 profile 走不到 |
| `#45` `#46` `#82` `#83` `#84` | 同一条"桌面壳补丁链"。0.2.1 的 `resources/app/lib/main.js` 已是打包产物，锚点（`exitPromise`、`dsh desktop host exited with`、那条 `@deepseek-ai/dsh-api-gateway/stream-protocol` import）都不存在了；宿主生命周期已搬进 `@deepseek-ai/dsh`，关闭路径改成 `ProfileMaterializationError` + `result` |
| `#80` | minimal 预设不在桌面 profile 里 |
| `#77` | 宿主自带 `isRewindMarker` / `rewindVisibleEntries`；`append()` 已重构，老锚点匹配不上 |

**这不是"关掉功能"，而是把状态区分开**：以前这些行报 `skipped`，和"真的有补丁没打上"混在一起，
看不出哪个需要修。改完之后：
`applied 66 / na 15 / pending 1`（`#40` 在 complete 模式下才会落地）。

---

## 附录 B · 未变更项：Ctrl+Enter 行为

**结论：有意保留，不作修改。**

### 现状

session-controller 处理 `request.mode` 的分支被本仓库的清洗补丁改写：

| 补丁 | 位置 | 行为 |
|---|---|---|
| `#85 SESSION_PROMPT_ALWAYS_FOLLOWUP` | `lib/core.js` | 将 `if (mode === "steer") agent.steer(...) else agent.followup(...)` 整体替换为 `agent.followup(message)` |
| `#86` | `lib/core.js` | 首个 `replace` 同样强制 `agent.followup(message)`；第三个 `replace` 保留 `steer()` 的 next-step 语义 |

实测宿主日志中 `[dsh-purge-85]` 命中 1 次、`[dsh-purge-86]` 命中 2 次，即两个补丁均已生效。

### 影响

UI 发送一律开启新一轮，Ctrl+Enter **不打断**当前轮次，而是排为下一轮。

### 保留理由

该改写并非缺陷修复，而是**行为性竞态补丁**：其目的是抑制「第二轮消息立刻发送被拒」的现象（`#85` 的 `desc` 记为「消 steer→next-step 竞态（二轮立刻发被拒根因）」）。上游后续版本改回了 `agent.steer`；若本分支同步回退，会重新引入该竞态。

### 如需回退

改动点仅两处，均在 `lib/core.js`：

1. `#85` 的 `replace`：恢复 `mode === "steer"` 分支。
2. `#86` 的首个 `replace`：同上，不再强制 `followup`。

回退后应重新运行 `lib/audit-apply.mjs` 确认命中状态，并在二轮连续发送场景下复测。

---
## 附录 C · 复核方法汇总

先跑一遍随包自带的回归测试（锁死第 7–9 条，不需要联网、不需要宿主的 yaml）：

```bash
cd <DSH_HOME>/profiles/desktop/node_modules/dsh-purge
node test/fixes.test.mjs          # 等价于 npm test
```

期望输出末行：`全部通过：22 passed, 0 failed`，退出码 0。

其余检查：

```bash
cd <DSH_HOME>/profiles/desktop/node_modules/dsh-purge

# 补丁能否命中 + 应用后是否还是合法 ESM（只读内存，不写盘）
ELECTRON_RUN_AS_NODE=1 "<DSH>/DSH Desktop.exe" lib/audit-apply.mjs 40,83

# 预设行的 config 是否符合宿主 Config schema
ELECTRON_RUN_AS_NODE=1 "<DSH>/DSH Desktop.exe" lib/audit-preset-config.mjs

# 组合期是否有 patch 命不中目标（按 owner 归因）
ELECTRON_RUN_AS_NODE=1 "<DSH>/DSH Desktop.exe" lib/audit-compose.mjs
```

> 这三个脚本**没有打进发布包**（发布包的 `files` 字段不含它们的新增项时会被排除）。
> 如果你要在自己的机器上复核，从开发机拷过去，或直接看它们的源码逻辑重写一遍。

### 复核 FIX-07 … FIX-09（无需上述脚本）

```js
// ① 第 7 条：fd 类方法是否真的装上了
import { hostFs } from "./lib/extract-asar.js";
for (const m of ["closeSync", "fsyncSync", "readSync", "writeSync"])
  console.log(m, typeof hostFs[m]);            // 全部应为 "function"
```

```js
// ② 第 8 条：预设里两个工具是否已摘掉
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
// 期望：tool-workflow/tool-ralph = disabled，workflow-ptc/tool-subagent = ENABLED
```

```js
// ③ 第 9 条：跑完 backupAll 之后，磁盘上到底有没有 .bak
import { backupAll } from "./lib/core.js";
const r = await backupAll("<DSH>/resources/app/node_modules/@deepseek-ai");
console.log("made:", r.made.length, "errors:", r.errors.length);
// 期望 made > 0、errors 为 0；对应目录下出现 *.dshpurge.bak
```

```powershell
# 判据汇总：宿主目录下应当出现备份文件
Get-ChildItem "<DSH>\resources\app" -Recurse -Filter *.dshpurge.bak | Measure-Object
```

> 第 9 条的另一半判据是**不崩**：点"应用"之后宿主仍在，日志里没有
> `fatal load failure`，也没有 `unhandledRejection` / `uncaughtException`。
