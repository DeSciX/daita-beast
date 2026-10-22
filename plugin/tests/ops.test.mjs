// Seat-side operations under load, end to end against a stub gh (gh-stub.mjs), a fake HOME and no network:
//   - a close whose board republish hits a GitHub secondary rate limit retries with backoff (rate_retry), then leaves the
//     board's stale marker and exits 0 with one loud line; the watchdog's next tick republishes the board and the
//     successful publish clears the marker;
//   - a desk answer a seat records (desk.sh answer --by) is that seat's own act: the relay (watch.sh) sends it no event
//     and the watchdog's unacked check does not remind it, while the asker's desk still reads the answer, and another
//     seat recording on the desk is still news to the desk's seat;
//   - issue.sh new lists the repo's open issues and refuses a duplicate title (named), files it with --force, and files a
//     distinct title.
//   - a watchdog tick that hands a signal while the Beast workstream's tracking issue is missing logs the failed notes read
//     and still finishes; a tick that dies mid-checklist logs the step, the command and the exit status.
//   node --test plugin/tests/
// BEAST_TEST_SCRIPTS / BEAST_TEST_PAGE point the test at another tree (a gate's negative control); BEAST_TEST_TMP is
// where the fixtures are written (default: the OS temp dir).
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { ghStub } from "./gh-stub.mjs";
import { pageFns } from "./page-harness.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPTS = process.env.BEAST_TEST_SCRIPTS || join(here, "..", "scripts");
const LIB = join(SCRIPTS, "lib.sh");
const PAGE = process.env.BEAST_TEST_PAGE || join(here, "..", "templates", "board.html");
const W = mkdtempSync(join(process.env.BEAST_TEST_TMP || tmpdir(), "beast-ops-"));
const P = "BEAST" + "-";   // assembled, so no line of this file is itself a coordination line
const REPO = "acme/twin";
const SIX = "## Decision\nd\n\n## Unblocks\nu\n\n## Waits\nw\n\n## Recommendation\nr\n\n## Approve with\n\"go\"\n\n## Record\nrec\n";
const ago = (s) => new Date(Date.now() - s * 1000).toISOString().replace(/\.\d+Z$/, "Z");
const LOCAL = "/" + "Users/someone";
const SECONDARY = "You have exceeded a secondary rate limit. Please wait a few minutes before you try again";

// world(name, issues, comments): a checkout of acme/twin whose roster seats LEAD and OTHER (workstream w, decider acme),
// the gh stub holding the given issues, and a fake HOME. run(script, args, env) runs a plugin script there.
function world(name, issues = {}, comments = {}) {
  const H = join(W, name), D = join(W, name + "-gh"), home = join(W, name + "-home");
  mkdirSync(join(H, ".beast"), { recursive: true }); mkdirSync(home, { recursive: true });
  execFileSync("git", ["-C", H, "init", "-q"]);
  execFileSync("git", ["-C", H, "remote", "add", "origin", `https://github.com/${REPO}.git`]);
  writeFileSync(join(H, ".beast", "roster.json"), JSON.stringify({ repo: REPO, board: REPO, relay: { permissionMode: "default" },
    people: [{ github: "acme", name: "Acme", role: "owner" }],
    seats: ["LEAD", "OTHER"].map((label) => ({ label, github: "acme", repo: REPO, agent: "daita-beast:seat", workstream: "w" })) }));
  const gh = ghStub(D, { login: "acme", repos: { [REPO]: { private: true }, "acme/site": { private: false } }, issues, comments, milestones: {} });
  const env = { ...process.env, PATH: `${gh.bin}:${process.env.PATH}`, HOME: home, BEAST_CACHE_DIR: join(W, name + "-cache"), BEAST_WS_CACHE: "",
    BEAST_RATE_RETRY_BASE_S: "1", CLAUDE_PLUGIN_ROOT: join(SCRIPTS, "..") };
  const run = (script, args, extra = {}) => spawnSync(join(SCRIPTS, script), args, { cwd: H, encoding: "utf8", env: { ...env, ...extra } });
  const edit = (f) => { const s = gh.state(); f(s); writeFileSync(join(D, "state.json"), JSON.stringify(s)); };
  const sh = (script, args = []) => spawnSync("bash", ["-c", `source '${LIB}'; ${script}`, "x", ...args], { cwd: H, encoding: "utf8", env });
  return { H, home, gh, run, edit, sh };
}
const issue = (n, title, labels, extra = {}) => ({ number: n, title, body: "b", state: "open", html_url: `https://github.com/${REPO}/issues/${n}`,
  labels: labels.map((name) => ({ name })), assignees: [{ login: "acme" }], user: { login: "acme" }, comments: 0, created_at: ago(7200), updated_at: ago(7200),
  closed_at: null, repository_url: `https://api.github.com/repos/${REPO}`, milestone: null, ...extra });
