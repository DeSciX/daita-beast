// A publish merged under a seat's standing latitude (publish.sh merge --latitude), end to end against a stub gh
// (gh-stub.mjs) and a local bare repo standing in for the public one, with no network:
//   - the merge closes the row with the latitude close line, quoting no words; the publish lands on public main;
//   - the record is verified before any write: a missing file or commit, a public or public-intended repo, another
//     seat's repo are refused; --latitude with --words is refused; a revise-pending row and an amended row with no
//     approval after the amend are refused;
//   - the generated board and the relay (watch.sh) show it as kind latitude; event_actors attributes it to the seat, so
//     the relay never sends it back to that seat and still sends it to another seat on the row;
//   - the latitude line is never an answer form (lib.sh answer_kind and row_answer_url, the page's answerKind), and the
//     page reads it as kind latitude with its record (closeOf).
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
import { ghStub } from "./gh-stub.mjs";
import { loadPage, pageFns } from "./page-harness.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPTS = process.env.BEAST_TEST_SCRIPTS || join(here, "..", "scripts");
const LIB = join(SCRIPTS, "lib.sh");
const PAGE = process.env.BEAST_TEST_PAGE || join(here, "..", "templates", "board.html");
const W = mkdtempSync(join(process.env.BEAST_TEST_TMP || tmpdir(), "beast-latitude-"));

// The protocol prefix is assembled, so no line of this file is itself a filled-in coordination line.
const P = "BEAST" + "-";
const TWIN = "acme/twin", PUB = "acme/site", SLUG = "dv1", ROW = 17;
const REC_SHA = "5e1f00d5e1f00d5e1f00d5e1f00d5e1f00d5e1f0";
const REC_PATH = "docs/standing/2026-10-17-standing-latitude.md";
const OPEN_SHA = "0be40be40be40be40be40be40be40be40be40be4";
const LATER_SHA = "1a7e11a7e11a7e11a7e11a7e11a7e11a7e11a7e";
const LINK = `https://github.com/${TWIN}/blob/${REC_SHA}/${REC_PATH}`;
const LINE = `Merged under standing latitude <${LINK}> by acme/GODSWORLD`;

const git = (dir, ...a) => execFileSync("git", ["-C", dir, ...a], { encoding: "utf8", env: { ...process.env, GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@x", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@x" } }).trim();

