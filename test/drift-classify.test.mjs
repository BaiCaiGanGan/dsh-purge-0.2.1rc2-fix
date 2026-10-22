/**
 * 锚点漂移检测：patchStatus 的状态不能"看起来没坏"就过去了。
 *
 * 背景：gatherState() 原先只统计 applied / pending / skipped，
 * unmatched 与 pattern_not_found 不进任何计数 —— 宿主升级改了锚点后，
 * 补丁静默失效，状态页照样显示 "0 待清洗"。
 *
 *   node test/drift-classify.test.mjs
 */
import { classifyPatchOutcome, gatherState } from "../lib/core.js";

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

const cases = [
  ["applied", null, "applied"],
  ["already", null, "applied"],
  ["pending", null, "pending"],
  ["unmatched", null, "drifted"],
  ["pattern_not_found", null, "drifted"],
  ["missing_file", { strictFiles: true }, "drifted"],
  ["missing_file", {}, "skipped"],
  ["skipped", null, "skipped"],
  ["off", null, "skipped"],
  ["na", null, "skipped"],
  ["permission denied", null, "failed"],
  [undefined, null, "unknown"],
];

console.log("\n[drift] 状态分类");

for (const [status, patch, want] of cases) {
  check((status === undefined ? "undefined" : status) + (patch && patch.strictFiles ? " + strictFiles" : "") + " -> " + want, () => {
    const got = classifyPatchOutcome(status, patch);
    assert(got === want, "期望 " + want + "，实际 " + got);
  });
}

check("strictFiles 缺文件不再被当成 skipped", () => {
  assert(classifyPatchOutcome("missing_file", { strictFiles: true }) === "drifted", "strictFiles 的 missing_file 应判为 drifted");
});

check("optional 缺文件仍算 skipped（本端不需要）", () => {
  assert(classifyPatchOutcome("missing_file", { optional: true }) === "skipped", "optional 的 missing_file 应判为 skipped");
});

console.log("\n[drift] gatherState 字段");

const state = await gatherState();
check("gatherState 暴露 patches_drifted / patches_failed", () => {
  assert(typeof state.patches_drifted === "number", "patches_drifted 不是数字");
  assert(typeof state.patches_failed === "number", "patches_failed 不是数字");
  assert(Array.isArray(state.drifted_patches), "drifted_patches 不是数组");
  return "drifted=" + state.patches_drifted + ", failed=" + state.patches_failed;
});

check("漂移清单与计数一致", () => {
  assert(state.drifted_patches.length === state.patches_drifted, "清单长度与计数不一致");
});

console.log(failed.length === 0 ? "\n全部通过：" + passed + " passed, 0 failed\n" : "\n失败：" + failed.length + " 项\n");
process.exit(failed.length === 0 ? 0 : 1);