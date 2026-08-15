import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("enterprise unit policy has balanced USING expression", async () => {
  const sql = await readFile(new URL("../supabase/migrations/202608150026_enterprise_units.sql", import.meta.url), "utf8");
  const marker = "create policy organization_member_units_select";
  const start = sql.indexOf(marker);
  assert.ok(start >= 0);
  const end = sql.indexOf(";", start);
  const policy = sql.slice(start, end + 1);
  assert.match(policy, /using\s*\(public\.has_feature/i);
  assert.doesNotMatch(policy, /\]\)\)\)\);\s*$/);
});