// world(name): a twin checkout of acme/twin on main (its roster seats GODSWORLD and BEAST; the workstream's table adds the
// peers OPEN, homed in the public acme/open, and LATER, homed in the public-intended acme/later), its public repo acme/site as a local bare repo (the remote `public`
// resolves to it through url.insteadOf), the branch publish/dv1 (one commit on public main) pushed there with PR #5 open,
// the approval row #17 open, and the records: acme/twin@REC_SHA carries REC_PATH; acme/open (public) and acme/later
// (public_intended) each carry a record too.
function world(name, { comments = [] } = {}) {
  const D = join(W, name), H = join(D, "twin"), B = join(D, "site.git");
  mkdirSync(D, { recursive: true });
  execFileSync("git", ["init", "-q", "--bare", "-b", "main", B]);
  execFileSync("git", ["init", "-q", "-b", "main", H]);
  git(H, "remote", "add", "origin", `https://github.com/${TWIN}.git`);
  git(H, "config", `url.file://${B}.insteadOf`, `https://github.com/${PUB}.git`);
  writeFileSync(join(H, "README.md"), "A small site.\n");
  git(H, "add", "-A"); git(H, "commit", "-q", "-m", "Initial page");
  git(H, "push", "-q", `file://${B}`, "main:main");
  const base = git(H, "rev-parse", "HEAD");
  mkdirSync(join(H, ".beast"), { recursive: true });
  const seat = (label, repo) => ({ label, github: "acme", repo, agent: "daita-beast:seat", workstream: "w" });
  writeFileSync(join(H, ".beast", "roster.json"), JSON.stringify({ repo: TWIN, publishes_to: PUB, board: TWIN, public_intended: ["acme/later"],
    people: [{ github: "acme", name: "Acme", role: "owner" }],
    seats: [seat("GODSWORLD", TWIN), seat("BEAST", TWIN)] }));
  writeFileSync(join(H, "page.txt"), "The new page.\n");
  git(H, "add", "-A"); git(H, "commit", "-q", "-m", "Roster and the page");
  git(H, "checkout", "-q", "-b", `publish/${SLUG}`, base);
  writeFileSync(join(H, "page.txt"), "The new page.\n");
  git(H, "add", "page.txt"); git(H, "commit", "-q", "-m", "Add the new page");
  git(H, "push", "-q", `file://${B}`, `publish/${SLUG}:publish/${SLUG}`);
  git(H, "checkout", "-q", "main");
  const body = `## Decision\nPublish https://github.com/${PUB}/pull/5 to ${PUB}: one new commit.\n\n## Unblocks\nthe squash-merge\n\n## Waits\nyour review\n\n## Recommendation\nApprove.\n\n## Approve with\n"publish ${SLUG}"\n\n## Record\nhttps://github.com/${PUB}/pull/5\n`;
  const row = { number: ROW, title: `Decision: Publish ${SLUG} to ${PUB}`, body, state: "open", html_url: `https://github.com/${TWIN}/issues/${ROW}`,
    labels: [{ name: "decision" }, { name: "seat:acme/GODSWORLD" }, { name: "seat:acme/BEAST" }], assignees: [{ login: "acme" }], user: { login: "acme" },
    created_at: "2026-10-20T19:00:00Z", updated_at: "2026-10-20T19:00:00Z", closed_at: null, repository_url: `https://api.github.com/repos/${TWIN}`, milestone: null, comments: 1 };
  // the workstream's tracking issue: its `## Seats` table holds the peers OPEN and LATER, whose home repos are others
  const tr = (label, repo) => `| acme/${label} | ${repo} | checkout | daita-beast:seat | — | — | — |`;
  const tracking = { number: 1, title: "Workstream: w", state: "open", html_url: `https://github.com/${TWIN}/issues/1`, labels: [{ name: "workstream" }, { name: "ws:w" }],
    assignees: [], user: { login: "acme" }, created_at: "2026-10-20T18:00:00Z", updated_at: "2026-10-20T18:00:00Z", closed_at: null, repository_url: `https://api.github.com/repos/${TWIN}`,
    body: ["## Seats", "| Seat | Repo | Home | Agent | Account | Address | Seen |", "|---|---|---|---|---|---|---|",
      tr("GODSWORLD", TWIN), tr("BEAST", TWIN), tr("OPEN", "acme/open"), tr("LATER", "acme/later"), ""].join("\n") };
  let cn = 0;
  const cm = (b, at) => ({ id: ++cn, body: b, user: { login: "acme" }, created_at: at, html_url: `${row.html_url}#issuecomment-${cn}` });
  const gh = ghStub(join(D, "gh"), { login: "acme",
    repos: { [TWIN]: { private: true }, [PUB]: { private: false }, "acme/open": { private: false }, "acme/later": { private: true } },
    issues: { [`${TWIN}#${ROW}`]: row, [`${TWIN}#1`]: tracking },
    comments: { [`${TWIN}#${ROW}`]: [cm(`${P}ACK seat=acme/GODSWORLD at=2026-10-20T19:00:01Z state=seen next=filed; waits on the decider's word`, "2026-10-20T19:00:01Z"),
      ...comments.map(([b, at]) => cm(b, at))] },
    milestones: {},
    files: { [TWIN]: { [REC_SHA]: [REC_PATH] }, "acme/open": { [OPEN_SHA]: [REC_PATH] }, "acme/later": { [LATER_SHA]: [REC_PATH] } },
    pulls: { [PUB]: [{ number: 5, state: "open", head: { ref: `publish/${SLUG}` }, html_url: `https://github.com/${PUB}/pull/5` }] },
    git: { [PUB]: B } });
  const env = { ...process.env, PATH: `${gh.bin}:${process.env.PATH}`, HOME: D, BEAST_CACHE_DIR: join(D, "cache"), BEAST_WS_CACHE: "" };
  const run = (script, args) => spawnSync(join(SCRIPTS, script), args, { cwd: H, encoding: "utf8", env });
  return { H, B, gh, run, env };
}
const writes = (gh) => gh.log().filter((l) => l.startsWith("WRITE "));
const rowComments = (gh) => gh.state().comments[`${TWIN}#${ROW}`];
const merge = (w, ...extra) => w.run("publish.sh", ["merge", SLUG, ...extra]);
const latitude = (spec = `${TWIN} ${REC_SHA.slice(0, 7)} — ${REC_PATH}`, by = "GODSWORLD") => ["--latitude", spec, "--by", by];

// One merged world, shared by the success, board, relay and answer-form gates.
let merged = null;
function mergedWorld() {
  if (merged) return merged;
  const w = world("merged");
  const r = merge(w, ...latitude());
  merged = { ...w, r };
  return merged;
}

