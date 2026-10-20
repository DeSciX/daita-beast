// A seat never hears its own act: lib.sh event_actors (the relay's actors of an event, read from seat tags), run through
// bash with no network.
//   node --test plugin/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPTS = process.env.BEAST_TEST_SCRIPTS || join(here, "..", "scripts");
const LIB = join(SCRIPTS, "lib.sh");

// The protocol prefix is assembled, so no line of this file is itself a filled-in coordination line.
const P = "BEAST" + "-";
const ack = (seat, rest = "") => `${P}ACK seat=${seat} at=2026-10-20T20:00:00Z state=seen next=x${rest}`;
const c = (body) => ({ body, user: { login: "alice" }, html_url: "u", created_at: "2026-10-20T20:00:00Z" });

function actors(kind, delta, comments, desk = "") {
  const r = spawnSync("bash", ["-c", `source '${LIB}'; event_actors "$@"`, "x", kind, String(delta), JSON.stringify(comments), desk], { encoding: "utf8", cwd: tmpdir() });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout.split("\n").filter(Boolean);
}

test("event_actors: the filer, the closer and each tagged writer; untagged is the decider", () => {
  const close = c(`Closed on the word, verbatim: "go"\n\nRecord: r. Closed by seat alice/BEAST at 2026-10-20T20:00:00Z.\n\n${ack("alice/BEAST")}`);
  assert.deepEqual(actors("NEW", 0, [c(ack("alice/BEAST"))]), ["alice/BEAST"]);
  assert.deepEqual(actors("NEW", 0, [c(ack("alice/DEVX"))]), ["alice/DEVX"]);
  assert.deepEqual(actors("NEW", 0, []), ["-"]);
  assert.deepEqual(actors("NEW", 0, [c(ack("alice/BEAST")), c("approve")]), ["alice/BEAST", "-"]);
  assert.deepEqual(actors("DECIDED", 1, [c("go"), close]), ["alice/BEAST"]);
  assert.deepEqual(actors("DECIDED", 0, [c("go")]), ["-"]);
  assert.deepEqual(actors("DECIDED", 2, [c("go"), close]), ["alice/BEAST", "-"]);
  assert.deepEqual(actors("UPDATED", 1, [c(`Reply (BEAST).\n\n${ack("alice/BEAST")}`)]), ["alice/BEAST"]);
  assert.deepEqual(actors("UPDATED", 1, [c(`Reply.\n\n${ack("BEAST")}`)]), ["alice/BEAST"]);
  assert.deepEqual(actors("UPDATED", 1, [c("Executed: seated.")]), ["-"]);
  assert.deepEqual(actors("UPDATED", 1, [c(ack("alice/BEAST", "\n\nevidence"))]), []);
  assert.deepEqual(actors("UPDATED", 1, [c(`${P}MSG from=platform/DEVX/alice to=beast/BEAST/alice re=none blocking=no at=2026-10-20T19:11:21Z\nhi`)], "alice/BEAST"), ["alice/DEVX"]);
  assert.deepEqual(actors("UPDATED", 1, [c(`${P}ASK n=3 seat=alice/BEAST at=2026-10-20T20:00:00Z\nWhich?`)], "alice/BEAST"), ["alice/BEAST"]);
  assert.deepEqual(actors("UPDATED", 1, [c(`${P}WITHDRAW n=3`)], "alice/BEAST"), ["alice/BEAST"]);
  assert.deepEqual(actors("UPDATED", 1, [c(`${P}WITHDRAW n=3`)], ""), ["-"]);
  assert.deepEqual(actors("UPDATED", 1, [c(`${P}ANSWER n=3 b`)], "alice/BEAST"), ["-"]);
});
