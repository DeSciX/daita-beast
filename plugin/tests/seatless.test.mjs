// A row's seats, end to end (rows filed with `decision.sh new --by <SEAT>` and no --seat once carried only `decision`
// and reached no seat's relay):
//   - decision.sh new labels the filing seat (--by) whatever --seat says, once, and fails loud when a label does not land;
//   - the board page lists an open row waiting on the decider in "Waiting on you" and counts it in the headline whatever
//     its seat labels; grouped under "With the seats", a row with no seat label is its filer's, and one with no filer
//     ack either is in the group "—";
//   - watch.sh (the relay's poll) sends a row with no seat label to its filer, the seat of its first BEAST-ACK comment.
//   node --test plugin/tests/
// BEAST_TEST_SCRIPTS / BEAST_TEST_PAGE point the test at another tree (a gate's negative control); BEAST_TEST_TMP is
// where the fixtures are written (default: the OS temp dir).
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadPage } from "./page-harness.mjs";
import { ghStub } from "./gh-stub.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPTS = process.env.BEAST_TEST_SCRIPTS || join(here, "..", "scripts");
const PAGE = process.env.BEAST_TEST_PAGE || join(here, "..", "templates", "board.html");
const W = mkdtempSync(join(process.env.BEAST_TEST_TMP || tmpdir(), "beast-seatless-"));
const P = "BEAST" + "-";
const REPO = "acme/twin";
const SIX = "## Decision\nd\n\n## Unblocks\nu\n\n## Waits\nw\n\n## Recommendation\nr\n\n## Approve with\n\"go\"\n\n## Record\nrec\n";
const filerAck = (seat, at) => ({ id: 1, body: `${P}ACK seat=${seat} at=${at} state=seen next=filed; waits on the decider's word`, user: { login: "alice" }, created_at: at, html_url: `x#${seat}` });

function world(name, issues = {}, comments = {}) {
  const H = join(W, name), D = join(W, name + "-gh");
  mkdirSync(join(H, ".beast"), { recursive: true });
  execFileSync("git", ["-C", H, "init", "-q"]);
  execFileSync("git", ["-C", H, "remote", "add", "origin", `https://github.com/${REPO}.git`]);
  writeFileSync(join(H, ".beast", "roster.json"), JSON.stringify({ repo: REPO, board: REPO, people: [{ github: "alice", name: "Alice", role: "owner" }],
    seats: ["DEVPLANE", "DEVX"].map((label) => ({ label, github: "alice", repo: REPO, agent: "daita-beast:seat", workstream: "platform" })) }));
  const gh = ghStub(D, { login: "alice", repos: { [REPO]: { private: true } }, issues, comments, milestones: {} });
  const home = join(W, name + "-home"); mkdirSync(home, { recursive: true });
  const run = (script, args) => spawnSync(join(SCRIPTS, script), args, { cwd: H, encoding: "utf8",
    env: { ...process.env, PATH: `${gh.bin}:${process.env.PATH}`, HOME: home, BEAST_CACHE_DIR: join(W, name + "-cache"), BEAST_WS_CACHE: "" } });
  const edit = (f) => { const s = gh.state(); f(s); writeFileSync(join(D, "state.json"), JSON.stringify(s)); };
  return { gh, run, edit };
}
const fileArgs = (title) => ["new", "--title", title, "--assignee", "alice", "--by", "DEVPLANE", "--decision", "d", "--unblocks", "u", "--waits", "w",
  "--recommendation", "r", "--approve-with", "go", "--record", "rec"];
const seatLabels = (it) => it.labels.map((l) => l.name).filter((n) => n.startsWith("seat:")).sort();

test("decision.sh new --by DEVPLANE without --seat labels the row seat:<filer>", () => {
  const { gh, run } = world("new-by");
  const r = run("decision.sh", fileArgs("retire apiserver"));
  assert.equal(r.status, 0, r.stderr);
  const it = Object.values(gh.state().issues).find((x) => x.title === "Decision: retire apiserver");
  assert.ok(it, "the row was filed");
  assert.deepEqual(seatLabels(it), ["seat:alice/DEVPLANE"]);
});

test("decision.sh new labels the filer beside every --seat, once", () => {
  const { gh, run } = world("new-seats");
  assert.equal(run("decision.sh", [...fileArgs("both"), "--seat", "DEVX"]).status, 0);
  assert.equal(run("decision.sh", [...fileArgs("self"), "--seat", "DEVPLANE", "--seat", "alice/DEVPLANE"]).status, 0);
  const by = (t) => Object.values(gh.state().issues).find((x) => x.title === "Decision: " + t);
  assert.deepEqual(seatLabels(by("both")), ["seat:alice/DEVPLANE", "seat:alice/DEVX"]);
  assert.deepEqual(seatLabels(by("self")), ["seat:alice/DEVPLANE"]);
});