test("gate 1: a latitude merge with a valid private record closes the row with the latitude line and no words", () => {
  const { r, gh, B } = mergedWorld();
  assert.equal(r.status, 0, `publish.sh merge --latitude exited ${r.status}\n${r.stdout}\n${r.stderr}`);
  const close = rowComments(gh).at(-1).body;
  assert.equal(close.split("\n")[0], LINE, close);
  assert.doesNotMatch(close, /verbatim|Record: /, "a latitude close quotes no words");
  assert.match(close, /\nClosed by seat acme\/GODSWORLD at \S+\.\n/);
  assert.match(close.split("\n").at(-1), new RegExp(`^${P}ACK seat=acme/GODSWORLD .*state=seen`));
  const it = gh.state().issues[`${TWIN}#${ROW}`];
  assert.equal(it.state, "closed"); assert.equal(it.state_reason, "completed");
  assert.equal(execFileSync("git", ["-C", B, "show", "main:page.txt"], { encoding: "utf8" }), "The new page.\n", "the publish is on public main");
  assert.equal(spawnSync("git", ["-C", B, "rev-parse", "--verify", "-q", `refs/heads/publish/${SLUG}`]).status, 1, "the public branch is deleted");
});

test("gate 2: a missing file or commit, a public or public-intended repo, another seat's repo: refused before any write", () => {
  const cases = [
    ["a missing file", latitude(`${TWIN} ${REC_SHA.slice(0, 7)} — docs/standing/none.md`), /has no docs\/standing\/none\.md at/],
    ["a missing commit", latitude(`${TWIN} deadbee — ${REC_PATH}`), /has no commit deadbee/],
    ["a public repo", latitude(`acme/open ${OPEN_SHA.slice(0, 7)} — ${REC_PATH}`, "OPEN"), /acme\/open is public on GitHub/],
    ["a public-intended repo", latitude(`acme/later ${LATER_SHA.slice(0, 7)} — ${REC_PATH}`, "LATER"), /acme\/later is listed in the roster's public_intended/],
    ["another seat's repo", latitude(`acme/open ${OPEN_SHA.slice(0, 7)} — ${REC_PATH}`), /is in acme\/open, not in acme\/twin, the own repo of acme\/GODSWORLD/],
  ];
  for (const [what, args, want] of cases) {
    const w = world("refuse-" + what.replace(/\W+/g, "-"));
    const r = merge(w, ...args);
    assert.notEqual(r.status, 0, `${what}: exited 0\n${r.stdout}`);
    assert.match(r.stderr, want, `${what}: ${r.stderr}`);
    assert.deepEqual(writes(w.gh), [], `${what}: wrote before refusing`);
  }
});

test("gate 3: --latitude together with --words is refused before any write", () => {
  const w = world("latitude-and-words");
  const r = merge(w, "--words", `publish ${SLUG}`, ...latitude());
  assert.notEqual(r.status, 0, r.stdout);
  assert.match(r.stderr, /--latitude and --words exclude each other/);
  assert.deepEqual(writes(w.gh), []);
});

test("gate 4: a revise-pending row, and an amended row with no approval after the amend, are refused; an approval after the amend passes", () => {
  const pend = world("revise-pending", { comments: [["revise: name the page", "2026-10-20T19:10:00Z"]] });
  let r = merge(pend, ...latitude());
  assert.notEqual(r.status, 0, r.stdout);
  assert.match(r.stderr, /asked for a revision at .* and the row was not revised/);
  assert.deepEqual(writes(pend.gh), []);
  const amended = world("amended", { comments: [["Amended at 2026-10-20T19:20:00Z: 1 files; added none; removed none; changed page.txt", "2026-10-20T19:20:00Z"]] });
  r = merge(amended, ...latitude());
  assert.notEqual(r.status, 0, r.stdout);
  assert.match(r.stderr, /was amended at 2026-10-20T19:20:00Z and the decider has not approved it since/);
  assert.deepEqual(writes(amended.gh), []);
  const approved = world("amended-approved", { comments: [["Amended at 2026-10-20T19:20:00Z: 1 files; added none; removed none; changed page.txt", "2026-10-20T19:20:00Z"], [`publish ${SLUG}`, "2026-10-20T19:30:00Z"]] });
  r = merge(approved, ...latitude());
  assert.equal(r.status, 0, r.stderr);
  assert.equal(rowComments(approved.gh).at(-1).body.split("\n")[0], LINE);
});

test("gate 5a: the generated board shows the close as kind latitude, its record linked, no words", () => {
  const w = mergedWorld();
  assert.equal(w.r.status, 0, w.r.stderr);
  const b = w.run("board.sh", ["--assignee", "acme"]);
  assert.equal(b.status, 0, b.stderr);
  const line = b.stdout.split("\n").find((l) => l.includes(`[${TWIN}#${ROW}]`));
  assert.ok(line, b.stdout);
  assert.match(line, /^\| \S+ \| latitude \| /, line);
  assert.ok(line.includes(`no words: merged under standing latitude by acme/GODSWORLD, record ${LINK}`), line);
});

test("gate 5b: the relay's DECIDED event carries close=latitude and the line with the record", () => {
  const w = world("relay");
  const watch = () => spawnSync(join(SCRIPTS, "watch.sh"), ["acme/GODSWORLD", "acme/BEAST", "--once"], { cwd: w.H, encoding: "utf8", env: w.env });
  let r = watch();
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stderr, /seat=acme\/BEAST baseline 1/);
  const m = merge(w, ...latitude());
  assert.equal(m.status, 0, m.stderr);
  r = watch();
  assert.equal(r.status, 0, r.stderr);
  const events = r.stdout.split("\n").filter(Boolean);
  assert.deepEqual(events, [`${P}EVENT kind=DECIDED seat=acme/BEAST close=latitude Decision: Publish ${SLUG} to ${PUB} https://github.com/${TWIN}/issues/${ROW} :: ${LINE}`], r.stdout + r.stderr);
  // gate 6, through the relay's own filter: the seat that merged never hears it back
  assert.match(r.stderr, new RegExp(`seat=acme/GODSWORLD own act, not sent: DECIDED https://github.com/${TWIN}/issues/${ROW}`));
});

