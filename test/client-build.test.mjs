/**
 * 构建产物防漂移：client.js 里内嵌的演练台必须等于 lib/redteam/client.js 的当前内容。
 *
 * client.js 由 scripts/build-client.mjs 生成（把 lib/redteam/client.js 塞进
 * DSH_PURGE_DRILL 标记之间）。改了源码忘了重建，发出去的客户端就是旧代码，
 * 而且它照样能跑 —— 只有细看行为才发现"修好的 bug 又在线上出现了"。
 *
 * 做法：备份 → 跑一次构建 → 比对字节 → 还原。仓库不留在改动状态。
 *
 *   node test/client-build.test.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const CLIENT = join(ROOT, "client.js");

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

console.log("\n[build] client.js 内嵌演练台与源码同步");

const original = readFileSync(CLIENT);
try {
  const built = spawnSync(process.execPath, [join(ROOT, "scripts", "build-client.mjs")], {
    cwd: ROOT,
    encoding: "utf8",
  });
  assert(built.status === 0, "构建脚本失败：" + String(built.stderr || "").slice(0, 300));

  const regenerated = readFileSync(CLIENT);
  check("client.js 与 lib/redteam/client.js 同步（未漂移）", () => {
    assert(
      Buffer.compare(original, regenerated) === 0,
      "client.js 是旧的构建产物：跑一次 npm run build:client 再提交",
    );
    return "字节一致";
  });

  check("内嵌区标记成对且有序", () => {
    const text = regenerated.toString("utf8");
    const begin = text.indexOf("/* __DSH_PURGE_DRILL_BEGIN__ */");
    const end = text.indexOf("/* __DSH_PURGE_DRILL_END__ */");
    assert(begin > 0 && end > begin, "标记缺失或顺序颠倒");
    return "内嵌 " + (end - begin) + " 字节";
  });
} finally {
  writeFileSync(CLIENT, original);
}

console.log(failed.length === 0 ? "\n全部通过：" + passed + " passed, 0 failed\n" : "\n失败：" + failed.length + " 项\n");
process.exit(failed.length === 0 ? 0 : 1);