// The decide adoption, end to end against a stub gh (gh-stub.mjs) and the board page in node, with no network:
//   (1) a program's sub-act may carry " when: <condition>": close --covered of its follow-on is refused without
//       --condition-met and writes the evidence into the close line with it; --condition-met is refused on a sub-act
//       without a condition and on a close on the words; board.sh and the page show the condition and the evidence;
//   (2) the optional sections `## Stops if` and `## Undo` (new, record and revise; flags or --body-file), placed right
//       before `## Approve with`, refused when malformed, shown in board.sh's Recommendation cell and on the page;
//   (3) a hands row's `Run sheet:` line (new|revise --run-sheet): refused without hands and on a non-https link;
//   (4) census.sh: reviewed vs served per roster target, clean / unshipped lines, exit 1 naming an unreadable target or
//       a malformed roster field.
// Each refusal is measured failing (and writing nothing) beside the accepted case.
//   node --test plugin/tests/
// BEAST_TEST_SCRIPTS / BEAST_TEST_PAGE point the test at another tree; BEAST_TEST_TMP is where the fixtures are written.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { ghStub } from "./gh-stub.mjs";
import { pageFns } from "./page-harness.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPTS = process.env.BEAST_TEST_SCRIPTS || join(here, "..", "scripts");
const PAGE = process.env.BEAST_TEST_PAGE || join(here, "..", "templates", "board.html");
const W = mkdtempSync(join(process.env.BEAST_TEST_TMP || tmpdir(), "beast-decide-"));
const REPO = "acme/twin";
const T0 = "2026-10-22T10:00:00Z";
const nowZ = () => new Date().toISOString().replace(/\.\d+Z$/, "Z");

function world(name, seatExtra = {}) {
  const H = join(W, name), D = join(W, name + "-gh");
  mkdirSync(join(H, ".beast"), { recursive: true });
  execFileSync("git", ["-C", H, "init", "-q", "-b", "main"]);
  execFileSync("git", ["-C", H, "remote", "add", "origin", `https://github.com/${REPO}.git`]);
  const roster = (extra) => writeFileSync(join(H, ".beast", "roster.json"), JSON.stringify({ repo: REPO, board: REPO, people: [{ github: "alice", name: "Alice", role: "owner" }],
    seats: ["DEVPLANE", "BUILDER"].map((label) => ({ label, github: "alice", repo: REPO, agent: "daita-beast:seat", workstream: "platform", ...(label === "DEVPLANE" ? extra : {}) })) }));
  roster(seatExtra);
  const gh = ghStub(D, { login: "alice", clock: T0, repos: { [REPO]: { private: true } }, issues: {}, comments: {}, milestones: {} });
  const home = join(W, name + "-home"); mkdirSync(home, { recursive: true });
  const env = { ...process.env, PATH: `${gh.bin}:${process.env.PATH}`, HOME: home, BEAST_CACHE_DIR: join(W, name + "-cache"), BEAST_WS_CACHE: "" };
  const run = (script, args) => spawnSync(join(SCRIPTS, script), args, { cwd: H, encoding: "utf8", env });
  const sh = (code, args = []) => spawnSync("bash", ["-c", `source '${join(SCRIPTS, "lib.sh")}'; ${code}`, "sh", ...args], { cwd: H, encoding: "utf8", env });
  const edit = (f) => { const s = gh.state(); f(s); writeFileSync(join(D, "state.json"), JSON.stringify(s)); };
  let cid = 500;
  const say = (n, body, at) => { const id = ++cid; edit((s) => { (s.comments[`${REPO}#${n}`] = s.comments[`${REPO}#${n}`] || []).push({ id, body, user: { login: "alice" }, created_at: at, html_url: `https://github.com/${REPO}/issues/${n}#issuecomment-${id}` }); }); return `https://github.com/${REPO}/issues/${n}#issuecomment-${id}`; };
  const SECTIONS = (title) => ["--decision", `do ${title}`, "--unblocks", "the E2E", "--waits", "the CEO's word", "--recommendation", "approve", "--approve-with", "go", "--record", "the answer comment"];
  const file = (title, extra = [], sections = true) => {
    const r = run("decision.sh", ["new", "--title", title, "--assignee", "alice", "--by", "DEVPLANE", ...(sections ? SECTIONS(title) : []), ...extra]);
    return { ...r, n: r.status === 0 ? Number(r.stdout.trim().split("\n").pop().split("/").pop()) : null };
  };
  const git = (...a) => execFileSync("git", ["-C", H, "-c", "user.name=t", "-c", "user.email=t@example.org", ...a], { encoding: "utf8" }).trim();
  return { H, gh, run, sh, edit, say, file, git, roster };
}
const comments = (gh, n) => gh.state().comments[`${REPO}#${n}`] || [];
const issue = (gh, n) => gh.state().issues[`${REPO}#${n}`];
const writes = (gh) => gh.log().filter((l) => l.startsWith("WRITE ") && !l.startsWith("WRITE POST graphql "));
const refused = (r, re, what) => { assert.notEqual(r.status, 0, `${what}: exited 0\n${r.stdout}`); assert.match(r.stderr, re, `${what}: ${r.stderr}`); };
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\#]/g, "\\$&");

