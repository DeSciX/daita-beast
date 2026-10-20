// The decider's turn and the PR rows, on both surfaces, with no network:
//   - the answer forms: lib.sh answer_kind and row_answer_url (the owners) and the page's answerKind and standingOf (the
//     twins) run on one table of comments and must agree; a comment in no answer form is no answer, whoever wrote it;
//   - the page (plugin/templates/board.html) run in node against a stubbed connector (page-harness.mjs): a row stays in
//     "Your turn" until an answer form, a revise shows its gap, a PR labelled needs-review is listed with its sections;
//   - pr.sh request and board.sh against a stub gh (gh-stub.mjs): the PR's Unblocks and Recommendation are required
//     before any write, written into its body, and shown on the generated board's row.
//   node --test plugin/tests/
// BEAST_TEST_SCRIPTS / BEAST_TEST_PAGE point the test at another tree (a gate's negative control); BEAST_TEST_TMP is
// where the fixtures are written (default: the OS temp dir).
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadPage, pageFns } from "./page-harness.mjs";
import { ghStub } from "./gh-stub.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPTS = process.env.BEAST_TEST_SCRIPTS || join(here, "..", "scripts");
const LIB = join(SCRIPTS, "lib.sh");
const PAGE = process.env.BEAST_TEST_PAGE || join(here, "..", "templates", "board.html");
const W = mkdtempSync(join(process.env.BEAST_TEST_TMP || tmpdir(), "beast-board-"));

// The protocol prefix is assembled, so no line of this file is itself a filled-in coordination line.
const P = "BEAST" + "-";
const REPO = "acme/twin";
const ack = (at, next = "x") => `${P}ACK seat=alice/DEVX at=${at} state=seen next=${next}`;
// The two plain comments the reviewing seat posted on a needs-review PR (#65 of the plugin's twin), untagged, as the
// decider's login.
const PLAIN = ["accurate — BEAST at ff32208 (base 81c73e5, plugin 1.5.10). Item 1 is verified.", "accurate — BEAST at bc80987. I verified the one-commit delta."];

function sh(cmd, args = []) {
  const r = spawnSync("bash", ["-c", `source '${LIB}'; ${cmd}`, "x", ...args], { encoding: "utf8", cwd: W });
  return { out: r.stdout.replace(/\n$/, ""), err: r.stderr, status: r.status };
}

// ---- the answer forms: one table, both readers ----
const PHRASE = "ship the guides";
const FORMS = [
  [PHRASE, PHRASE, "approve"],
  [`${PHRASE} — fix the typo first`, PHRASE, "approve"],
  [`${PHRASE}   `, PHRASE, "approve"],
  [`${PHRASE}\n\nthanks`, PHRASE, "approve"],
  ["approve", PHRASE, "approve"],
  ["approved", PHRASE, "approve"],
  ["Approve", PHRASE, "approve"],
  ["approve\r\nlooks right", PHRASE, "approve"],
  ["revise: name the second login", PHRASE, "revise"],
  ["reject: out of scope", PHRASE, "reject"],
  ["approve", "", "approve"],
  ["revise: x", "", "revise"],
  [PLAIN[0], "approve", null],
  [PLAIN[1], "approve", null],
  ["DEVX: ready for re-review. Head a61face.", "approve", null],
  [`${PHRASE}, but later`, PHRASE, null],
  [`${PHRASE}—no spaces`, PHRASE, null],
  ["APPROVE", PHRASE, null],
  ["approve this one", PHRASE, null],
  ["  approve", PHRASE, null],
  ["I approve", PHRASE, null],
  ["revise:", PHRASE, null],
  ["reject:\nthe reason on line two", PHRASE, null],
  ["revise:   \nchange it", PHRASE, null],
  ["\napprove", PHRASE, null],
  ["", "", null],
  ["\nsome reply", "", null],
  [" — a comment", "", null],
  [ack("2026-10-20T20:00:00Z"), PHRASE, null],
];

test("answer forms: lib.sh answer_kind and the page's answerKind read every comment of the table alike, as the table says", () => {
  const { answerKind } = pageFns(PAGE, ["answerKind"]);
  const diffs = [];
  for (const [body, phrase, want] of FORMS) {
    const lib = sh('answer_kind "$1" "$2"', [body, phrase]).out || null;
    const page = answerKind(body, phrase || null);
    if (lib !== want || page !== want) diffs.push(`  ${JSON.stringify(body)} (phrase ${JSON.stringify(phrase)}): want ${want}, lib.sh ${lib}, page ${page}`);
  }
  assert.equal(diffs.length, 0, `${diffs.length} comment(s) read wrong:\n${diffs.join("\n")}`);
});