let cid = 500;
const cm = (n, body, at) => ({ id: ++cid, body, user: { login: "acme" }, created_at: at, html_url: `https://github.com/${REPO}/issues/${n}#issuecomment-${cid}` });

// ---- (6) the board publish under a secondary rate limit -------------------------------------------------------------
test("gate 6: a 403 on the board publish leaves the stale marker and the close exits 0; the watchdog's next tick republishes and clears it", () => {
  const board = issue(1, "Pending decisions (generated)", [], { assignees: [], body: "old board" });
  const row = issue(2, "Decision: ship it", ["decision", "seat:acme/LEAD"], { body: SIX, comments: 1 });
  const w = world("board", { [`${REPO}#1`]: board, [`${REPO}#2`]: row },
    { [`${REPO}#2`]: [cm(2, `${P}ACK seat=acme/LEAD at=${ago(7200)} state=seen next=filed; waits on the decider's word`, ago(7200))] });
  w.edit((s) => { s.fail = [{ method: "PATCH", route: `repos/${REPO}/issues/1`, times: 99, status: 403, message: SECONDARY }]; });
  const r = w.run("decision.sh", ["close", `${REPO}#2`, "--words", "go", "--record", `${REPO} abc1234 — records/x.md`, "--by", "LEAD"]);
  assert.equal(r.status, 0, `the close exits 0 though the board was not republished\n${r.stdout}\n${r.stderr}`);
  assert.equal(w.gh.state().issues[`${REPO}#2`].state, "closed", "the row is closed");
  assert.match(r.stderr, /BOARD STALE: acme\/twin#2 IS CLOSED \(the close stands; never rerun it\)/, r.stderr);
  assert.match(r.stderr, /retrying in 1 s/, "rate_retry backed off before giving up");
  assert.equal(w.gh.log().filter((l) => l.startsWith("FAILED PATCH repos/acme/twin/issues/1")).length, 3, "three publish attempts (RATE_RETRY_TRIES)");
  const marker = join(w.home, ".beast", "board", "stale", "acme__twin__acme");
  assert.ok(existsSync(marker), "the stale marker is written");
  assert.match(readFileSync(marker, "utf8"), new RegExp(`^${P}BOARD stale since=\\S+ repo=acme/twin assignee=acme why=.*secondary rate limit`));
  assert.equal(w.gh.state().issues[`${REPO}#1`].body, "old board", "the board was not published");

  // the limit lifts; the watchdog's next tick republishes the marked board and the publish clears the marker
  w.edit((s) => { s.fail = []; });
  const t = w.run("watchdog.sh", ["--repo", w.H]);
  assert.equal(t.status, 0, `${t.stdout}\n${t.stderr}`);
  const log = readFileSync(join(w.home, ".beast", "watchdog.log"), "utf8");
  assert.match(log, /board: repaired: republished the board in acme\/twin for @acme/, log);
  assert.ok(!existsSync(marker), "the marker is cleared by the successful publish");
  assert.match(w.gh.state().issues[`${REPO}#1`].body, /^Pending decisions for @acme — 0 open .* 1 decided in the last 7 days/, "the board is republished with the close");
});

// ---- (7/8) a seat-recorded desk answer is the seat's own act --------------------------------------------------------
test("gate 7/8: a seat-recorded desk answer gives that seat no event and no unacked reminder; the asker still reads the answer", () => {
  const desk = issue(3, "Desk: acme/LEAD", ["desk", "seat:acme/LEAD"], { comments: 3, updated_at: ago(3600) });
  // #9: the plugin's own workstream tracking issue, where a tick that hands a signal to the agent reads its notes
  const tracking = issue(9, "Workstream: beast", ["workstream", "ws:beast"], { assignees: [], body: "## Seats\n| Seat | Repo | Home | Agent | Account | Address | Seen |\n|---|---|---|---|---|---|---|\n" });
  const w = world("desk", { [`${REPO}#3`]: desk, [`${REPO}#9`]: tracking }, { [`${REPO}#3`]: [
    cm(3, `${P}ASK n=1 seat=acme/LEAD at=${ago(3600)}\nWhich name?\noptions: a | b`, ago(3600)),
    cm(3, `${P}ASK n=2 seat=acme/LEAD at=${ago(3600)}\nWhich colour?`, ago(3600)),
    cm(3, `${P}ACK seat=acme/LEAD at=${ago(3590)} state=seen next=asked n=1 and n=2`, ago(3590))] });
  // the relay's baseline, then the seat records the decider's words, then the relay's next poll
  const base = w.run("watch.sh", ["LEAD", "--once"]);
  assert.equal(base.status, 0, base.stderr);
  const a = w.run("desk.sh", ["answer", "LEAD", "1", "b", "--by", "LEAD"]);
  assert.equal(a.status, 0, `${a.stdout}\n${a.stderr}`);
  const posted = w.gh.state().comments[`${REPO}#3`].at(-1).body;
  assert.match(posted.split("\n")[0], /^BEAST-ANSWER n=1 b$/);
  assert.match(posted.split("\n").at(-1), new RegExp(`^${P}ACK seat=acme/LEAD at=\\S+ state=seen next=recorded the decider's answer to n=1$`));
  const poll = w.run("watch.sh", ["LEAD", "--once"]);
  assert.equal(poll.status, 0, poll.stderr);
  assert.doesNotMatch(poll.stdout, /BEAST-EVENT/, `no event to the recorder: ${poll.stdout}`);
  assert.match(poll.stderr, /seat=acme\/LEAD own act, not sent: UPDATED https:\/\/github.com\/acme\/twin\/issues\/3/, poll.stderr);

  // the watchdog's unacked check, with no grace, on the seat's live session: nothing to remind
  const sessions = join(w.home, ".claude", "sessions"); mkdirSync(sessions, { recursive: true });
  writeFileSync(join(sessions, `${process.pid}.json`), JSON.stringify({ pid: process.pid, sessionId: "s-lead", cwd: w.H, name: "lead-1", status: "idle" }));
  writeFileSync(join(w.home, ".beast", "sessions.json"), JSON.stringify({ "w/LEAD/acme": { session: "s-lead", session_at: ago(60), launch: w.H, tracking: `${REPO}#9` } }));
  mkdirSync(join(w.home, ".beast", "watchdog"), { recursive: true });
  writeFileSync(join(w.home, ".beast", "watchdog", "state.json"), JSON.stringify({ tune: { "unacked.grace": 0 } }));
  const t = w.run("watchdog.sh", ["--repo", w.H, "--dry-run"]);
  assert.equal(t.status, 0, `${t.stdout}\n${t.stderr}`);
  assert.doesNotMatch(t.stdout, /check=unacked/, `no unacked reminder for the recorder:\n${t.stdout}`);
  assert.match(readFileSync(join(w.home, ".beast", "watchdog.log"), "utf8"), /tick: dry run|tick: quiet/);

  // the asker's desk reads the decider's answer (lib.sh desk_parse and the page's parseDesk alike), without the ack line
  const rd = JSON.stringify({ issue: { assignees: [{ login: "acme" }], number: 3 }, comments: w.gh.state().comments[`${REPO}#3`] });
  const lib = JSON.parse(w.sh(`desk_parse acme/LEAD "$1" 2>/dev/null`, [rd]).stdout);
  assert.deepEqual([lib.asks[0].state, lib.asks[0].answer.text, lib.asks[0].answer.by, lib.asks[1].state], ["answered", "b", "typed to the session", "open"]);
  const { parseDesk } = pageFns(PAGE, ["parseDesk", "ackLine", "ms", "seatMatch", "seatParts"], ["ACK_RE", "CLOSER_RE", "ASK_RE", "WAITS_RE", "ANSWER_RE", "WITHDRAW_RE", "MSG_RE", "DESK_FORM_RE"]);
  const page = JSON.parse(JSON.stringify(parseDesk(w.gh.state().comments[`${REPO}#3`], "acme/LEAD")));
  assert.deepEqual(page.open.map((x) => x.n), [2], "the page reads n=1 answered, n=2 still open");
  assert.equal(page.answered[0].answer.text.split("\n")[0], "b");
  assert.doesNotMatch(page.answered[0].answer.text, /BEAST-ACK/, "the recorder's ack is not answer text on the page");
  assert.equal(page.ackAt, w.gh.state().comments[`${REPO}#3`].at(-1).created_at, "the page reads the recorder's ack at the post, as seat_acks");

  // the positive control, on the same instruments: the decider's own answer on the desk (the page's comment, untagged) is
  // news to LEAD: the relay sends the event and the watchdog reminds while LEAD has not acked it
  w.edit((s) => { s.comments[`${REPO}#3`].push(cm(3, `${P}ANSWER n=2 blue`, ago(0))); s.issues[`${REPO}#3`].comments += 1; s.issues[`${REPO}#3`].updated_at = ago(0); });
  const poll2 = w.run("watch.sh", ["LEAD", "--once"]);
  assert.match(poll2.stdout, /^BEAST-EVENT kind=UPDATED seat=acme\/LEAD .*issues\/3$/m, `${poll2.stdout}\n${poll2.stderr}`);
  const t2 = w.run("watchdog.sh", ["--repo", w.H, "--dry-run"]);
  assert.equal(t2.status, 0, `${t2.stdout}\n${t2.stderr}`);
  assert.match(t2.stdout, /SIGNAL 1 check=unacked seat=w\/LEAD\/acme object=https:\/\/github.com\/acme\/twin\/issues\/3/, `${t2.stdout}\n${t2.stderr}`);

  // a message LEAD sent itself (report.sh --post's section for its own poster) is its own act: not desk news for LEAD;
  // one from another seat is
  const selfMsg = cm(3, `${P}MSG from=w/LEAD/acme to=w/LEAD/acme re=none blocking=no at=${ago(0)}\nyour section`, ago(0));
  const peerMsg = cm(3, `${P}MSG from=w/OTHER/acme to=w/LEAD/acme re=none blocking=no at=${ago(0)}\npeer note`, ago(0));
  const rd2 = JSON.stringify({ issue: { assignees: [{ login: "acme" }], number: 3 }, comments: [...w.gh.state().comments[`${REPO}#3`], selfMsg, peerMsg] });
  const news = w.sh(`desk_news acme/LEAD "$(desk_parse acme/LEAD "$1" 2>/dev/null)" "$2" | cut -f2`, [rd2, ago(5)]).stdout;
  assert.doesNotMatch(news, /your section/, news);
  assert.match(news, /message from w\/OTHER\/acme .*peer note/, news);

  // another seat recording on LEAD's desk is news to LEAD: the actor is the recorder, not LEAD
  const other = cm(3, `${P}ANSWER n=2 c\n(words typed to acme/LEAD's session, verbatim)\n\n${P}ACK seat=acme/OTHER at=${ago(1)} state=seen next=recorded`, ago(0));
  assert.deepEqual(w.sh(`event_actors UPDATED 1 "$1" acme/LEAD`, [JSON.stringify([other])]).stdout.split("\n").filter(Boolean), ["acme/OTHER"]);
});

test("desk.sh answer refuses without --by, naming it", () => {
  const w = world("desk-noby", { [`${REPO}#3`]: issue(3, "Desk: acme/LEAD", ["desk", "seat:acme/LEAD"]) }, { [`${REPO}#3`]: [cm(3, `${P}ASK n=1 seat=acme/LEAD at=${ago(60)}\nQ?`, ago(60))] });
  const r = w.run("desk.sh", ["answer", "LEAD", "1", "b"]);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /answer needs --by <SEAT>, the recording seat/);
  assert.equal(w.gh.log().filter((l) => l.startsWith("WRITE")).length, 0);
});

