/**
 * FTS5 降级分支的验收用例（schema.js 的注释就指向本文件）。
 *
 * FTS5 是编译期选项：Node 22.14 的 node:sqlite 没有，22.23 有。
 * 装了 FTS5 的机器永远走不到降级路径，所以要留一个能主动触发的开关：
 * REDTEAM_NO_FTS5=1。HAS_FTS5 是模块加载期算出来的常量，只能在子进程里验。
 *
 *   node test/fts-fallback.test.mjs
 */
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

let passed = 0;
const failed = [];

function check(name, fn) {
  try {
    const detail = fn();
    passed += 1;
    console.log("  ok   " + name + (detail ? " — " + detail : ""));
  } catch (error) {
    failed.push([name, error]);
    console.log("  FAIL " + name + "\n         " + String(error && error.message ? error.message : error));
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

/** 在子进程里加载 schema.js，打印 HAS_FTS5 与 DDL 是否建得起来。 */
function probe(env) {
  const script = [
    "const { HAS_FTS5, DDL, ASSET_FTS_DDL } = await import('./lib/redteam/schema.js')",
    "const { DatabaseSync } = await import('node:sqlite')",
    "const db = new DatabaseSync(':memory:')",
    "db.exec(DDL)",
    "let fts = 'skipped'",
    "if (HAS_FTS5) { db.exec(ASSET_FTS_DDL); fts = 'created' }",
    "db.close()",
    "console.log(JSON.stringify({ has: HAS_FTS5, fts }))",
  ].join("\n");
  const out = spawnSync(process.execPath, ["--input-type=module", "-e", script], {
    cwd: ROOT,
    env: { ...process.env, ...env },
    encoding: "utf8",
  });
  if (out.status !== 0) throw new Error("子进程失败：" + String(out.stderr || out.stdout).slice(0, 400));
  const lines = out.stdout.trim().split("\n");
  return JSON.parse(lines[lines.length - 1]);
}

console.log("\n[fts] FTS5 能力检测与降级路径");

check("默认环境：HAS_FTS5 是布尔值，主 DDL 能建起来", () => {
  const r = probe({ REDTEAM_NO_FTS5: "" });
  assert(typeof r.has === "boolean", "HAS_FTS5 不是布尔值");
  return "HAS_FTS5=" + r.has + "（本机 FTS5 " + (r.has ? "可用" : "缺席") + "）";
});

check("REDTEAM_NO_FTS5=1：强制降级，主 DDL 依旧可用", () => {
  const r = probe({ REDTEAM_NO_FTS5: "1" });
  assert(r.has === false, "开关没生效，HAS_FTS5 仍为 true");
  assert(r.fts === "skipped", "降级时不应建 FTS 虚拟表");
  return "HAS_FTS5=false，未建 asset_fts";
});

console.log(failed.length === 0 ? "\n全部通过：" + passed + " passed, 0 failed\n" : "\n失败：" + failed.length + " 项\n");
process.exit(failed.length === 0 ? 0 : 1);