// ---- (1) conditions on sub-acts ----
const COND = "npm test green on the exact commit";
test("(1) a sub-act with a condition: close --covered is refused without --condition-met and writes the evidence with it", () => {
  const { gh, run, sh, edit, say, file } = world("cond");
  let w = writes(gh).length;
  refused(file("bad program", ["--sub", "build: merge when:"]), /its act carries 'when:' that is not ' when: <condition>'/, "a dangling when:");
  assert.equal(writes(gh).length, w, "nothing written");
  const prog = file("decide program", ["--sub", `build: merge the PR when: ${COND}`, "--sub", "publish: publish it"]);
  assert.equal(prog.status, 0, prog.stderr);
  assert.match(issue(gh, prog.n).body, new RegExp(`## Sub-acts\\n- build: merge the PR when: ${esc(COND)}\\n- publish: publish it\\n`));
  const approval = say(prog.n, "go", "2026-10-22T11:00:00Z");
  const fol = (slug) => file(`decide ${slug}`, ["--follows", `${REPO}#${prog.n}`, "--sub-act", slug]);
  const fb = fol("build");
  assert.equal(fb.status, 0, fb.stderr);
  assert.match(fb.stderr, new RegExp(`--condition-met "<evidence that: ${esc(COND)}>"`), "the filing names the condition to meet");
  const fp = fol("publish");
  assert.equal(fp.status, 0, fp.stderr);
  assert.doesNotMatch(fp.stderr, /--condition-met/);
  // The board names the condition on the program's Kind.
  const b = run("board.sh", ["--assignee", "alice"]);
  assert.equal(b.status, 0, b.stderr);
  assert.match(b.stdout, new RegExp(`\\| decision · program: build \\(when: ${esc(COND)}\\), publish \\| \\[${REPO}#${prog.n}\\]`), b.stdout);
  // Negative controls: no evidence, empty evidence, evidence on a sub-act without a condition, evidence on a words close.
  w = writes(gh).length;
  refused(run("decision.sh", ["close", `${REPO}#${fb.n}`, "--covered", "--by", "DEVPLANE"]),
    new RegExp(`sub-act build of ${REPO}#${prog.n} carries the condition "${esc(COND)}": close --covered needs --condition-met`), "no evidence");
  refused(run("decision.sh", ["close", `${REPO}#${fb.n}`, "--covered", "--condition-met", "  ", "--by", "DEVPLANE"]), /--condition-met is empty/, "empty evidence");
  refused(run("decision.sh", ["close", `${REPO}#${fp.n}`, "--covered", "--condition-met", "x", "--by", "DEVPLANE"]), /carries no condition: --condition-met has nothing to meet/, "no condition");
  refused(run("decision.sh", ["close", `${REPO}#${fp.n}`, "--words", "go", "--record", "r", "--condition-met", "x", "--by", "DEVPLANE"]), /--condition-met belongs to close --covered/, "a words close");
  assert.equal(writes(gh).length, w, "nothing written by a refused close");
  assert.equal(issue(gh, fb.n).state, "open");
  // With the evidence: closed, the close line carries it, every reader reads it back.
  const EV = "npm test 131/131 at 0123abc; served == built";
  const c = run("decision.sh", ["close", `${REPO}#${fb.n}`, "--covered", "--condition-met", EV, "--by", "DEVPLANE"]);
  assert.equal(c.status, 0, c.stderr);
  assert.equal(issue(gh, fb.n).state, "closed");
  assert.equal(comments(gh, fb.n).at(-1).body.split("\n")[0], `Closed as covered by <${approval}> by alice/DEVPLANE; condition met: ${EV}`);
  const k = sh(`close_of_comments "$1" | jq -r '.kind + "|" + .record + "|" + .met'`, [JSON.stringify(comments(gh, fb.n))]);
  assert.equal(k.stdout.trim(), `covered|${approval}|${EV}`, k.stderr);
  // A sub-act without a condition still closes covered as before, with no evidence.
  const c2 = run("decision.sh", ["close", `${REPO}#${fp.n}`, "--covered", "--by", "DEVPLANE"]);
  assert.equal(c2.status, 0, c2.stderr);
  assert.equal(comments(gh, fp.n).at(-1).body.split("\n")[0], `Closed as covered by <${approval}> by alice/DEVPLANE`);
  // The decided table shows the evidence (the closes moved into the wall clock's 7-day window).
  edit((s) => { for (const n of [fb.n, fp.n]) s.issues[`${REPO}#${n}`].closed_at = nowZ(); });
  const d = run("board.sh", ["--assignee", "alice"]);
  assert.equal(d.status, 0, d.stderr);
  assert.match(d.stdout, new RegExp(`no words: covered by the program approval ${esc(approval)}, closed by alice/DEVPLANE; condition met: ${esc(EV)} \\|`), d.stdout);
});

