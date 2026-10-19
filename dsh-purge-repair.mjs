#!/usr/bin/env node
/**
 * dsh-purge-repair.mjs —— dsh-purge 配置自愈工具（DSH Desktop 0.2.1-rc.2）
 *
 * 修什么：
 *   1) dsh-purge/cordis.patch.yml 里被重复写入的 `- insert:` 块（同一批插件行写两遍）
 *      → 症状：DSH 启动不了 / 插件配置在设置页里渲染成两块 / 同一个插件挂载两次
 *   2) 红队预设 ~/.dsh/.agent-presets/redteam/agent.cordis.yml 里 0.2.1-rc.2 已删除的
 *      `toolFilter:` / `persona:` 键（写进 @deepseek-ai/dsh-tool-subagent 的 Config 就 throw）
 *      → 症状：`tool-subagent: toolFilter is no longer supported` / 预设 broken / 派活全废
 *
 * 用法（生产机 = 装 dsh-purge 的那台）：
 *   node dsh-purge-repair.mjs              # 只检查，不改文件
 *   node dsh-purge-repair.mjs --fix        # 检查并修复，改前自动备份
 *   node dsh-purge-repair.mjs --fix --home D:\other\.dsh
 *
 * 退出码：0 = 没有发现问题（或已修好）；1 = 发现问题且未修（未加 --fix）；2 = 参数/环境错误
 */

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const YAML = await importYaml();

/**
 * 找 yaml 解析器。**不假定 DSH 装在哪、也不假定 home 在哪**。
 *
 * 顺序（每一步都是通用推导，没有写死的绝对路径）：
 *   ① 从本脚本所在目录**逐级向上**找 node_modules/yaml —— 脚本装在
 *      `<profile>/node_modules/dsh-purge/` 里，而 yaml 是 profile 自己的顶层依赖
 *      （pnpm hoisted 布局），所以这一步在**任何安装方式**下都成立。
 *   ② 顺手在向上途中收集宿主特征目录（`resources/app/node_modules`、
 *      `resources/app.asar.unpacked/node_modules`、`contents/resources/app/node_modules`）
 *      —— 桌面端把 yaml 放在这里。
 *   ③ $DSH_HOME 下各个 profile 的 node_modules/yaml（脚本被拷到别处跑时兜底）
 *   ④ 全局 `import("yaml")` —— 用户自己 npm i -g yaml 或 DSH 安装目录有解析路径时。
 */
async function importYaml() {
  const candidates = [];
  const seen = new Set();
  const push = (p) => {
    if (!p) return;
    const key = String(p).toLowerCase();
    if (seen.has(key)) return;
    seen.add(key);
    candidates.push(p);
  };

  const selfDir = (() => {
    try { return path.dirname(fileURLToPath(import.meta.url)); }
    catch { return process.cwd(); }
  })();

  // ① + ② 从脚本自身位置逐级向上
  const HOST_MARKS = [
    "resources/app/node_modules",
    "resources/app.asar.unpacked/node_modules",
    "contents/resources/app/node_modules",
  ];
  let dir = selfDir;
  for (let i = 0; i < 8; i += 1) {
    push(path.join(dir, "node_modules", "yaml", "dist", "index.js"));
    for (const mark of HOST_MARKS) push(path.join(dir, mark, "yaml", "dist", "index.js"));
    const up = path.dirname(dir);
    if (up === dir) break;
    dir = up;
  }

  // ③ $DSH_HOME 下的各个 profile
  for (const root of [process.env.DSH_HOME, path.join(os.homedir(), ".dsh")]) {
    if (!root) continue;
    const profiles = path.join(root, "profiles");
    try {
      for (const name of fs.readdirSync(profiles))
        push(path.join(profiles, name, "node_modules", "yaml", "dist", "index.js"));
    } catch { /* 没有 profiles 目录就跳过 */ }
  }

  for (const file of candidates) {
    try { return (await import(url(file))).default; } catch { /* 下一个 */ }
  }
  // ④ 让它按 Node 自己的解析规则找（含全局安装、NODE_PATH）
  try { return (await import("yaml")).default; } catch { /* 下面抛 */ }

  console.error("✗ 找不到 yaml 解析器。");
  console.error("  本脚本需要 `yaml`。三条路任选：");
  console.error("  1) 用它自己的宿主跑（推荐，DSH 一定带着 yaml）：");
  console.error('     ELECTRON_RUN_AS_NODE=1 "<DSH 安装目录>/DSH Desktop.exe" "<本脚本的完整路径>" --fix');
  console.error("     （DSH 装在哪：Get-ChildItem \"$env:LOCALAPPDATA\\Programs\",\"$env:ProgramFiles\" -Filter \"DSH Desktop.exe\" -Recurse -Depth 3）");
  console.error("  2) 从装好的插件目录里跑（脚本会向上找到 profile 自己的 node_modules/yaml）：");
  console.error('     node "<DSH_HOME>/profiles/<profile>/node_modules/dsh-purge/dsh-purge-repair.mjs" --fix');
  console.error("  3) 先补一个解析器再用真 node 跑：npm i -g yaml");
  process.exit(2);
}

