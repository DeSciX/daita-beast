// A seat never hears its own act, and the Stop hook never asks for a twin of a filed row. Two owners, run with no
// network: lib.sh event_actors (the relay's actors of an event, read from seat tags) through bash, and
// scripts/ask-guard.sh on built transcripts, with a stub gh that serves issues from a directory (never GitHub).
//   node --test plugin/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync, readFileSync } from "node:fs";
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

// ---- ask-guard.sh: a fixture checkout (the seat's home), a stub gh, and a transcript per case ----
const W = mkdtempSync(join(tmpdir(), "beast-echo-"));
const H = join(W, "home");
mkdirSync(join(H, ".beast"), { recursive: true });
execFileSync("git", ["-C", H, "init", "-q"]);
execFileSync("git", ["-C", H, "remote", "add", "origin", "https://github.com/acme/twin.git"]);
writeFileSync(join(H, ".beast", "roster.json"), JSON.stringify({ repo: "acme/twin", board: "acme/twin", people: [{ github: "alice", name: "Alice", role: "owner" }],
  seats: [{ label: "BEAST", github: "alice", repo: "acme/twin", agent: "daita-beast:seat", workstream: "beast" }] }));
const ISSUES = join(W, "issues");
mkdirSync(ISSUES);
const issue = (repo, n, state, labels) => writeFileSync(join(ISSUES, `${repo.replace("/", "__")}__${n}.json`),
  JSON.stringify({ number: n, state, labels: labels.map((name) => ({ name })), html_url: `https://github.com/${repo}/issues/${n}` }));
issue("acme/twin", 62, "open", ["decision"]);
issue("acme/twin", 52, "closed", ["decision"]);
issue("acme/other", 35, "open", ["decision"]);
const BIN = join(W, "bin");
mkdirSync(BIN);
writeFileSync(join(BIN, "gh"), `#!/usr/bin/env bash
echo "$*" >> "${W}/gh.log"
[[ "$1 $2" == "auth token" ]] && { echo stubtoken; exit 0; }
p="\${@: -1}"; [[ "$p" == -* || "$p" == GET ]] && p=""
for a in "$@"; do [[ "$a" == user || "$a" == repos/* ]] && p="$a"; done
ok() { printf 'HTTP/2.0 200 OK\\r\\nContent-Type: application/json\\r\\n\\r\\n%s\\n' "$1"; exit 0; }
[[ "$p" == user ]] && ok '{"login":"alice"}'
if [[ "$p" =~ ^repos/([^/]+)/([^/]+)/issues/([0-9]+)$ ]]; then
  f="${ISSUES}/\${BASH_REMATCH[1]}__\${BASH_REMATCH[2]}__\${BASH_REMATCH[3]}.json"
  [[ -f "$f" ]] && ok "$(cat "$f")"
  printf 'HTTP/2.0 404 Not Found\\r\\n\\r\\n{"message":"Not Found"}\\n'; exit 1
fi
echo "stub gh: unsupported $*" >&2; exit 2
`);
chmodSync(join(BIN, "gh"), 0o755);

// guard(message, command): "block" or "pass", for a turn that ran <command> (or nothing) and ended with <message>.
function guard(message, command = "") {
  const t = join(W, "t.jsonl");
  const rows = [
    { type: "user", promptId: "old", message: { content: [{ type: "tool_result", tool_use_id: "j", content: `SEATED alice/BEAST at ${H}\n` }] } },
    { type: "user", promptId: "turn", message: { content: "go on" } },
  ];
  if (command) rows.push({ type: "assistant", message: { content: [{ type: "tool_use", id: "c", name: "Bash", input: { command } }] } },
    { type: "user", promptId: "turn", message: { content: [{ type: "tool_result", tool_use_id: "c", content: "filed", is_error: false }] } });
  rows.push({ type: "assistant", message: { content: [{ type: "text", text: message }] } });
  writeFileSync(t, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
  const r = spawnSync(join(SCRIPTS, "ask-guard.sh"), [], { cwd: H, encoding: "utf8",
    input: JSON.stringify({ transcript_path: t, prompt_id: "turn", stop_hook_active: false, last_assistant_message: message }),
    env: { ...process.env, PATH: `${BIN}:${process.env.PATH}`, HOME: W, BEAST_CACHE_DIR: join(W, "cache") } });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout.startsWith('{"decision": "block"') ? "block" : "pass";
}

test("ask-guard: a message that points at an open row passes", () => {
  assert.equal(guard("Nothing to act on here: the relay reported my own new row, #62. #62 is waiting on you."), "pass");
  assert.equal(guard("Still waiting on your answer to acme/other#35."), "pass");
  assert.equal(guard("Beast 1.5.8 is waiting for you to approve publishing it.\n\nAnswer on [#62](https://github.com/acme/twin/issues/62)."), "pass");
  assert.equal(guard("Can you answer https://github.com/acme/twin/issues/62?"), "pass");
});

test("ask-guard: a new question, or a pointer at nothing open, blocks", () => {
  assert.equal(guard("The build is green. Should I deploy X or Y?"), "block");
  assert.equal(guard("Per https://github.com/acme/twin/issues/52, should I deploy X or Y?"), "block");
  assert.equal(guard("#52 is waiting on you."), "block");
  assert.equal(guard("#99 is waiting on you."), "block");
  assert.equal(guard("#62 is waiting on you.\nShould I deploy X or Y?"), "block");
});

test("ask-guard: a filing command counts however it is reached", () => {
  const q = "Should I deploy X or Y?";
  for (const cmd of ["plugin/scripts/publish.sh request s --seat BEAST", "/x/plugins/cache/daita/daita-beast/1.5.8/scripts/publish.sh request s",
    "cd /x && plugin/scripts/decision.sh new --by BEAST", "plugin/scripts/pr.sh \\\n  request acme/twin#3 --seat BEAST", `"$B/desk.sh" ask BEAST --text q`])
    assert.equal(guard(q, cmd), "pass", cmd);
  assert.equal(guard(q, "plugin/scripts/publish.sh prepare s"), "block");
});

test("ask-guard: one GET per distinct row", () => {
  writeFileSync(join(W, "gh.log"), "");
  guard("#62 and https://github.com/acme/twin/issues/62 and acme/twin#62 are waiting on you; so is acme/other#35.");
  const gets = readFileSync(join(W, "gh.log"), "utf8").split("\n").filter((l) => l.includes("issues/"));
  assert.equal(gets.length, 2, gets.join("\n"));
});