test("the inline rule is stated before composing: desk.sh --help, the ask usage, decision.sh --help and its usage", () => {
  const w = world("help");
  const rule = /the content inline, or a URL to a file or diff at a commit .*never a session .* or a local path/;
  for (const [s, a] of [["desk.sh", ["--help"]], ["decision.sh", ["--help"]]]) { const r = w.run(s, a); assert.equal(r.status, 0, r.stderr); assert.match(r.stdout, rule, s); }
  for (const [s, a] of [["desk.sh", ["ask"]], ["decision.sh", []]]) { const r = w.run(s, a); assert.notEqual(r.status, 0); assert.match(r.stderr, rule, `${s} ${a.join(" ")}`); }
});

// ---- (9) issue.sh new: the duplicate check in the same act as the create ---------------------------------------------
test("gate 9: issue.sh new refuses a duplicate title naming it, files it with --force, and files a distinct title", () => {
  const w = world("issue", {
    [`${REPO}#5`]: issue(5, "Powch PWA logs three '[DeSciX SDK] DeSciX.view|chat|powch is unavailable: no readable App Shell bus' console errors on every load inside the shell (cross-origin by design)", []),
    [`${REPO}#6`]: issue(6, "app init writes an absolute workspaceRoot into .descix/workspace.json, which public repos commit; the loader never reads it", []),
    [`${REPO}#7`]: issue(7, "Closed: Board publish fails", [], { state: "closed" }) });
  const bf = join(W, "issue-body.md"); writeFileSync(bf, "Measured: the bundle logs the line three times on every shell load.\n");
  const created = () => Object.values(w.gh.state().issues).filter((i) => i.number > 7).map((i) => i.title);

  const dup = "Powch site bundle logs '[DeSciX SDK] DeSciX.view/chat/powch is unavailable: no readable DeSciX App Shell bus' three times on every shell load";
  const r1 = w.run("issue.sh", ["new", "--repo", REPO, "--title", dup, "--body-file", bf]);
  assert.notEqual(r1.status, 0, r1.stdout);
  assert.match(r1.stderr, /#5 \(\d+ shared words, overlap 0\.\d\d\): Powch PWA logs three/, r1.stderr);
  assert.match(r1.stderr, /refused: 1 open issue\(s\) in acme\/twin match the title/);
  assert.deepEqual(created(), [], "nothing filed");

  const r2 = w.run("issue.sh", ["new", "--repo", REPO, "--title", "CLI: workspace.json stores an absolute workspaceRoot, so a committed app-lane workspace carries one machine's path into public repos", "--body-file", bf]);
  assert.notEqual(r2.status, 0, r2.stdout);
  assert.match(r2.stderr, /#6 \(\d+ shared words/, r2.stderr);

  const r3 = w.run("issue.sh", ["new", "--repo", REPO, "--title", "APP INIT writes an absolute workspaceRoot into .descix/workspace.json — which public repos commit; the loader never reads it!", "--body-file", bf]);
  assert.notEqual(r3.status, 0);
  assert.match(r3.stderr, /#6 \(same title\)/, r3.stderr);

  const r4 = w.run("issue.sh", ["new", "--repo", REPO, "--title", dup, "--body-file", bf, "--force", "--label", "bug"]);
  assert.equal(r4.status, 0, r4.stderr);
  assert.match(r4.stdout, /^https:\/\/github.com\/acme\/twin\/issues\/8$/m);
  assert.deepEqual(created(), [dup]);

  const r5 = w.run("issue.sh", ["new", "--repo", REPO, "--title", "Board publish fails under a secondary rate limit", "--body-file", bf]);
  assert.equal(r5.status, 0, r5.stderr);
  assert.equal(created().length, 2, "a distinct title files (a closed issue of the same words is not a candidate)");

  const pub = w.run("issue.sh", ["new", "--repo", "acme/site", "--title", "Anything new", "--body-file", bf]);
  assert.notEqual(pub.status, 0); assert.match(pub.stderr, /refused: acme\/site is public/);
  const lp = join(W, "issue-local.md"); writeFileSync(lp, "see " + LOCAL + "/x.log\n");   // a local path, assembled so no line of this file is one
  const loc = w.run("issue.sh", ["new", "--repo", REPO, "--title", "Another thing", "--body-file", lp]);
  assert.notEqual(loc.status, 0); assert.match(loc.stderr, /points elsewhere for its substance \("\/\w+\/someone"\)/);
  const lab = w.run("issue.sh", ["new", "--repo", REPO, "--title", "A third thing", "--body-file", bf, "--label", "decision"]);
  assert.notEqual(lab.status, 0); assert.match(lab.stderr, /'decision' is a coordination label/);
  assert.equal(created().length, 2, "the refusals filed nothing");
});

// ---- a tick whose agent memory cannot be read: loud in the log, and the tick still finishes ----------------------------
// The fixture has no Beast workstream tracking issue, so notes_read (the agent's MEMORY) fails. A tick that hands the
// agent a signal names the failing step and its error in the watchdog log, still builds the prompt with the signal, and
// ends with its tick line; the non-dry tick also runs the agent (a stub claude) and logs the notes write it could not make.
test("watchdog: a tick that hands a signal while the Beast tracking issue is missing logs the failing step and finishes", () => {
  const desk = issue(3, "Desk: acme/LEAD", ["desk", "seat:acme/LEAD"], { comments: 2, updated_at: ago(3600) });
  const w = world("notracking", { [`${REPO}#3`]: desk }, { [`${REPO}#3`]: [
    cm(3, `${P}ASK n=1 seat=acme/LEAD at=${ago(3600)}\nWhich name?\noptions: a | b`, ago(3600)),
    cm(3, `${P}ACK seat=acme/LEAD at=${ago(3590)} state=seen next=asked n=1`, ago(3590))] });
  assert.equal(w.run("watch.sh", ["LEAD", "--once"]).status, 0);
  w.edit((s) => { s.comments[`${REPO}#3`].push(cm(3, `${P}ANSWER n=1 b`, ago(0))); s.issues[`${REPO}#3`].comments += 1; s.issues[`${REPO}#3`].updated_at = ago(0); });
  assert.equal(w.run("watch.sh", ["LEAD", "--once"]).status, 0);
  const sessions = join(w.home, ".claude", "sessions"); mkdirSync(sessions, { recursive: true });
  writeFileSync(join(sessions, `${process.pid}.json`), JSON.stringify({ pid: process.pid, sessionId: "s-lead", cwd: w.H, name: "lead-1", status: "idle" }));
  writeFileSync(join(w.home, ".beast", "sessions.json"), JSON.stringify({ "w/LEAD/acme": { session: "s-lead", session_at: ago(60), launch: w.H, tracking: `${REPO}#9` } }));
  mkdirSync(join(w.home, ".beast", "watchdog"), { recursive: true });
  writeFileSync(join(w.home, ".beast", "watchdog", "state.json"), JSON.stringify({ tune: { "unacked.grace": 0 } }));
  const logf = join(w.home, ".beast", "watchdog.log");
  const t = w.run("watchdog.sh", ["--repo", w.H, "--dry-run"]);
  const log = readFileSync(logf, "utf8");
  assert.match(t.stdout, /SIGNAL 1 check=unacked seat=w\/LEAD\/acme/, `the signal still reaches the prompt\n${t.stdout}\n${t.stderr}\n${log}`);
  assert.match(log, /FAILED memory: notes_read .*no open issue labelled workstream and ws:beast/, log);
  assert.match(t.stdout, /MEMORY .*\n {2}\| \(not read: /, t.stdout);
  assert.match(log, /tick: dry run: 1 signal\(s\), no agent/, log);
  assert.equal(t.status, 0, `${t.stdout}\n${t.stderr}`);

  // the real tick: the agent (a stub claude that replies one line) runs, and the notes it cannot write are named
  const bin = join(w.home, "bin"); mkdirSync(bin, { recursive: true });
  writeFileSync(join(bin, "claude"), "#!/bin/sh\necho '1 unacked x nudged sent'\n", { mode: 0o755 });
  writeFileSync(join(w.home, ".beast", "watchdog", "state.json"), JSON.stringify({ tune: { "unacked.grace": 0 } }));
  const t2 = w.run("watchdog.sh", ["--repo", w.H], { PATH: `${bin}:${w.gh.bin}:${process.env.PATH}` });
  const log2 = readFileSync(logf, "utf8").slice(log.length);
  assert.match(log2, /FAILED memory: notes_read .*no open issue labelled workstream and ws:beast/, log2);
  assert.match(log2, /agent \(haiku, default\): 1 signal\(s\)/, log2);
  assert.match(log2, /notes: not written: .*no open issue labelled workstream and ws:beast/, log2);
  assert.match(log2, /tick: 1 signal\(s\) to the agent/, log2);
  assert.equal(t2.status, 0, `${t2.stdout}\n${t2.stderr}\n${log2}`);

  // any other death mid-tick is named too: a copy of the scripts whose step 5 fails outright logs the step, the command
  // and the exit status, and exits non-zero
  const broken = join(w.home, "scripts"); cpSync(SCRIPTS, broken, { recursive: true });
  const wd = join(broken, "watchdog.sh");
  writeFileSync(wd, readFileSync(wd, "utf8").replace('tick_step="5 logs"\n', 'tick_step="5 logs"\nfalse\n'));
  const before = readFileSync(logf, "utf8").length;
  const t3 = spawnSync(wd, ["--repo", w.H, "--dry-run"], { cwd: w.H, encoding: "utf8", env: { ...process.env, PATH: `${w.gh.bin}:${process.env.PATH}`, HOME: w.home, BEAST_WS_CACHE: "", CLAUDE_PLUGIN_ROOT: join(broken, "..") } });
  const log3 = readFileSync(logf, "utf8").slice(before);
  assert.notEqual(t3.status, 0);
  assert.match(log3, /tick: DIED \(exit 1\) in step "5 logs" at line \d+: false; the checks after it did not run/, log3);
});
