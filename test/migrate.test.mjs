/**
 * 迁移回归：schema.js 里那两处"引用了别人作用域的常量"的死分支。
 *
 * 症状（修复前）：migrate() 里的 LEGACY_STAGE_MAP / SCOPE_SQL 只存在于
 * store-core.js 的模块作用域，schema.js 既没声明也没 import，两个 try/catch
 * 把 ReferenceError 吞掉 —— 迁移"跑过了"，但什么都没写，老库的
 * attack_step.stage_code 与 asset.scope 永远是 NULL。
 *
 * 这条用例直接对内存库跑一次 migrate()，断言回填真的落库。
 * 只用 node 内置模块：node test/migrate.test.mjs
 */
import { DatabaseSync } from "node:sqlite";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DDL, SCOPE_SQL, LEGACY_STAGE_MAP, migrate } from "../lib/redteam/schema.js";

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

console.log("\n[migrate] schema 常量与增量迁移");

check("schema.js 自带 SCOPE_SQL（不再悬空引用 store-core）", () => {
  assert(typeof SCOPE_SQL === "string" && SCOPE_SQL.includes("internal"), "SCOPE_SQL 不是 SQL 片段");
});

check("schema.js 自带 LEGACY_STAGE_MAP", () => {
  assert(LEGACY_STAGE_MAP && LEGACY_STAGE_MAP.pivot === "boundary", "LEGACY_STAGE_MAP 缺失或内容不对");
});

const dir = mkdtempSync(join(tmpdir(), "purge-migrate-"));
const db = new DatabaseSync(join(dir, "engagement.db"));
try {
  db.exec(DDL);
  db.prepare("INSERT INTO attack_step (seq, stage, title) VALUES (1, 'pivot', '隧道出口')").run();
  db.prepare("INSERT INTO attack_step (seq, stage, title) VALUES (2, 'data', '取数')").run();
  db.prepare("INSERT INTO asset (segment_cidr, ip) VALUES ('10.0.0.0/24', '10.0.0.5')").run();
  db.prepare("INSERT INTO asset (segment_cidr, ip) VALUES ('1.1.1.0/24', '1.1.1.5')").run();

  migrate(db);

  check("migrate() 把老 stage 回填成 stage_code", () => {
    const rows = db.prepare("SELECT seq, stage, stage_code FROM attack_step ORDER BY seq").all();
    const byStage = Object.fromEntries(rows.map((r) => [r.stage, r.stage_code]));
    assert(byStage.pivot === "boundary", "pivot -> " + byStage.pivot + "（期望 boundary）");
    assert(byStage.data === "internal", "data -> " + byStage.data + "（期望 internal）");
    return "pivot->boundary, data->internal";
  });

  check("migrate() 回填 asset.scope（内网/外网）", () => {
    const rows = db.prepare("SELECT ip, scope FROM asset ORDER BY ip").all();
    const byIp = Object.fromEntries(rows.map((r) => [r.ip, r.scope]));
    assert(byIp["10.0.0.5"] === "internal", "10.0.0.5 -> " + byIp["10.0.0.5"]);
    assert(byIp["1.1.1.5"] === "external", "1.1.1.5 -> " + byIp["1.1.1.5"]);
    return "10.0.0.5->internal, 1.1.1.5->external";
  });

  check("migrate() 可重复执行（幂等）", () => {
    const before = db.prepare("SELECT COUNT(*) AS n, SUM(COALESCE(stage_code, '')) AS s FROM attack_step").get();
    migrate(db);
    const after = db.prepare("SELECT COUNT(*) AS n, SUM(COALESCE(stage_code, '')) AS s FROM attack_step").get();
    assert(before.n === after.n && before.s === after.s, "第二次 migrate 改了数据");
    return "二次运行无变化";
  });

  check("重复迁移不会把显式指定的阶段打回自动推导", () => {
    db.prepare("INSERT INTO attack_step (seq, stage, stage_code, title) VALUES (3, 'target', 'target', '靶标权限')").run();
    migrate(db);
    const row = db.prepare("SELECT stage_code FROM attack_step WHERE seq = 3").get();
    assert(row.stage_code === "target", "显式 stage_code 被改成了 " + row.stage_code);
    return "target 保留";
  });
} finally {
  db.close();
  rmSync(dir, { recursive: true, force: true });
}

console.log(failed.length === 0 ? "\n全部通过：" + passed + " passed, 0 failed\n" : "\n失败：" + failed.length + " 项\n");
process.exit(failed.length === 0 ? 0 : 1);