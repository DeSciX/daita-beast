// The watchdog's contracts in lib.sh, run through bash with no network: its lines are bookkeeping (never an event, never
// a desk message), its session runs only the allowlisted scripts, and a scheduled caller names a fault once.
//   node --test plugin/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPTS = process.env.BEAST_TEST_SCRIPTS || join(here, "..", "scripts");
const LIB = join(SCRIPTS, "lib.sh");
const P = "BEAST" + "-";   // assembled, so no line of this file is itself a coordination line
const c = (body, login = "alice") => ({ body, user: { login }, html_url: "u", created_at: "2026-10-20T20:00:00Z" });
const sh = (script, args = [], env = {}) => spawnSync("bash", ["-c", script, "x", ...args], { encoding: "utf8", cwd: tmpdir(), env: { ...process.env, ...env } });

test("BEAST-WATCHDOG lines and the watchdog's notes are bookkeeping: never an UPDATED", () => {
  for (const l of [`${P}WATCHDOG to=w/DEV/alice check=unacked at=2026-10-20T20:00:00Z`, `${P}WATCHDOG machine=h at=2026-10-20T20:00:00Z check=hook-misfire`, `${P}WATCHDOG-NOTES machine=h at=2026-10-20T20:00:00Z entries=1`]) {
    const r = sh(`source '${LIB}'; comment_is_bookkeeping "$1"`, [l]);
    assert.equal(r.status, 0, `${l}: ${r.stderr}`);
    const e = sh(`source '${LIB}'; event_actors UPDATED 1 "$1" ""`, [JSON.stringify([c(l)])]);
    assert.equal(e.status, 0, e.stderr);
    assert.equal(e.stdout.trim(), "", l);
  }
  assert.notEqual(sh(`source '${LIB}'; comment_is_bookkeeping "$1"`, [`${P}WATCHDOGS x`]).status, 0);
});

test("desk_parse names a BEAST-WATCHDOG line on a desk as dropped, never a message", () => {
  const row = { issue: { assignees: [{ login: "alice" }] }, comments: [c(`${P}WATCHDOG to=w/DEV/alice check=unacked at=2026-10-20T20:00:00Z\nrows`)] };
  const r = sh(`source '${LIB}'; desk_parse alice/DEV "$1"`, [JSON.stringify(row)]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout).messages, []);
  assert.match(r.stderr, /dropped: a BEAST-WATCHDOG line is the machine watchdog's/);
});

test("under BEAST_WATCHDOG=1 a plugin script runs only when allowlisted (watchdog_guard)", () => {
  for (const [s, a] of [["ack.sh", ["o/r#1"]], ["decision.sh", ["close"]], ["desk.sh", ["answer"]], ["seats.sh", ["record"]], ["seats.sh", ["forget"]], ["seats.sh", ["touch"]], ["status.sh", []], ["notes.sh", ["DEV", "set"]]]) {
    const r = spawnSync(join(SCRIPTS, s), a, { encoding: "utf8", cwd: tmpdir(), env: { ...process.env, BEAST_WATCHDOG: "1" } });
    assert.notEqual(r.status, 0, s);
    assert.match(r.stderr, /refused: .* under the watchdog \(BEAST_WATCHDOG=1\)/, `${s}: ${r.stderr}`);
  }
  const ok = spawnSync(join(SCRIPTS, "watchdog.sh"), ["bug"], { encoding: "utf8", cwd: tmpdir(), env: { ...process.env, BEAST_WATCHDOG: "1" } });
  assert.doesNotMatch(ok.stderr, /under the watchdog/);
  const plain = spawnSync(join(SCRIPTS, "ack.sh"), [], { encoding: "utf8", cwd: tmpdir(), env: { ...process.env, BEAST_WATCHDOG: "" } });
  assert.doesNotMatch(plain.stderr, /under the watchdog/);
});

test("fault_once: a scheduled caller's ledger names a fault once per message; without it every time", () => {
  const d = mkdtempSync(join(tmpdir(), "wd-"));
  const run = (env) => sh(`source '${LIB}'; fault_once k "daita-beast: table broken"; fault_once k "daita-beast: table broken"; fault_once k "daita-beast: table broken again"`, [], env);
  const led = run({ BEAST_FAULT_LEDGER: join(d, "faults.json") });
  assert.equal(led.status, 0, led.stderr);
  assert.equal(led.stderr.split("\n").filter((l) => l.includes("table broken")).length, 2);
  assert.equal(JSON.parse(readFileSync(join(d, "faults.json"), "utf8")).k.n, 1);
  const none = run({ BEAST_FAULT_LEDGER: "" });
  assert.equal(none.stderr.split("\n").filter((l) => l.includes("table broken")).length, 3);
});
