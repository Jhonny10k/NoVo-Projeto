import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("analytics migration avoids reserved day alias in PL/pgSQL", async () => {
  const sql = await readFile(new URL("../supabase/migrations/202608150013_analytics_utm.sql", import.meta.url), "utf8");
  assert.match(sql, /g::date\s+as\s+day_value/i);
  assert.doesNotMatch(sql, /g::date\s+day[,\s]/i);
  assert.match(sql, /d\.day_value/);
});