test("decision.sh new fails loud when the filer's seat label does not land, before the filer's ack", () => {
  const { gh, run, edit } = world("new-drop");
  edit((s) => { s.drop_labels = ["seat:alice/DEVPLANE"]; });
  const r = run("decision.sh", fileArgs("dropped"));
  assert.notEqual(r.status, 0, r.stdout);
  assert.match(r.stderr, /does not carry the label seat:alice\/DEVPLANE/, r.stderr);
  assert.deepEqual(Object.values(gh.state().comments).flat(), [], "no ack is posted on a row whose seat label is missing");
});

// ---- the page ----
const row = (n, labels, extra = {}) => ({ number: n, title: "Decision: t" + n, body: SIX, state: "open", html_url: `https://github.com/${REPO}/issues/${n}`,
  labels, comments: 1, assignees: ["alice"], created_at: "2026-10-20T22:12:27Z", updated_at: "2026-10-20T22:12:34Z", repository_url: `https://api.github.com/repos/${REPO}`, ...extra });

test("page: an open seatless row waiting on the decider is in Waiting on you and counted in the headline", async () => {
  const rows = [row(39, ["decision"]), row(41, ["decision"], { comments: 0 }), row(40, ["decision", "seat:alice/DEVX"])];
  const comments = { [`${REPO}#39`]: [filerAck("alice/DEVPLANE", "2026-10-20T22:12:33Z")] };
  const p = await loadPage(PAGE, { rows, comments });
  assert.deepEqual(p.turnRows().map((c) => c.key).sort(), [`${REPO}#39`, `${REPO}#40`, `${REPO}#41`]);
  assert.match(p.text("turn"), /^3 decisions are waiting on you/, p.text("turn"));
  assert.equal(p.text("count"), "(3 waiting)");
  assert.deepEqual(p.withSeats(), [], "no row waiting on the decider is grouped by seat");
});

test("page: answered, a seatless row is grouped under its filer, or under — with no filer ack", async () => {
  const ans = (at) => ({ body: "go", user: { login: "alice" }, created_at: at, html_url: "x#a" + at });
  const rows = [row(39, ["decision"], { comments: 2 }), row(42, ["decision"], { comments: 1 })];
  const comments = { [`${REPO}#39`]: [filerAck("alice/DEVPLANE", "2026-10-20T22:12:33Z"), ans("2026-10-20T22:36:54Z")], [`${REPO}#42`]: [ans("2026-10-21T02:15:42Z")] };
  const p = await loadPage(PAGE, { rows, comments });
  assert.deepEqual(p.turnRows(), []);
  const groups = p.doc.getElementById("tlist").find("group").map((g) => g.childNodes[0].textContent);
  assert.equal(groups.length, 2, groups.join(" | "));
  assert.match(groups[0], /^DEVPLANE1 open/, groups[0]);
  assert.match(groups[1], /^—1 open/, groups[1]);
});

// ---- the relay's poll ----
test("watch.sh sends the decider's answer on a seatless row to its filer", () => {
  const it = row(39, [{ name: "decision" }], { assignees: [{ login: "alice" }], user: { login: "alice" }, closed_at: null, created_at: new Date(Date.now() - 600e3).toISOString().replace(/\.\d+Z$/, "Z") });
  it.updated_at = it.created_at;
  const { run, edit } = world("watch", { [`${REPO}#39`]: it }, { [`${REPO}#39`]: [filerAck("alice/DEVPLANE", it.created_at)] });
  const base = run("watch.sh", ["DEVPLANE", "--once"]);
  assert.equal(base.status, 0, base.stderr);
  assert.match(base.stderr, /seat=alice\/DEVPLANE baseline 1 decision/, base.stderr);
  const now = new Date().toISOString().replace(/\.\d+Z$/, "Z");
  edit((s) => { s.comments[`${REPO}#39`].push({ id: 2, body: "retire apiserver", user: { login: "alice" }, created_at: now, html_url: "x#2" }); const r = s.issues[`${REPO}#39`]; r.comments = 2; r.updated_at = now; });
  const poll = run("watch.sh", ["DEVPLANE", "--once"]);
  assert.equal(poll.status, 0, poll.stderr);
  assert.match(poll.stdout, /^BEAST-EVENT kind=UPDATED seat=alice\/DEVPLANE Decision: t39 https:\/\/github\.com\/acme\/twin\/issues\/39$/m, poll.stdout + poll.stderr);
});