// ---- the standing answer: row_answer_url (lib.sh) and standingOf (the page) on one set of threads ----
let cn = 0;
const cm = (body, at, login = "alice") => ({ body, user: { login }, created_at: at, html_url: `https://github.com/${REPO}/issues/1#issuecomment-${++cn}` });
const THREADS = {
  "plain comments only": [cm(ack("2026-10-20T19:35:38Z"), "2026-10-20T19:35:38Z"), cm(PLAIN[0], "2026-10-20T20:16:07Z"), cm(PLAIN[1], "2026-10-20T20:33:40Z")],
  "approve then plain": [cm("approve", "2026-10-20T19:00:00Z"), cm(PLAIN[0], "2026-10-20T20:16:07Z")],
  "approve then revise": [cm("approve", "2026-10-20T19:00:00Z"), cm("revise: more", "2026-10-20T19:10:00Z"), cm(PLAIN[1], "2026-10-20T19:20:00Z")],
  "revise then amend then approve": [cm("revise: more", "2026-10-20T19:00:00Z"), cm("Amended at 2026-10-20T19:05:00Z: revised", "2026-10-20T19:05:00Z"), cm(`${PHRASE} — ok`, "2026-10-20T19:10:00Z")],
  "approve before the amend": [cm(PHRASE, "2026-10-20T19:00:00Z"), cm("Amended at 2026-10-20T19:05:00Z: rebuilt", "2026-10-20T19:05:00Z")],
  "reject": [cm(PLAIN[0], "2026-10-20T19:00:00Z"), cm("reject: no", "2026-10-20T19:10:00Z")],
  "someone else's approve": [cm("approve", "2026-10-20T19:00:00Z", "mallory")],
};

test("the standing answer: lib.sh row_answer_url and the page's standingOf agree on every thread; plain comments are no answer", () => {
  const { standingOf } = pageFns(PAGE, ["answerKind", "standingOf", "ackLine", "ms"], ["AMEND_RE", "ACK_RE", "CLOSER_RE"]);
  const diffs = [];
  for (const [name, comments] of Object.entries(THREADS)) {
    const row = JSON.stringify({ issue: { assignees: [{ login: "alice" }], number: 1, repository_url: `https://api.github.com/repos/${REPO}` }, comments });
    let lib = null;
    for (const k of ["approve", "revise", "reject"]) { const u = sh('row_answer_url "$1" "$2" "$3" 2>/dev/null', [row, PHRASE, k]).out; if (u) lib = `${k} ${u}`; }
    const w = standingOf(comments, PHRASE, "alice");
    const page = w.answer ? `${w.kind} ${w.answer.html_url}` : null;
    if (lib !== page) diffs.push(`  ${name}: lib.sh ${lib}, page ${page}`);
  }
  assert.equal(diffs.length, 0, diffs.join("\n"));
  assert.equal(standingOf(THREADS["plain comments only"], "approve", "alice").answer, null, "a plain comment is never the standing answer");
});

test("the section lists: the page's SECTIONS and PR_SECTIONS equal lib.sh ROW_SECTIONS and PR_ROW_SECTIONS", () => {
  const src = readFileSync(PAGE, "utf8");
  const arr = (name) => { const m = new RegExp(`var ${name} = (\\[[^\\]]*\\]);`).exec(src); assert.ok(m, `${PAGE} has no var ${name} = [...]`); return JSON.parse(m[1]); };
  const lib = (name) => sh(`printf '%s\\n' "\${${name}[@]}"`).out.split("\n");
  assert.deepEqual(arr("SECTIONS"), lib("ROW_SECTIONS"));
  assert.deepEqual(arr("PR_SECTIONS"), lib("PR_ROW_SECTIONS"));
});

// ---- the page against a stubbed connector ----
const DBODY = `## Decision\nd\n\n## Unblocks\nu\n\n## Waits\nw\n\n## Recommendation\nr\n\n## Approve with\n"${PHRASE}"\n\n## Record\nrec\n`;
const PR_SECTIONED = "## What\nTwo guides.\n\n## Unblocks\nthe DEVX docs release 1.5.10\n\n## Recommendation\nmerge: every citation re-read at ff32208\n";
const item = (n, pr, body, labels) => ({ number: n, title: pr ? `docs: guides ${n}` : `Decision: t${n}`, body, state: "open",
  html_url: `https://github.com/${REPO}/${pr ? "pull" : "issues"}/${n}`, labels: [...labels, "seat:alice/DEVX"], assignees: ["alice"],
  created_at: "2026-10-20T19:00:00Z", updated_at: "2026-10-20T20:40:00Z", repository_url: `https://api.github.com/repos/${REPO}`, comments: 3 });
