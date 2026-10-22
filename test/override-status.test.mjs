/**
 * 注入文件状态：missing / default / custom 三态。
 *
 * 原实现恒返回 "default"，状态页看不出磁盘上到底有没有文件、是不是内置默认。
 * seal 保护的是仓库里的副本，运行时仍会写一份明文 —— 这里如实标出来。
 *
 *   node test/override-status.test.mjs
 */
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { overrideStatus, defaultOverrideText, readPromptInjectFileSync } from "../lib/core.js";

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

console.log("\n[override] 注入文件三态");

const dir = mkdtempSync(join(tmpdir(), "purge-override-"));
const file = join(dir, "prompt-inject.md");

/* 占位说明：空目录这一条在下面用真实目录断言。 */

try {
  const missing = await overrideStatus(dir);
  check("空目录 -> missing", () => {
    assert(missing === "missing", "期望 missing，实际 " + missing);
  });

  const def = defaultOverrideText();
  assert(def.length > 0, "内置默认提示词为空，无法继续");
  writeFileSync(file, def, "utf8");
  const isDefault = await overrideStatus(dir);
  check("写入内置默认 -> default（明文可读）", () => {
    assert(isDefault === "default", "期望 default，实际 " + isDefault);
    return def.length + " chars";
  });

  writeFileSync(file, "# 我自己的提示词\n\n只回答一句话。\n", "utf8");
  const custom = await overrideStatus(dir);
  check("写入自定义 -> custom", () => {
    assert(custom === "custom", "期望 custom，实际 " + custom);
  });

  check("读盘函数返回的仍是磁盘原文", () => {
    assert(readPromptInjectFileSync(dir).includes("我自己的提示词"), "读到的不是自定义内容");
  });
} finally {
  rmSync(dir, { recursive: true, force: true });
}

console.log(failed.length === 0 ? "\n全部通过：" + passed + " passed, 0 failed\n" : "\n失败：" + failed.length + " 项\n");
process.exit(failed.length === 0 ? 0 : 1);