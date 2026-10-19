/**
 * 离线回归测试：把 FIXES.md 第 7–9 条锁死，防止后续改动把修复又改回去。
 *
 * 只用 node 内置模块，不依赖宿主的 yaml —— 直接从仓库根跑：
 *   node test/fixes.test.mjs
 *
 * 退出码：0 全通过 / 1 有失败。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => fs.readFileSync(path.join(ROOT, p), "utf8");

let passed = 0;
const failed = [];

function check(name, fn) {
  try {
    const detail = fn();
    passed += 1;
    console.log(`  ok   ${name}${detail ? ` — ${detail}` : ""}`);
  } catch (error) {
    failed.push([name, error]);
    console.log(`  FAIL ${name}\n         ${String(error && error.message ? error.message : error)}`);
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

/* ── 第 7 条：hostFs 的 fd 类方法必须真的装上 ───────────────────────────── */

console.log("\n[7] hostFs fd 类方法");

const { hostFs } = await import("../lib/extract-asar.js");

for (const method of ["closeSync", "fsyncSync", "readSync", "writeSync"]) {
  check(`hostFs.${method} 存在且是函数`, () => {
    assert(typeof hostFs[method] === "function", `期望 function，实际 ${typeof hostFs[method]}`);
  });
}

check("hostFs.closeSync 真的能关掉 hostFs.openSync 拿到的 fd", () => {
  const os = fs.mkdtempSync(path.join(process.env.TEMP || "/tmp", "dshpurge-test-"));
  const target = path.join(os, "probe.txt");
  try {
    const fd = hostFs.openSync(target, "wx");
    assert(hostFs.writeSync(fd, Buffer.from("x")) === 1, "writeSync 没写进 1 字节");
    hostFs.closeSync(fd);
    // 已关闭的 fd 再 close 必然 EBADF —— 说明第一次确实关成功了，没有拿 fd 当路径去路由
    let second = null;
    try { hostFs.closeSync(fd); } catch (error) { second = error; }
    assert(second && second.code === "EBADF", "第二次 closeSync 没抛 EBADF，第一次可能没真关上");
    return "open → write → close → 二次 close 抛 EBADF";
  } finally {
    fs.rmSync(os, { recursive: true, force: true });
  }
});

check("HOST_SYNC 里不含 fd 类方法，它们在 HOST_FD 里", () => {
  const src = read("lib/extract-asar.js");
  const syncBlock = /const HOST_SYNC = \[([\s\S]*?)\];/.exec(src);
  const fdBlock = /const HOST_FD = \[([\s\S]*?)\];/.exec(src);
  assert(syncBlock, "找不到 HOST_SYNC");
  assert(fdBlock, "找不到 HOST_FD");
  for (const method of ["closeSync", "readSync", "writeSync"]) {
    assert(!syncBlock[1].includes(`"${method}"`), `${method} 不该留在 HOST_SYNC`);
    assert(fdBlock[1].includes(`"${method}"`), `${method} 应出现在 HOST_FD`);
  }
});

/* ── 第 8 条：预设里 workflow / ralph 的工具必须摘掉 ──────────────────────── */

console.log("\n[8] 红队预设的叶子边界");

const preset = read("presets/redteam/agent.cordis.yml");

function entryBlock(id) {
  const lines = preset.split("\n");
  const start = lines.findIndex((l) => new RegExp(`^\\s*- id: ${id}$`).test(l));
  if (start < 0) return null;
  const indent = lines[start].match(/^\s*/)[0].length;
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (line.trim() === "") continue;
    if (line.match(/^\s*/)[0].length <= indent && /^\s*-\s/.test(line)) { end = i; break; }
  }
  return lines.slice(start, end).join("\n");
}

for (const id of ["tool-workflow", "tool-ralph"]) {
  check(`${id} 已 disabled: true`, () => {
    const block = entryBlock(id);
    assert(block, `预设里找不到 ${id}`);
    assert(/^\s*disabled: true\s*$/m.test(block), `${id} 没有 disabled: true —— 子代理能拿它绕过 maxDepth`);
  });
}

check("workflow-ptc 引擎仍然挂着（只摘工具，不拆引擎）", () => {
  const block = entryBlock("workflow-ptc");
  assert(block, "找不到 workflow-ptc");
  assert(!/^\s*disabled: true\s*$/m.test(block), "workflow-ptc 不该被 disabled");
});

check("tool-subagent 仍是 maxDepth: 1", () => {
  const block = entryBlock("tool-subagent");
  assert(block, "找不到 tool-subagent");
  assert(/^\s*maxDepth: 1\s*$/m.test(block), "tool-subagent 的 maxDepth 不是 1");
});

check("预设里没有可执行的 toolFilter / persona（只在注释里出现）", () => {
  const offenders = preset.split("\n").filter((l) => /^\s*(toolFilter|persona):/.test(l));
  assert(offenders.length === 0, `仍有 ${offenders.length} 行配置键：${offenders[0]}`);
});