const thread = (...bodies) => [cm(ack("2026-10-20T19:35:38Z"), "2026-10-20T19:35:38Z"), ...bodies.map((b, i) => cm(b, `2026-10-20T20:${String(10 + i).padStart(2, "0")}:00Z`))];
const statusOf = (cards, n) => cards.find((c) => c.key === `${REPO}#${n}`);

test("page: a needs-review PR whose only comments are plain untagged ones is listed in Your turn", async () => {
  const p = await loadPage(PAGE, { rows: [item(65, true, PR_SECTIONED, ["needs-review"])], comments: { 65: thread(...PLAIN) } });
  const c = statusOf(p.turnRows(), 65);
  assert.ok(c, `the PR is not in Your turn; Your turn: ${JSON.stringify(p.turnRows())}; with the seats: ${JSON.stringify(p.withSeats())}`);
  assert.equal(c.status, "Your turn");
});

test("page: a decision whose only comments are plain untagged ones stays in Your turn", async () => {
  const p = await loadPage(PAGE, { rows: [item(1, false, DBODY, ["decision"])], comments: { 1: thread(...PLAIN) } });
  assert.equal(statusOf(p.turnRows(), 1)?.status, "Your turn", JSON.stringify(p.withSeats()));
});

test("page: an approve answer takes the row out of Your turn (a decision and a PR)", async () => {
  const p = await loadPage(PAGE, { rows: [item(1, false, DBODY, ["decision"]), item(65, true, PR_SECTIONED, ["needs-review"])],
    comments: { 1: thread(PLAIN[0], `${PHRASE} — go`), 65: thread(PLAIN[0], "approve") } });
  assert.deepEqual(p.turnRows(), [], "nothing is in Your turn");
  for (const n of [1, 65]) assert.match(statusOf(p.withSeats(), n)?.status || "(absent)", /^Answered/, `#${n}`);
});

test("page: a revise shows the revise gap, and a plain reply after it does not end the gap", async () => {
  const p = await loadPage(PAGE, { rows: [item(1, false, DBODY, ["decision"])], comments: { 1: thread("revise: name the second login", PLAIN[0]) } });
  const c = statusOf(p.withSeats(), 1);
  assert.match(c?.status || "(absent)", /^Revision requested — waiting on/);
});

test("page: a PR row shows its Unblocks and Recommendation; a PR without them is malformed, with no answer buttons", async () => {
  const p = await loadPage(PAGE, { rows: [item(65, true, PR_SECTIONED, ["needs-review"]), item(66, true, "## What\nno sections", ["needs-review"])], comments: { 65: thread(), 66: thread() } });
  const ok = statusOf(p.turnRows(), 65), bad = statusOf(p.turnRows(), 66);
  assert.ok(ok && bad, `both PRs are listed: ${JSON.stringify(p.turnRows())}`);
  assert.match(ok.text, /Unblocksthe DEVX docs release 1\.5\.10/);
  assert.match(ok.text, /Recommendationmerge: every citation re-read at ff32208/);
  assert.match(bad.text, /malformed: Unblocks, Recommendation/);
  assert.doesNotMatch(bad.text, /Approve|Revise|Reject/, "a malformed PR offers no answer");
  assert.match(ok.text, /Approve.*Revise.*Reject/, "a well-formed PR offers the three answers");
  const tools = new Set(p.calls.map((c) => c.tool));
  assert.ok(tools.has("search_pull_requests") && tools.has("search_issues"), [...tools].join(","));
});

test("page: when the pull-request search is refused the list fails naming the tool, never showing the issues alone", async () => {
  const p = await loadPage(PAGE, { rows: [item(1, false, DBODY, ["decision"]), item(65, true, PR_SECTIONED, ["needs-review"])], comments: { 1: thread(), 65: thread() }, missing: ["search_pull_requests"] });
  assert.deepEqual(p.turnRows(), [], "no row is listed from half a search");
  assert.match(p.text("banner"), /search_pull_requests/, p.text("banner"));
});

