// decision.sh restore, end to end against a stub gh (gh-stub.mjs, which keeps the body's edit history and serves it to the
// GraphQL userContentEdits query), with no network:
//   - the measured shape (2026-10-21): a row filed by decision.sh new, then a hand edit emptying ## Recommendation; restore
//     by its seat writes the filed body back byte for byte and posts the amend line, and the decider's earlier approval no
//     longer counts (row_answer_url);
//   - refused, with nothing written: a --by that is neither the filer nor a seat of the row; a closed row; a body that
//     already is the last script-written body; a last script-written body that is itself malformed; an unreadable history.
//   node --test plugin/tests/
// BEAST_TEST_SCRIPTS points the test at another tree (a gate's negative control); BEAST_TEST_TMP is where the fixtures are
// written (default: the OS temp dir).
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { ghStub } from "./gh-stub.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPTS = process.env.BEAST_TEST_SCRIPTS || join(here, "..", "scripts");
const W = mkdtempSync(join(process.env.BEAST_TEST_TMP || tmpdir(), "beast-restore-"));
// The protocol prefix is assembled, so no line of this file is itself a filled-in coordination line.
const P = "BEAST" + "-";
const REPO = "acme/twin";
const AMEND_RE = /^Amended at \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z: restored the body recorded at /;
const BODY_RE = new RegExp(`^${P}BODY digest=[0-9a-f]{40}$`);
const SIX = "## Decision\nd\n\n## Unblocks\nu\n\n## Waits\nw\n\n## Recommendation\nr\n\n## Approve with\n\"go\"\n\n## Record\nrec\n";
// The fixture's digest of a body it injects (the body line's definition: sha256, CR removed, trailing newlines trimmed,
// 40 hex); the first test holds it equal to lib.sh body_digest.
const digest = (b) => createHash("sha256").update(b.replace(/\r/g, "").replace(/\n+$/, "")).digest("hex").slice(0, 40);

function world(name) {
  const H = join(W, name), D = join(W, name + "-gh");
  mkdirSync(join(H, ".beast"), { recursive: true });
  execFileSync("git", ["-C", H, "init", "-q"]);
  execFileSync("git", ["-C", H, "remote", "add", "origin", `https://github.com/${REPO}.git`]);
  writeFileSync(join(H, ".beast", "roster.json"), JSON.stringify({ repo: REPO, board: REPO, people: [{ github: "alice", name: "Alice", role: "owner" }],
    seats: ["DEVPLANE", "DEVX"].map((label) => ({ label, github: "alice", repo: REPO, agent: "daita-beast:seat", workstream: "platform" })) }));
  const gh = ghStub(D, { login: "alice", repos: { [REPO]: { private: true } }, issues: {}, comments: {}, milestones: {} });
  const home = join(W, name + "-home"); mkdirSync(home, { recursive: true });
  const env = { ...process.env, PATH: `${gh.bin}:${process.env.PATH}`, HOME: home, BEAST_CACHE_DIR: join(W, name + "-cache"), BEAST_WS_CACHE: "" };
  const run = (script, args) => spawnSync(join(SCRIPTS, script), args, { cwd: H, encoding: "utf8", env });
  const sh = (code, args = []) => spawnSync("bash", ["-c", `source '${join(SCRIPTS, "lib.sh")}'; ${code}`, "sh", ...args], { cwd: H, encoding: "utf8", env });
  // A hand edit of the body under the shared login, as measured 2026-10-21: gh api PATCH, straight past the scripts.
  const handEdit = (n, body) => { const f = join(D, "hand.md"); writeFileSync(f, body); execFileSync(join(gh.bin, "gh"), ["api", "-X", "PATCH", `repos/${REPO}/issues/${n}`, "-F", `body=@${f}`], { env }); };
  const edit = (f) => { const s = gh.state(); f(s); writeFileSync(join(D, "state.json"), JSON.stringify(s)); };
  const file = () => {
    const r = run("decision.sh", ["new", "--title", "retire apiserver", "--assignee", "alice", "--by", "DEVPLANE", "--decision", "d", "--unblocks", "u",
      "--waits", "w", "--recommendation", "Approve: it can only restore what the protocol wrote.", "--approve-with", "go", "--record", "rec"]);
    assert.equal(r.status, 0, r.stderr);
    return Number(r.stdout.trim().split("\n").pop().split("/").pop());
  };
  return { gh, run, sh, handEdit, edit, file };
}
const comments = (gh, n) => gh.state().comments[`${REPO}#${n}`] || [];
// The stub logs every non-GET as WRITE; the GraphQL read of the edit history is a POST that writes nothing.
const writes = (gh) => gh.log().filter((l) => l.startsWith("WRITE ") && !l.startsWith("WRITE POST graphql "));