function url(p) { return new URL("file:///" + String(p).replace(/\\/g, "/").replace(/^\/+/, "")).href; }

const args = process.argv.slice(2);
const FIX = args.includes("--fix");
const homeIndex = args.indexOf("--home");
const HOME = homeIndex >= 0 ? args[homeIndex + 1] : (process.env.DSH_HOME || path.join(os.homedir(), ".dsh"));

const problems = [];
const fixes = [];

/* ---------- ① bundle patch：重复 insert 块 ---------- */

function pluginPatchFile() {
  const direct = path.join(HOME, "profiles", "desktop", "node_modules", "dsh-purge", "cordis.patch.yml");
  if (fs.existsSync(direct)) return direct;
  const profiles = path.join(HOME, "profiles");
  if (!fs.existsSync(profiles)) return null;
  for (const name of fs.readdirSync(profiles)) {
    const candidate = path.join(profiles, name, "node_modules", "dsh-purge", "cordis.patch.yml");
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
}

/** 把顶层数组里的每个 patch 切成 [起始行, 结束行) —— 顶层 `- ` 开头的行是分隔点。 */
function splitTopLevelPatches(lines) {
  const starts = [];
  for (let i = 0; i < lines.length; i += 1) if (/^- /.test(lines[i]) || lines[i] === "-") starts.push(i);
  return starts.map((start, index) => ({
    start,
    end: index + 1 < starts.length ? starts[index + 1] : lines.length,
  }));
}

function findByKey(value, key) {
  if (!value || typeof value !== "object") return undefined;
  if (Object.hasOwn(value, key)) return value[key];
  for (const child of Object.values(value)) {
    const found = findByKey(child, key);
    if (found !== undefined) return found;
  }
  return undefined;
}

/**
 * `!!js <表达式>` 的占位符集合。
 *
 * yaml 的 stringify 不认识自定义 tag：直接写回会得到 `root: "!!js dshHomePath('redteam')"`
 * —— 引号把表达式降级成普通字符串，宿主 eval 出一串文本，红队数据目录就静默失效了。
 * 所以序列化时先用一个绝不可能撞车的哨兵字符串占位，再按行替换回 `!!js <源码>`。
 */
const JS_SENTINELS = new Map();

function jsTag() {
  return {
    tag: "tag:yaml.org,2002:js",
    resolve(value) {
      const source = String(value);
      const sentinel = `__DSHPURGE_JS_${JS_SENTINELS.size}_${Math.random().toString(36).slice(2, 10)}__`;
      JS_SENTINELS.set(sentinel, source);
      return { __js: source, __sentinel: sentinel, toJSON() { return sentinel; } };
    },
  };
}

/** 把序列化结果里的哨兵还原成 `!!js <源码>`。 */
function restoreJs(text) {
  let out = text;
  for (const [sentinel, source] of JS_SENTINELS) {
    out = out.split(sentinel).join(`!!js ${source}`);
  }
  return out;
}

function checkBundlePatch(file) {
  const raw = fs.readFileSync(file, "utf8");
  const lines = raw.split(/\r?\n/);
  const spans = splitTopLevelPatches(lines);
  const patches = [];
  for (const span of spans) {
    const slice = lines.slice(span.start, span.end);
    const text = slice.join("\n");
    if (!/^\s*-?\s*insert\s*:/m.test(text) && !/^\s*- id:/m.test(text)) { patches.push(null); continue; }
    let parsed = null;
    try { parsed = YAML.parse(text, { customTags: [jsTag()] }); } catch { /* 交给整个文件解析 */ }
    patches.push(Array.isArray(parsed) ? parsed[0] : parsed);
  }

  const totalInserts = patches.filter((p) => p && Object.hasOwn(p, "insert")).length;
  const insertedIds = [];
  for (const patch of patches) {
    if (!patch || !Array.isArray(patch.insert)) continue;
    for (const row of patch.insert) if (row && typeof row.id === "string") insertedIds.push(row.id);
  }
  const dupIds = [...new Set(insertedIds.filter((id, index) => insertedIds.indexOf(id) !== index))];
  const insertBlocks = spans.map((span, index) => ({ ...span, patch: patches[index] })).filter((s) => s.patch && Object.hasOwn(s.patch, "insert"));

  if (totalInserts <= 1 && dupIds.length === 0) {
    console.log(`✓ ${file}`);
    console.log(`  insert 块 1 个，插件行 ${insertedIds.length} 条，无重复：${[...new Set(insertedIds)].join(", ")}`);
    return;
  }

  console.log(`✗ ${file}`);
  console.log(`  insert 块 ${totalInserts} 个，插件行 ${insertedIds.length} 条，**重复 id**：${dupIds.join(", ") || "(无，但块数异常)"}`);
  problems.push({ kind: "bundle-patch", file });

  if (!FIX) return;

  // 稳住安全网：把当前内容留一份，宿主自己的 ENOENT 兜底会读 <file>.dshpurge.bak
  const bak = `${file}.dshpurge.bak`;
  if (!fs.existsSync(bak) || fs.readFileSync(bak, "utf8") !== raw) {
    fs.writeFileSync(bak, raw, "utf8");
    console.log(`  · 已留安全网副本: ${path.basename(bak)}`);
  }

  // 保留第一个 insert 块；后续带 insert 的顶层 patch 整块丢弃；同时按 id 去重
  let keptInsert = false;
  const keptLines = [];
  const seen = new Set();
  for (const span of spans) {
    const slice = lines.slice(span.start, span.end);
    const patch = patches[spans.indexOf(span)];
    const isInsertPatch = patch && Object.hasOwn(patch, "insert");
    if (isInsertPatch && keptInsert) {
      console.log(`  · 丢弃重复 insert 块（原第 ${span.start + 1}-${span.end} 行）`);
      continue;
    }
    if (isInsertPatch) {
      keptInsert = true;
      const rows = [];
      for (const row of patch.insert) {
        if (row && typeof row.id === "string") {
          if (seen.has(row.id)) { console.log(`  · 丢弃重复插件行 ${row.id}`); continue; }
          seen.add(row.id);
        }
        rows.push(row);
      }
      // 用解析结果重建这个块（唯一需要重写的部分），其余顶层 patch 原样保留
      keptLines.push(renderInsertBlock(slice, rows));
      continue;
    }
    keptLines.push(slice.join("\n"));
  }

  const out = keptLines.join("\n").replace(/\n{3,}/g, "\n\n").replace(/\s*$/, "") + "\n";
  try {
    YAML.parse(out, { customTags: [jsTag()] });
  } catch (error) {
    console.log(`  ! 重建后的内容解析失败，放弃写入：${error.message}`);
    problems.push({ kind: "bundle-patch-unfixed", file });
    return;
  }
  fs.writeFileSync(file, out, "utf8");
  fixes.push(file);
  console.log(`  ✓ 已修复（${lines.length} 行 → ${out.split("\n").length} 行）`);
}

/**
 * 只重建 insert 块：保留原块里 `- insert:` 之前的所有行，子行按去重后的顺序重新输出。
 * `!!js` 表达式经 toJSON 还原成 `!!js <源码>`，不会退化成对象字面量。
 */
function renderInsertBlock(slice, rows) {
  const headEnd = slice.findIndex((line) => /^-?\s*insert\s*:/.test(line));
  const head = headEnd > 0 ? slice.slice(0, headEnd) : [];
  const body = restoreJs(YAML.stringify(rows, { lineWidth: 0 }));
  const indented = body
    .split("\n")
    .filter((line) => line !== "")
    .map((line) => `    ${line}`)
    .join("\n");
  return `${head.join("\n")}${head.length ? "\n" : ""}- insert:\n${indented}`;
}

/* ---------- ② 红队预设：0.2.1-rc.2 已删除的 toolFilter / persona ---------- */

const RETIRED_KEYS = ["toolFilter", "persona"];

function presetFile() {
  const candidates = [
    path.join(HOME, ".agent-presets", "redteam", "agent.cordis.yml"),
    path.join(HOME, "profiles", "desktop", "node_modules", "dsh-purge", "presets", "redteam", "agent.cordis.yml"),
  ];
  return candidates.filter((file) => fs.existsSync(file));
}

function checkPreset(file) {
  const raw = fs.readFileSync(file, "utf8");
  const lines = raw.split(/\r?\n/);
  const hits = [];
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (/^\s*#/.test(line)) continue;
    for (const key of RETIRED_KEYS) {
      if (!new RegExp(`^\\s*${key}\\s*:`).test(line)) continue;
      hits.push({ index: i, key, indent: line.match(/^\s*/)[0] });
    }
  }
  if (hits.length === 0) {
    console.log(`✓ ${file}`);
    console.log("  没有 0.2.1-rc.2 已删除的 toolFilter / persona 键");
    return;
  }

  console.log(`✗ ${file}`);
  for (const hit of hits) console.log(`  第 ${hit.index + 1} 行: ${hit.key}: —— 写进 Config 会让整行 throw`);
  problems.push({ kind: "preset-retired-key", file });

  if (!FIX) return;

  const drop = new Set();
  for (const hit of hits) {
    drop.add(hit.index);
    const indent = hit.indent.length;
    for (let j = hit.index + 1; j < lines.length; j += 1) {
      const next = lines[j];
      if (next.trim() === "") { drop.add(j); continue; }
      const nextIndent = next.match(/^\s*/)[0].length;
      if (nextIndent <= indent) break;         // 回到同级 → 键块结束
      drop.add(j);
    }
  }
  const kept = lines.filter((_, index) => !drop.has(index));
  const out = kept.join("\n").replace(/\s*$/, "") + "\n";
  try {
    YAML.parse(out, { customTags: [jsTag()] });
  } catch (error) {
    console.log(`  ! 重建后解析失败，放弃写入：${error.message}`);
    problems.push({ kind: "preset-unfixed", file });
    return;
  }
  const bak = `${file}.dsh-purge-repair.bak`;
  fs.writeFileSync(bak, raw, "utf8");
  fs.writeFileSync(file, out, "utf8");
  fixes.push(file);
  console.log(`  ✓ 已剥离（备份 ${path.basename(bak)}）`);
}

/* ---------- 主流程 ---------- */

console.log("DSH_HOME =", HOME);
console.log("");

const patch = pluginPatchFile();
if (!patch) {
  console.log("✗ 找不到 dsh-purge/cordis.patch.yml —— 确认这台机器装过 dsh-purge");
  process.exit(2);
}
checkBundlePatch(patch);
console.log("");

const presets = presetFile();
if (presets.length === 0) console.log("· 没找到红队预设文件，跳过");
for (const file of presets) { checkPreset(file); console.log(""); }

console.log("────────────────────────────────────────");
if (fixes.length > 0) {
  console.log(`已修复 ${fixes.length} 个文件。**重启 DSH 生效**（bundle patch 只在启动时读盘）。`);
  process.exit(0);
}
if (problems.length > 0) {
  console.log(`发现 ${problems.length} 处问题，未修改（加 --fix 执行修复）。`);
  process.exit(1);
}
console.log("全部正常，没有需要修的东西。");