test("(1) page: a sub-act's condition and a covered close's evidence are read and shown", () => {
  const f = pageFns(PAGE, ["subActsOf", "closeOf", "ms"], ["SUBACT_RE", "CLOSE_RE"]);
  const body = `## Decision\nd\n\n## Sub-acts\n- build: merge when: ${COND}\n- publish: publish it\n- bad: x when:\n\n## Unblocks\nu\n`;
  assert.deepEqual(JSON.parse(JSON.stringify(f.subActsOf(body))), [{ slug: "build", act: "merge", when: COND }, { slug: "publish", act: "publish it", when: null }]);
  const url = `https://github.com/${REPO}/issues/74#issuecomment-501`;
  const c = f.closeOf([{ body: `Closed as covered by <${url}> by alice/DEVPLANE; condition met: tests green\n\nClosed by seat alice/DEVPLANE at 2026-10-22T12:00:00Z.`, created_at: "2026-10-22T12:00:00Z", html_url: "x" }]);
  assert.deepEqual(JSON.parse(JSON.stringify(c)), { kind: "covered", record: url, seat: "alice/DEVPLANE", met: "tests green", url: "x" });
  const src = readFileSync(PAGE, "utf8");
  assert.match(src, /x\.when \? " — when: " \+ x\.when : ""/, "the card shows the condition beside the act");
  assert.match(src, /w\.met \? "Condition met: " \+ w\.met/, "the decided card shows the evidence");
});