// ---- pr.sh request and board.sh against a stub gh ----
function checkout(name) {
  const H = join(W, name);
  mkdirSync(join(H, ".beast"), { recursive: true });
  execFileSync("git", ["-C", H, "init", "-q"]);
  execFileSync("git", ["-C", H, "remote", "add", "origin", `https://github.com/${REPO}.git`]);
  writeFileSync(join(H, ".beast", "roster.json"), JSON.stringify({ repo: REPO, board: REPO, people: [{ github: "alice", name: "Alice", role: "owner" }],
    seats: [{ label: "DEVX", github: "alice", repo: REPO, agent: "daita-beast:seat", workstream: "platform" }] }));
  return H;
}
function ghWorld(name, prBody) {
  const H = checkout(name);
  const pr = { number: 65, title: "docs: guides", body: prBody, state: "open", html_url: `https://github.com/${REPO}/pull/65`, pull_request: { merged_at: null },
    labels: [], assignees: [], user: { login: "alice" }, created_at: "2026-10-20T19:00:00Z", updated_at: "2026-10-20T19:00:00Z", closed_at: null,
    repository_url: `https://api.github.com/repos/${REPO}`, milestone: null };
  const gh = ghStub(join(W, name + "-gh"), { login: "alice", repos: { [REPO]: { private: true } }, issues: { [`${REPO}#65`]: pr }, comments: {}, milestones: {} });
  const run = (script, args) => spawnSync(join(SCRIPTS, script), args, { cwd: H, encoding: "utf8",
    env: { ...process.env, PATH: `${gh.bin}:${process.env.PATH}`, HOME: W, BEAST_CACHE_DIR: join(W, name + "-cache"), BEAST_WS_CACHE: "" } });
  return { gh, run };
}
const writes = (gh) => gh.log().filter((l) => l.startsWith("WRITE "));

test("pr.sh request without --unblocks or --recommendation is refused before any write", () => {
  for (const [label, extra] of [["neither", []], ["no --recommendation", ["--unblocks", "the release"]], ["no --unblocks", ["--recommendation", "merge"]], ["an empty one", ["--unblocks", " ", "--recommendation", "merge"]]]) {
    const { gh, run } = ghWorld("refuse-" + label.replace(/\W+/g, "-"), "## What\nx\n");
    const r = run("pr.sh", ["request", `${REPO}#65`, "--seat", "DEVX", ...extra]);
    assert.notEqual(r.status, 0, `${label}: pr.sh request exited 0`);
    assert.match(r.stderr, /needs --(unblocks|recommendation)/, `${label}: ${r.stderr}`);
    assert.deepEqual(writes(gh), [], `${label}: wrote before refusing`);
  }
});

test("pr.sh request writes Unblocks and Recommendation into the PR body, and board.sh shows them on the PR row", () => {
  const { gh, run } = ghWorld("request", "## What\nTwo guides.\n\n## Evidence\nscan exit 0\n");
  const r = run("pr.sh", ["request", `${REPO}#65`, "--seat", "DEVX", "--unblocks", "the DEVX docs release 1.5.10", "--recommendation", "merge: every citation re-read"]);
  assert.equal(r.status, 0, r.stderr);
  const body = gh.state().issues[`${REPO}#65`].body;
  assert.match(body, /## Unblocks\nthe DEVX docs release 1\.5\.10\n/);
  assert.match(body, /## Recommendation\nmerge: every citation re-read\n/);
  assert.match(body, /^## What\nTwo guides\.\n\n## Evidence\nscan exit 0\n/, "the body the PR had is kept");
  const order = writes(gh).map((l) => l.split(" ").slice(1, 3).join(" "));
  assert.ok(order.findIndex((l) => /PATCH repos\/acme\/twin\/issues\/65$/.test(l)) < order.findIndex((l) => /issues\/65\/labels/.test(l)), `the body is written before the labels: ${order.join(" | ")}`);
  const b = run("board.sh", ["--assignee", "alice"]);
  assert.equal(b.status, 0, b.stderr);
  const row = b.stdout.split("\n").find((l) => l.startsWith("| PR |"));
  assert.ok(row, b.stdout);
  assert.match(row, /^\| PR \| \[acme\/twin#65\]\([^)]*\) \| docs: guides \| the DEVX docs release 1\.5\.10 \| — \| merge: every citation re-read \| approve \| — \|/);
});

test("board.sh fails loud on a needs-review PR whose body lacks the sections, naming it", () => {
  const { gh, run } = ghWorld("old-pr", "## What\nx\n");
  const s = gh.state(); s.issues[`${REPO}#65`].labels = [{ name: "needs-review" }]; s.issues[`${REPO}#65`].assignees = [{ login: "alice" }];
  writeFileSync(join(W, "old-pr-gh", "state.json"), JSON.stringify(s));
  const b = run("board.sh", ["--assignee", "alice"]);
  assert.equal(b.status, 1, b.stdout);
  assert.match(b.stderr, /acme\/twin#65 .*'## Unblocks'/);
  assert.match(b.stdout, /\(missing: Unblocks\) \| — \| \(missing: Recommendation\)/);
});
