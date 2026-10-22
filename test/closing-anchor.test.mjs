/**
 * 末尾锚点：把关键约束在 system 结尾再讲一遍，且必须幂等、可关闭。
 *
 *   node test/closing-anchor.test.mjs
 */
import { ensureOperatorBody, withClosingAnchor, CLOSING_ANCHOR_MARK, CLOSING_ANCHOR_TEXT } from "../lib/rules.js";
import { hangOperatorPrompt, hungOperatorPrompt } from "../lib/core.js";
import { readFileSync } from "node:fs";
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

console.log("\n[anchor] 末尾重申");

check("追加一次后正文变长", () => {
  const base = "base prompt";
  const out = withClosingAnchor(base, {});
  assert(out.length > base.length, "没有追加");
  assert(out.startsWith(base), "原文被改动");
  return "+" + (out.length - base.length) + " chars";
});

check("幂等：重复调用不叠加", () => {
  const once = withClosingAnchor("x", {});
  const twice = withClosingAnchor(once, {});
  assert(once === twice, "锚点被重复追加");
  assert(once.split(CLOSING_ANCHOR_MARK).length - 1 === 1, "标记出现多次");
});

check("DSH_PURGE_ANCHOR=0 可关闭", () => {
  const base = "x";
  assert(withClosingAnchor(base, { DSH_PURGE_ANCHOR: "0" }) === base, "关闭开关无效");
});

check("空正文不追加（避免只注入一段锚点）", () => {
  assert(withClosingAnchor("", {}) === "", "空正文被追加");
  assert(withClosingAnchor("   \n", {}) === "   \n", "空白正文被追加");
});

check("锚点文本本身含三条约束", () => {
  const lines = CLOSING_ANCHOR_TEXT.trim().split("\n").filter((l) => /^\d\./.test(l));
  assert(lines.length === 3, "约束条数应为 3，实际 " + lines.length);
});

check("真实注入出口 hangOperatorPrompt 自带锚点", () => {
  hangOperatorPrompt("BASE");
  const hung = hungOperatorPrompt();
  assert(hung.includes(CLOSING_ANCHOR_MARK), "挂给宿主的正文里没有锚点");
  assert(hung.startsWith("BASE"), "原文被改动");
  return "len=" + hung.length;
});

check("ensureOperatorBody 的返回值带锚点", () => {
  const prev = process.env.DSH_PURGE_ANCHOR;
  delete process.env.DSH_PURGE_ANCHOR;
  try {
    const body = ensureOperatorBody(process.env.DSH_HOME || "");
    if (!body) return "无注入正文（跳过）";
    assert(body.includes(CLOSING_ANCHOR_MARK), "返回值里没有锚点");
    return "len=" + body.length;
  } finally {
    if (prev === undefined) delete process.env.DSH_PURGE_ANCHOR;
    else process.env.DSH_PURGE_ANCHOR = prev;
  }
});

check("host 侧 tier-1 路径已接锚点（静态断言）", () => {
  const src = readFileSync(join(ROOT, "lib", "index.js"), "utf8");
  assert(
    /text: core\.withClosingAnchor\(text \|\| resolved\.text\)/.test(src),
    "refreshHungOperator 的返回 text 没经过 withClosingAnchor",
  );
  assert(
    /const norm = \(s\) => core\.withClosingAnchor\(peelChatmlEnvelope/.test(src),
    "四重兜底出口没经过 withClosingAnchor",
  );
});

console.log(failed.length === 0 ? "\n全部通过：" + passed + " passed, 0 failed\n" : "\n失败：" + failed.length + " 项\n");
process.exit(failed.length === 0 ? 0 : 1);