check("预设没有重复 id（宿主 entryMap 会静默覆盖）", () => {
  const ids = [...preset.matchAll(/^\s*- id: (\S+)\s*$/gm)].map((m) => m[1]);
  const dup = ids.filter((v, i, a) => a.indexOf(v) !== i);
  assert(dup.length === 0, `重复 id: ${[...new Set(dup)].join(", ")}`);
  return `${ids.length} 个 id`;
});

/* ── 第 8 条（续）：已落地预设的自愈 ───────────────────────────────────── */

console.log("\n[8b] 已落地预设的自愈（installPreset 非 force 路径）");

{
  const os = await import("node:os");
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "dshpurge-leaf-"));
  const prevHome = process.env.DSH_HOME;
  process.env.DSH_HOME = home;
  try {
    const dir = path.join(home, ".agent-presets", "redteam");
    fs.mkdirSync(dir, { recursive: true });
    const stale = [
      "tools:",
      "  - tool-workflow",
      "",
      "entries:",
      "  - id: tool-workflow",
      "    name: '@deepseek-ai/dsh-tool-workflow'",
      "  - id: tool-ralph",
      "    name: '@deepseek-ai/dsh-tool-ralph'",
      "    config:",
      "      subagentProvider: spawn",
      "  - id: workflow-ptc",
      "    name: '@deepseek-ai/dsh-workflow-ptc'",
      "  - id: tool-subagent",
      "    name: '@deepseek-ai/dsh-tool-subagent'",
      "    config:",
      "      maxDepth: 1",
      "# USER-EDIT-MARKER",
      "",
    ].join("\n");
    fs.writeFileSync(path.join(dir, "agent.cordis.yml"), stale);

    const { installPreset } = await import("../lib/redteam/index.js");
    const result = installPreset({ log: () => {} });
    const text = fs.readFileSync(path.join(dir, "agent.cordis.yml"), "utf8");
    const block = (id) => {
      const at = text.indexOf(`- id: ${id}`);
      if (at < 0) return null;
      const rest = text.slice(at + `- id: ${id}`.length);
      const end = rest.search(/\n[ \t]*- id: /);
      return end < 0 ? rest : rest.slice(0, end);
    };

    check("旧预设里的 tool-workflow 被补上 disabled: true", () => {
      assert(/disabled:\s*true/.test(block("tool-workflow")), "tool-workflow 仍是 enabled");
    });
    check("旧预设里的 tool-ralph 被补上 disabled: true", () => {
      assert(/disabled:\s*true/.test(block("tool-ralph")), "tool-ralph 仍是 enabled");
    });
    check("workflow-ptc 引擎没有被连带 disabled", () => {
      assert(!/disabled:\s*true/.test(block("workflow-ptc")), "workflow-ptc 被误关");
    });
    check("用户的其它改动被保留（不整份覆盖）", () => {
      assert(text.includes("# USER-EDIT-MARKER"), "用户标记丢了 —— 说明走了整份覆盖");
    });
    check("repaired 里记录了 leaf-boundary", () => {
      const list = result.repaired || [];
      assert(list.includes("leaf-boundary"), `repaired=${JSON.stringify(list)}`);
      return JSON.stringify(list);
    });
    check("再跑一次是幂等的（不再报 leaf-boundary）", () => {
      const again = installPreset({ log: () => {} });
      assert(!(again.repaired || []).includes("leaf-boundary"), "第二次仍在改，说明不幂等");
      return `action=${again.action}`;
    });
  } finally {
    if (prevHome === undefined) delete process.env.DSH_HOME;
    else process.env.DSH_HOME = prevHome;
    fs.rmSync(home, { recursive: true, force: true });
  }
}

/* ── 第 9 条：同步函数里不能再调 async ───────────────────────────────────── */

console.log("\n[9] repairOfficialCliAfterUnpack 全程同步");

const desktopSrc = read("lib/desktop.js");

check("desktop.js 不再 import atomicCopyFile", () => {
  assert(!/import\s*\{[^}]*atomicCopyFile[^}]*\}\s*from/.test(desktopSrc), "仍在 import atomicCopyFile");
});

check("desktop.js 里没有 atomicCopyFile( 调用", () => {
  // 注释里提到它没问题，调用不行
  const calls = desktopSrc
    .split("\n")
    .filter((l) => !l.trim().startsWith("//") && !l.trim().startsWith("*") && /\batomicCopyFile\s*\(/.test(l));
  assert(calls.length === 0, `仍有调用：${calls[0]?.trim()}`);
});

check("备份改用 atomicWriteSync(bak, fs.readFileSync(...))", () => {
  assert(/atomicWriteSync\(\s*bak\s*,\s*fs\.readFileSync\(/.test(desktopSrc), "没找到同步备份写法");
});

check("repairOfficialCliAfterUnpack 不是 async（签名没被改成 async）", () => {
  const m = /export\s+(async\s+)?function\s+repairOfficialCliAfterUnpack/.exec(desktopSrc);
  assert(m, "找不到该函数");
  assert(!m[1], "函数被改成了 async —— 那会波及所有调用点");
});

/* ── 汇总 ─────────────────────────────────────────────────────────────── */

console.log(`\n${failed.length === 0 ? "全部通过" : "有失败"}：${passed} passed, ${failed.length} failed\n`);
if (failed.length > 0) process.exitCode = 1;