// ---- (2) Stops if and Undo ----
test("(2) --stops-if and --undo write the optional sections before ## Approve with; board.sh shows them; malformed is refused", () => {
  const { gh, run, sh, say, file } = world("optional");
  const r = file("deploy the site", ["--stops-if", "the suite is red", "--stops-if", "served != built after the deploy", "--undo", "redeploy the previous image (named on the deploy row)"]);
  assert.equal(r.status, 0, r.stderr);
  const body = issue(gh, r.n).body;
  assert.match(body, /## Recommendation\napprove\n\n## Stops if\n- the suite is red\n- served != built after the deploy\n\n## Undo\nredeploy the previous image \(named on the deploy row\)\n\n## Approve with\n/, body);
  const b = run("board.sh", ["--assignee", "alice"]);
  assert.equal(b.status, 0, b.stderr);
  assert.match(b.stdout, /\| approve — Stops if: the suite is red; served != built after the deploy — Undo: redeploy the previous image \(named on the deploy row\) \|/, b.stdout);
  // Refusals, nothing written.
  const bf = join(W, "optional-body.md");
  const BODY = (extra) => `## Decision\nd\n\n## Unblocks\nu\n\n## Waits\nw\n\n## Recommendation\nr\n${extra}\n## Approve with\n"go"\n\n## Record\nrec\n`;
  const w = writes(gh).length;
  writeFileSync(bf, BODY("\n## Stops if\nthe suite is red\n"));
  refused(file("bad stops", ["--body-file", bf], false), /a '## Stops if' line that is not '- <condition>': the suite is red/, "a Stops if line without '- '");
  writeFileSync(bf, BODY("\n## Undo\n\n"));
  refused(file("empty undo", ["--body-file", bf], false), /no non-empty '## Undo' section/, "an empty Undo");
  writeFileSync(bf, BODY("\n## Stops if\n- a\n"));
  refused(file("both", ["--body-file", bf, "--stops-if", "b"], false), /already has '## Stops if': pass the conditions in the body or with --stops-if, not both/, "body and flag");
  refused(file("blank undo", ["--undo", "   "]), /--undo is empty/, "a blank --undo");
  refused(file("two-line stop", ["--stops-if", "a\nb"]), /--stops-if 'a\nb' is not one line/, "a two-line --stops-if");
  assert.equal(writes(gh).length, w, "nothing written");
  // The --body-file form.
  writeFileSync(bf, BODY("\n## Stops if\n- the publish scrub is not clean\n\n## Undo\nrevert the squash commit on public main\n"));
  const r2 = file("publish via body", ["--body-file", bf], false);
  assert.equal(r2.status, 0, r2.stderr);
  assert.match(issue(gh, r2.n).body, /## Undo\nrevert the squash commit on public main\n/);
  // revise: a seat adds Stops if to its unanswered row (placed before the existing Undo), and replaces Undo.
  const rv = run("decision.sh", ["revise", `${REPO}#${r.n}`, "--by", "DEVPLANE", "--undo", "roll back to the previous revision", "--stops-if", "the canary errors"]);
  assert.equal(rv.status, 0, rv.stderr);
  assert.match(issue(gh, r.n).body, /## Recommendation\napprove\n\n## Stops if\n- the canary errors\n\n## Undo\nroll back to the previous revision\n\n## Approve with\n/, issue(gh, r.n).body);
  assert.match(comments(gh, r.n).at(-1).body.split("\n")[0], /; changed: Stops if, Undo$/);
  const r3 = file("plain row");
  const rv2 = run("decision.sh", ["revise", `${REPO}#${r3.n}`, "--by", "DEVPLANE", "--undo", "nothing to undo: a read-only act"]);
  assert.equal(rv2.status, 0, rv2.stderr);
  assert.match(issue(gh, r3.n).body, /## Recommendation\napprove\n\n## Undo\nnothing to undo: a read-only act\n\n## Approve with\n/, issue(gh, r3.n).body);
  // record carries them too.
  const rec = run("decision.sh", ["record", "--title", "recorded deploy", "--assignee", "alice", "--by", "DEVPLANE", "--decision", "d", "--unblocks", "u", "--waits", "w", "--recommendation", "r",
    "--approve-with", "go", "--stops-if", "the suite is red", "--undo", "redeploy", "--words", "go", "--record", "https://github.com/acme/twin/issues/1#issuecomment-1"]);
  assert.equal(rec.status, 0, rec.stderr);
  const recBody = Object.values(gh.state().issues).find((i) => i.title === "Decision: recorded deploy").body;
  assert.match(recBody, /## Stops if\n- the suite is red\n\n## Undo\nredeploy\n\n## Approve with\n/);
  // sh-level: a section heading twice is refused.
  const dup = sh(`row_optional_check t "$1"`, [BODY("\n## Undo\na\n\n## Undo\nb\n")]);
  refused(dup, /'## Undo' appears 2 times/, "Undo twice");
  void say;
});

test("(2) page: Stops if and Undo are parsed beside the six sections; their absence is not malformed", () => {
  const f = pageFns(PAGE, ["parseItem", "parseBody", "subActsOf", "followsOf", "runSheetOf", "isPR"], ["SECTIONS", "PR_SECTIONS", "OPTIONAL_SECTIONS", "SUBACT_RE", "FOLLOWS_RE", "RUN_SHEET_RE"]);
  const B = "## Decision\nd\n\n## Unblocks\nu\n\n## Waits\nw\n\n## Recommendation\nr\n\n## Stops if\n- red suite\n\n## Undo\nrevert\n\n## Approve with\n\"go\"\n\n## Record\nrec\n";
  const it = (body) => ({ body, html_url: `https://github.com/${REPO}/issues/9` });
  const p = f.parseItem(it(B));
  assert.deepEqual([p.sec["Stops if"], p.sec.Undo, Array.from(p.missing)], ["- red suite", "revert", []]);
  const q = f.parseItem(it(B.replace("\n## Stops if\n- red suite\n\n## Undo\nrevert\n", "")));
  assert.deepEqual([q.sec["Stops if"], q.sec.Undo, Array.from(q.missing)], [undefined, undefined, []]);
  assert.match(readFileSync(PAGE, "utf8"), /\["Decision", "Sub-acts", "Unblocks", "Waits", "Recommendation"\]\.concat\(OPTIONAL_SECTIONS, \["Record"\]\)/, "the card lists them after the Recommendation");
});

// ---- (3) a hands row's run sheet ----
test("(3) --run-sheet links a run sheet on a hands row only, one https link, replaced by revise", () => {
  const { gh, run, file } = world("runsheet");
  const U1 = "https://claude.ai/artifact/0123-abcd", U2 = "https://claude.ai/artifact/4567-ef01";
  const w = writes(gh).length;
  refused(file("not hands", ["--run-sheet", U1]), /--run-sheet links the run sheet of a hands row: file it with --hands/, "no --hands");
  refused(file("http", ["--hands", "--run-sheet", "http://claude.ai/artifact/x"]), /--run-sheet 'http:\/\/claude.ai\/artifact\/x' is not one https link/, "http");
  assert.equal(writes(gh).length, w, "nothing written");
  const r = file("flip the repo public", ["--hands", "--run-sheet", U1]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(issue(gh, r.n).body, new RegExp(`## Decision\\ndo flip the repo public\\n\\nRun sheet: ${esc(U1)}\\n\\n## Unblocks\\n`), issue(gh, r.n).body);
  assert.ok(issue(gh, r.n).labels.some((l) => l.name === "hands"));
  const rv = run("decision.sh", ["revise", `${REPO}#${r.n}`, "--by", "DEVPLANE", "--run-sheet", U2]);
  assert.equal(rv.status, 0, rv.stderr);
  const body = issue(gh, r.n).body;
  assert.equal((body.match(/^Run sheet: /gm) || []).length, 1, body);
  assert.match(body, new RegExp(`Run sheet: ${esc(U2)}\\n`));
  const plain = file("plain");
  refused(run("decision.sh", ["revise", `${REPO}#${plain.n}`, "--by", "DEVPLANE", "--run-sheet", U1]), /this row is not labelled hands/, "revise on a non-hands row");
  const bf = join(W, "runsheet-body.md");
  writeFileSync(bf, `## Decision\nd\n\nRun sheet: ${U1}\n\n## Unblocks\nu\n\n## Waits\nw\n\n## Recommendation\nr\n\n## Approve with\n"go"\n\n## Record\nrec\n`);
  refused(file("body without hands", ["--body-file", bf], false), /a run sheet belongs to a hands row; file it with --hands/, "a body-file link without hands");
});

test("(3) page: a hands row's run sheet is read from its one Run sheet: line", () => {
  const f = pageFns(PAGE, ["runSheetOf"], ["RUN_SHEET_RE"]);
  assert.equal(f.runSheetOf("## Decision\nd\n\nRun sheet: https://claude.ai/artifact/0123\n"), "https://claude.ai/artifact/0123");
  assert.equal(f.runSheetOf("## Decision\nd\n\nRun sheet: https://a.example/1\nRun sheet: https://a.example/2\n"), null);
  assert.equal(f.runSheetOf("## Decision\nd\n\nRun sheet: http://a.example/1\n"), null);
});

// ---- (4) census ----
test("(4) census.sh compares reviewed and served per roster target: unshipped lines, then clean", () => {
  const { H, run, git, roster } = world("census");
  writeFileSync(join(H, "a.txt"), "1\n"); git("add", "a.txt"); git("commit", "-q", "-m", "one");
  const c1 = git("rev-parse", "HEAD");
  git("branch", "served", c1);
  writeFileSync(join(H, "a.txt"), "2\n"); git("commit", "-q", "-am", "two");
  const c2 = git("rev-parse", "HEAD");
  mkdirSync(join(H, "svc"), { recursive: true });
  roster({ census: [
    { name: "site", reviewed: { git: "main" }, served: { git: "served" } },
    { name: "api", reviewed: { git: "main" }, served: { cmd: "printf '  %s\\n' \"$(git rev-parse main)\"" } },
    { name: "svc", reviewed: { git: "main", dir: "svc" }, served: { git: "main" } },
  ] });
  const r = run("census.sh", ["DEVPLANE"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, `unshipped: site reviewed=${c2} served=${c1}\ncensus: 1 unshipped of 3 targets checked\n`);
  git("branch", "-f", "served", c2);
  const r2 = run("census.sh", ["DEVPLANE"]);
  assert.equal(r2.status, 0, r2.stderr);
  assert.equal(r2.stdout, "census: clean, 3 targets checked\n");
});

test("(4) census.sh fails loud: an unreadable target, a malformed roster field, no targets; never a clean line", () => {
  const { H, run, git, roster } = world("census-bad");
  writeFileSync(join(H, "a.txt"), "1\n"); git("add", "a.txt"); git("commit", "-q", "-m", "one");
  const ok = { name: "site", reviewed: { git: "main" }, served: { git: "main" } };
  const cases = [
    [[ok, { name: "api", reviewed: { git: "main" }, served: { cmd: "echo deployed" } }], /census: api served: read 'deployed', not one 40-hex sha/],
    [[ok, { name: "api", reviewed: { git: "main" }, served: { cmd: "git rev-parse --short main" } }], /census: api served: read '[0-9a-f]{7,}', not one 40-hex sha/],
    [[ok, { name: "api", reviewed: { git: "main" }, served: { cmd: "git rev-parse main; git rev-parse main" } }], /census: api served: read '[0-9a-f]{40} [0-9a-f]+', not one 40-hex sha/],
    [[ok, { name: "api", reviewed: { git: "main" }, served: { cmd: "exit 3" } }], /census: api served: the command "exit 3" exited non-zero/],
    [[ok, { name: "api", reviewed: { git: "nope" }, served: { git: "main" } }], /census: api reviewed: the ref 'nope' names no commit/],
    [[ok, { name: "api", reviewed: { git: "main", dir: "missing" }, served: { git: "main" } }], /census: api reviewed: no directory .*\/missing/],
  ];
  for (const [census, re] of cases) {
    roster({ census });
    const r = run("census.sh", ["DEVPLANE"]);
    refused(r, re, JSON.stringify(census[1]));
    assert.match(r.stderr, /census: cannot read 1 of 2 target\(s\): api/);
    assert.doesNotMatch(r.stdout, /^census:/m, "no summary line when a target is unread");
  }
  const malformed = [
    [[ok, ok], /census lists the target site twice/],
    [[{ ...ok, reviewed: { git: "main", cmd: "x" } }], /census \[0\]\.reviewed has keys \['cmd', 'git'\]: a reader is/],
    [[{ ...ok, extra: 1 }], /census \[0\] is \{"name", "reviewed", "served"\} exactly/],
    [[{ ...ok, name: "Site" }], /census \[0\]\.name is a slug/],
    [[{ ...ok, served: { git: "main", dir: "../x" } }], /census \[0\]\.served\.dir is a plain path/],
    [[], /census is a non-empty list/],
  ];
  for (const [census, re] of malformed) { roster({ census }); refused(run("census.sh", ["DEVPLANE"]), re, JSON.stringify(census)); }
  roster({});
  refused(run("census.sh", ["DEVPLANE"]), /census: alice\/DEVPLANE lists no targets: add "census"/, "no census field");
  roster({ census: [ok] });
  const good = run("census.sh", ["DEVPLANE"]);
  assert.equal(good.status, 0, good.stderr);
  assert.equal(good.stdout, "census: clean, 1 targets checked\n");
});