test("a hand edit empties a section: restore by the filer brings back the filed body byte for byte; the amend line voids the earlier approval", () => {
  const { gh, run, sh, handEdit, edit, file } = world("shape68");
  const n = file();
  const filed = gh.state().issues[`${REPO}#${n}`].body;
  assert.equal(sh(`body_digest "$1"`, [filed]).stdout.trim(), digest(filed), "lib.sh body_digest is the fixture's digest");
  const ack = comments(gh, n)[0].body.split("\n");
  assert.match(ack[0], new RegExp(`^${P}ACK seat=alice/DEVPLANE `), "the filer's ack is still the first line");
  assert.equal(ack.at(-1), `${P}BODY digest=${digest(filed)}`, "the filer's ack records the body it filed");
  // 33 s later: a hand edit empties ## Recommendation.
  handEdit(n, filed.replace(/## Recommendation\n[^\n]+\n/, "## Recommendation\n\n"));
  assert.notEqual(gh.state().issues[`${REPO}#${n}`].body, filed);
  // The decider approved before the restore.
  edit((s) => { s.comments[`${REPO}#${n}`].push({ id: 77, body: "go", user: { login: "alice" }, created_at: "2026-10-21T18:14:00Z", html_url: `x#approve` }); });
  const approved = () => sh(`rd="$(row_read ${REPO} ${n})" || exit 1; row_answer_url "$rd" go approve`);
  assert.equal(approved().stdout.trim(), "x#approve", "before the restore the approval stands");
  const before = writes(gh).length;
  const r = run("decision.sh", ["restore", `${REPO}#${n}`, "--by", "DEVPLANE"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(gh.state().issues[`${REPO}#${n}`].body, filed, "the body is the filed body, byte for byte");
  const w = writes(gh).slice(before);
  assert.equal(w.length, 2, w.join("\n"));
  assert.match(w[0], /^WRITE POST repos\/acme\/twin\/issues\/\d+\/comments /, "the amend comment first");
  assert.match(w[1], /^WRITE PATCH repos\/acme\/twin\/issues\/\d+ /, "then the body");
  const amend = comments(gh, n).at(-1).body.split("\n");
  assert.match(amend[0], AMEND_RE, amend[0]);
  assert.match(amend[0], /changed: Recommendation$/, amend[0]);
  assert.equal(amend.at(-1), `${P}BODY digest=${digest(filed)}`);
  const after = approved();
  assert.equal(after.status, 0, after.stderr);
  assert.equal(after.stdout.trim(), "", "the approval given before the amend line no longer counts");
  assert.match(after.stderr, /predates the amend/, after.stderr);
  // Run again: nothing left to restore.
  const again = run("decision.sh", ["restore", `${REPO}#${n}`, "--by", "DEVPLANE"]);
  assert.notEqual(again.status, 0);
  assert.match(again.stderr, /nothing to restore/, again.stderr);
});

test("a --by that is neither the row's filer nor one of its seats is refused, nothing written", () => {
  const { gh, run, handEdit, file } = world("nonseat");
  const n = file();
  handEdit(n, SIX.replace("## Recommendation\nr\n", "## Recommendation\n\n"));
  const before = writes(gh).length;
  const r = run("decision.sh", ["restore", `${REPO}#${n}`, "--by", "DEVX"]);
  assert.notEqual(r.status, 0, r.stdout);
  assert.match(r.stderr, /alice\/DEVX is neither the row's filer \(alice\/DEVPLANE\) nor one of its seats/, r.stderr);
  assert.equal(writes(gh).length, before, "nothing was written");
});

test("a closed row is refused, nothing written", () => {
  const { gh, run, handEdit, edit, file } = world("closed");
  const n = file();
  handEdit(n, SIX.replace("## Recommendation\nr\n", "## Recommendation\n\n"));
  edit((s) => { const it = s.issues[`${REPO}#${n}`]; it.state = "closed"; it.closed_at = "2026-10-21T19:00:00Z"; });
  const before = writes(gh).length;
  const r = run("decision.sh", ["restore", `${REPO}#${n}`, "--by", "DEVPLANE"]);
  assert.notEqual(r.status, 0, r.stdout);
  assert.match(r.stderr, /is closed: a decided row is not restored/, r.stderr);
  assert.equal(writes(gh).length, before);
});

test("with nothing to restore (the body is the filed body), it refuses", () => {
  const { gh, run, file } = world("nothing");
  const n = file();
  const before = writes(gh).length;
  const r = run("decision.sh", ["restore", `${REPO}#${n}`, "--by", "DEVPLANE"]);
  assert.notEqual(r.status, 0, r.stdout);
  assert.match(r.stderr, /nothing to restore: the body already is the last body a Beast script wrote/, r.stderr);
  assert.equal(writes(gh).length, before);
});

test("when the only script-written body is itself malformed, it refuses", () => {
  const { gh, run, handEdit, edit } = world("malformed");
  const bad = SIX.replace("## Recommendation\nr\n", "## Recommendation\n\n");
  edit((s) => {
    s.issues[`${REPO}#5`] = { number: 5, title: "Decision: t", body: bad, state: "open", html_url: `https://github.com/${REPO}/issues/5`,
      labels: [{ name: "decision" }, { name: "seat:alice/DEVPLANE" }], assignees: [{ login: "alice" }], user: { login: "alice" }, comments: 1,
      created_at: "2026-10-21T18:13:21Z", updated_at: "2026-10-21T18:13:21Z", closed_at: null, repository_url: `https://api.github.com/repos/${REPO}` };
    s.comments[`${REPO}#5`] = [{ id: 1, body: `${P}ACK seat=alice/DEVPLANE at=2026-10-21T18:13:22Z state=seen next=filed; waits on the decider's word\n\n${P}BODY digest=${digest(bad)}`,
      user: { login: "alice" }, created_at: "2026-10-21T18:13:22Z", html_url: "x#ack" }];
  });
  handEdit(5, bad.replace("## Unblocks\nu\n", "## Unblocks\nhand\n"));
  const before = writes(gh).length;
  const r = run("decision.sh", ["restore", `${REPO}#5`, "--by", "DEVPLANE"]);
  assert.notEqual(r.status, 0, r.stdout);
  assert.match(r.stderr, /is itself malformed: empty or missing '## Recommendation'/, r.stderr);
  assert.equal(writes(gh).length, before);
});

test("when the edit history cannot be read, it refuses naming the cause", () => {
  const { gh, run, handEdit, edit, file } = world("nohistory");
  const n = file();
  handEdit(n, SIX.replace("## Recommendation\nr\n", "## Recommendation\n\n"));
  edit((s) => { s.edits_fail = "GraphQL: Resource not accessible by integration"; });
  const before = writes(gh).length;
  const r = run("decision.sh", ["restore", `${REPO}#${n}`, "--by", "DEVPLANE"]);
  assert.notEqual(r.status, 0, r.stdout);
  assert.match(r.stderr, /cannot read the body's edit history \(GraphQL userContentEdits\): .*Resource not accessible/, r.stderr);
  assert.equal(writes(gh).length, before);
});