test("gate 6: event_actors attributes the latitude close to the seat: its own echo is suppressed, another seat is told", () => {
  const { gh } = mergedWorld();
  const cs = rowComments(gh);
  const r = spawnSync("bash", ["-c", `source '${LIB}'; event_actors DECIDED 1 "$1" ""`, "x", JSON.stringify(cs)], { encoding: "utf8", cwd: W });
  assert.equal(r.status, 0, r.stderr);
  const actors = r.stdout.split("\n").filter(Boolean);
  assert.deepEqual(actors, ["acme/GODSWORLD"]);
  // watch.sh sends a seat the event only when some actor is not that seat
  assert.ok(!actors.some((a) => a !== "acme/GODSWORLD"), "GODSWORLD's own act");
  assert.ok(actors.some((a) => a !== "acme/BEAST"), "BEAST is told");
});

test("gate 7: the latitude line is never an answer form: lib.sh answer_kind and row_answer_url, the page's answerKind", () => {
  const { gh, r: m } = mergedWorld();
  const sh = (cmd, args) => spawnSync("bash", ["-c", `source '${LIB}'; ${cmd}`, "x", ...args], { encoding: "utf8", cwd: W });
  const close = rowComments(gh).at(-1).body;
  assert.equal(close.split("\n")[0], LINE, `no latitude close to read (merge exited ${m.status}: ${m.stderr.trim()})`);
  for (const phrase of [`publish ${SLUG}`, ""]) {
    const k = sh('answer_kind "$1" "$2"', [close, phrase]);
    assert.equal(k.status, 0, k.stderr); assert.equal(k.stdout.trim(), "", `answer_kind read the latitude close as '${k.stdout.trim()}' (phrase '${phrase}')`);
  }
  const { answerKind } = pageFns(PAGE, ["answerKind"]);
  assert.equal(answerKind(close, `publish ${SLUG}`), null);
  const rowj = JSON.stringify({ issue: gh.state().issues[`${TWIN}#${ROW}`], comments: rowComments(gh) });
  for (const kind of ["approve", "reject", "revise"]) {
    const u = sh('row_answer_url "$1" "$2" "$3"', [rowj, `publish ${SLUG}`, kind]);
    assert.equal(u.status, 0, u.stderr); assert.equal(u.stdout.trim(), "", `row_answer_url ${kind} took the latitude close as the decider's answer`);
  }
  // the positive control: the same reader, on the same thread with the decider's approval added, finds it
  const approved = [...rowComments(gh), { id: 99, body: `publish ${SLUG}`, user: { login: "acme" }, created_at: "2099-01-01T00:00:00Z", html_url: "u-approve" }];
  const pc = sh('row_answer_url "$1" "$2" approve', [JSON.stringify({ issue: gh.state().issues[`${TWIN}#${ROW}`], comments: approved }), `publish ${SLUG}`]);
  assert.equal(pc.stdout.trim(), "u-approve", "the reader finds a real approval (positive control)");
  assert.equal(answerKind(`publish ${SLUG}`, `publish ${SLUG}`), "approve", "the page reads a real approval (positive control)");
});

test("gate 5c: the page reads the latitude close as kind latitude, with its record and its seat", async () => {
  const { gh } = mergedWorld();
  const { closeOf } = pageFns(PAGE, ["closeOf", "ms"], ["CLOSE_RE"]);
  const c = closeOf(rowComments(gh));
  assert.equal(c?.kind, "latitude", JSON.stringify(c));
  assert.equal(c.record, LINK); assert.equal(c.seat, "acme/GODSWORLD");
  const it = { ...gh.state().issues[`${TWIN}#${ROW}`] };
  const row = { ...it, labels: it.labels.map((l) => l.name), assignees: it.assignees.map((a) => a.login), comments: rowComments(gh).length };
  const p = await loadPage(PAGE, { login: "acme", rows: [row], comments: { [ROW]: rowComments(gh) } });
  const dl = p.text("dlist");
  assert.match(dl, /latitude/, dl);
});
