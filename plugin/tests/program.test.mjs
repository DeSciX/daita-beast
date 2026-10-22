// Consolidation, end to end against a stub gh (gh-stub.mjs, with its clock set so the scripts' comments order against the
// ones a test injects) and the board page run in node (page-harness.mjs), with no network:
//   (1) a seat amends its own row while the decider has not answered (decision.sh revise --by <SEAT>): the amend line
//       makes an approval older than it not count; refused once the decider approved or rejected, on a closed row, and
//       for a seat that is neither the filer nor a seat of the row;
//   (2) a program row (decision.sh new --sub) and its follow-ons (--follows --sub-act): the decider's one approval covers
//       every listed sub-act; a follow-on is filed covered, rendered under its program (board.sh and the page) and closed
//       with close --covered, whose close line cites the program's approval and quotes no words; refused for an unlisted
//       sub-act and while the program is unanswered, revise-pending or rejected;
//   (3) desk.sh ask --supersedes <n>: the new ask carries "Replaces: n=<n>", n is withdrawn, the desk and the page show
//       "replaces n=<n>"; refused when n is answered, withdrawn or no ask;
//   (4) a row whose Waits on: names an open row is "queued behind" it, not the decider's turn, until that row closes.
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
import { ghStub } from "./gh-stub.mjs";
import { loadPage, pageFns } from "./page-harness.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPTS = process.env.BEAST_TEST_SCRIPTS || join(here, "..", "scripts");
const PAGE = process.env.BEAST_TEST_PAGE || join(here, "..", "templates", "board.html");
const W = mkdtempSync(join(process.env.BEAST_TEST_TMP || tmpdir(), "beast-program-"));
// The protocol prefix is assembled, so no line of this file is itself a filled-in coordination line.
const P = "BEAST" + "-";
const REPO = "acme/twin";
const T0 = "2026-10-22T10:00:00Z";

function world(name) {
  const H = join(W, name), D = join(W, name + "-gh");
  mkdirSync(join(H, ".beast"), { recursive: true });
  execFileSync("git", ["-C", H, "init", "-q"]);
  execFileSync("git", ["-C", H, "remote", "add", "origin", `https://github.com/${REPO}.git`]);
  writeFileSync(join(H, ".beast", "roster.json"), JSON.stringify({ repo: REPO, board: REPO, people: [{ github: "alice", name: "Alice", role: "owner" }],
    seats: ["DEVPLANE", "DEVX", "BUILDER"].map((label) => ({ label, github: "alice", repo: REPO, agent: "daita-beast:seat", workstream: "platform" })) }));
  const gh = ghStub(D, { login: "alice", clock: T0, repos: { [REPO]: { private: true } }, issues: {}, comments: {}, milestones: {} });
  const home = join(W, name + "-home"); mkdirSync(home, { recursive: true });
  const env = { ...process.env, PATH: `${gh.bin}:${process.env.PATH}`, HOME: home, BEAST_CACHE_DIR: join(W, name + "-cache"), BEAST_WS_CACHE: "" };
  const run = (script, args) => spawnSync(join(SCRIPTS, script), args, { cwd: H, encoding: "utf8", env });
  const sh = (code, args = []) => spawnSync("bash", ["-c", `source '${join(SCRIPTS, "lib.sh")}'; ${code}`, "sh", ...args], { cwd: H, encoding: "utf8", env });
  const edit = (f) => { const s = gh.state(); f(s); writeFileSync(join(D, "state.json"), JSON.stringify(s)); };
  // The decider's own comment on a row, at a time the test names (an answer typed on GitHub or the board page).
  let cid = 500;
  const say = (n, body, at) => { const id = ++cid; edit((s) => { (s.comments[`${REPO}#${n}`] = s.comments[`${REPO}#${n}`] || []).push({ id, body, user: { login: "alice" }, created_at: at, html_url: `https://github.com/${REPO}/issues/${n}#issuecomment-${id}` }); }); return `https://github.com/${REPO}/issues/${n}#issuecomment-${id}`; };
  const file = (title, extra = [], by = "DEVPLANE") => {
    const r = run("decision.sh", ["new", "--title", title, "--assignee", "alice", "--by", by, "--decision", `do ${title}`, "--unblocks", "the E2E",
      "--waits", "the CEO's word", "--recommendation", "approve", "--approve-with", "go", "--record", "the answer comment", ...extra]);
    return { ...r, n: r.status === 0 ? Number(r.stdout.trim().split("\n").pop().split("/").pop()) : null };
  };
  return { gh, run, sh, edit, say, file };
}
const comments = (gh, n) => gh.state().comments[`${REPO}#${n}`] || [];
const issue = (gh, n) => gh.state().issues[`${REPO}#${n}`];
const writes = (gh) => gh.log().filter((l) => l.startsWith("WRITE ") && !l.startsWith("WRITE POST graphql "));
const refused = (r, re, what) => { assert.notEqual(r.status, 0, `${what}: exited 0\n${r.stdout}`); assert.match(r.stderr, re, `${what}: ${r.stderr}`); };

// ---- (1) a seat amends its own unanswered row ----
test("(1) a seat revises its own unanswered row: the body changes, the amend line voids an earlier approval; refused after an answer", () => {
  const { gh, run, sh, say, edit, file } = world("seat-revise");
  const { n, status, stderr } = file("deploy the Powch microservice");
  assert.equal(status, 0, stderr);
  const before = issue(gh, n).body;
  const r = run("decision.sh", ["revise", `${REPO}#${n}`, "--by", "DEVPLANE", "--recommendation", "approve: Powch#15 is ready, so the deploy carries it"]);
  assert.equal(r.status, 0, r.stderr);
  const body = issue(gh, n).body;
  assert.notEqual(body, before);
  assert.match(body, /## Recommendation\napprove: Powch#15 is ready, so the deploy carries it\n/);
  const amend = comments(gh, n).at(-1);
  const lines = amend.body.split("\n");
  assert.match(lines[0], /^Amended at \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ: amended by alice\/DEVPLANE before any answer; changed: Recommendation$/, lines[0]);
  assert.match(lines.at(-1), new RegExp(`^${P}BODY digest=[0-9a-f]{40}$`), "the amend comment records the body it wrote");
  assert.equal(sh(`body_digest "$1"`, [body]).stdout.trim(), lines.at(-1).split("=")[1]);
  // The decider's approval given before the amend line (on the body the amend replaced) no longer counts; one after it does.
  say(n, "go", "2026-10-22T09:59:59Z");
  const answer = () => sh(`rd="$(row_read ${REPO} ${n})" || exit 1; row_answer_url "$rd" go approve`);
  assert.equal(answer().stdout.trim(), "", "an approval older than the amend does not count");
  assert.match(answer().stderr, /predates the amend/);
  // Run again with the same text: nothing to change.
  refused(run("decision.sh", ["revise", `${REPO}#${n}`, "--by", "DEVPLANE", "--recommendation", "approve: Powch#15 is ready, so the deploy carries it"]), /nothing to change/, "a rerun");
  // A seat that is neither the filer nor a seat of the row.
  let w = writes(gh).length;
  refused(run("decision.sh", ["revise", `${REPO}#${n}`, "--by", "BUILDER", "--waits", "x"]), /alice\/BUILDER is neither the row's filer \(alice\/DEVPLANE\) nor one of its seats/, "a stranger seat");
  assert.equal(writes(gh).length, w, "nothing written");
  // After the decider's approval (newer than the amend), the seat no longer revises.
  const ok = say(n, "go", "2026-10-22T12:00:00Z");
  assert.equal(answer().stdout.trim(), ok, "the approval after the amend counts");
  w = writes(gh).length;
  refused(run("decision.sh", ["revise", `${REPO}#${n}`, "--by", "DEVPLANE", "--waits", "y"]), /the decider has already answered \(approve: /, "after an approval");
  assert.equal(writes(gh).length, w, "nothing written");
  // After a reject, the same.
  const r2 = file("deploy the site");
  say(r2.n, "reject: not this week", "2026-10-22T12:00:00Z");
  refused(run("decision.sh", ["revise", `${REPO}#${r2.n}`, "--by", "DEVPLANE", "--waits", "y"]), /already answered \(reject: /, "after a reject");
  // A closed row.
  const r3 = file("deploy nothing");
  edit((s) => { const it = s.issues[`${REPO}#${r3.n}`]; it.state = "closed"; it.closed_at = "2026-10-22T12:00:00Z"; });
  refused(run("decision.sh", ["revise", `${REPO}#${r3.n}`, "--by", "DEVPLANE", "--waits", "y"]), /is closed/, "a closed row");
  // The decider's revise: is still answered by the seat (the earlier path).
  const r4 = file("deploy the docs");
  const rev = say(r4.n, "revise: name the target", "2026-10-22T12:00:00Z");
  const a4 = run("decision.sh", ["revise", `${REPO}#${r4.n}`, "--by", "DEVPLANE", "--decision", "deploy the docs to PROD"]);
  assert.equal(a4.status, 0, a4.stderr);
  assert.equal(comments(gh, r4.n).at(-1).body.split("\n")[0].replace(/^Amended at \S+ /, ""), `revised after ${rev}; changed: Decision`);
});

// ---- (2) programs and follow-ons ----
const SUBS = ["--sub", "deploy-ms: deploy the Powch microservice to PROD", "--sub", "deploy-site: deploy the Powch site to PROD"];
test("(2) a program row covers its follow-ons on one approval; a follow-on is filed covered, listed under it, closed --covered citing the approval", () => {
  const { gh, run, sh, say, file } = world("program");
  const prog = file("powch program", SUBS);
  assert.equal(prog.status, 0, prog.stderr);
  const pb = issue(gh, prog.n).body;
  assert.match(pb, /## Decision\ndo powch program\n\n## Sub-acts\n- deploy-ms: deploy the Powch microservice to PROD\n- deploy-site: deploy the Powch site to PROD\n\n## Unblocks\n/, pb);
  assert.match(prog.stderr, /program: the decider's one approving answer pre-authorizes deploy-ms, deploy-site/);
  const fol = (slug, extra = []) => file(`powch ${slug}`, ["--follows", `${REPO}#${prog.n}`, "--sub-act", slug, ...extra]);
  // Unanswered: refused before any write.
  let w = writes(gh).length;
  refused(fol("deploy-ms"), /is not approved/, "a follow-on of an unanswered program");
  assert.equal(writes(gh).length, w, "nothing written");
  // The decider's one word.
  const approval = say(prog.n, "go", "2026-10-22T11:00:00Z");
  // Unlisted, or another assignee: refused before any write.
  w = writes(gh).length;
  refused(fol("migrate-db"), /lists no sub-act 'migrate-db' \(it lists: deploy-ms, deploy-site\): a follow-on that wants anything not listed is a normal row/, "an unlisted sub-act");
  const bob = run("decision.sh", ["new", "--title", "powch deploy-ms", "--assignee", "bob", "--by", "DEVPLANE", "--decision", "d", "--unblocks", "u", "--waits", "w",
    "--recommendation", "r", "--approve-with", "go", "--record", "rec", "--follows", `${REPO}#${prog.n}`, "--sub-act", "deploy-ms"]);
  refused(bob, /--assignee bob is not an assignee of the program/, "another assignee");
  refused(file("both", [...SUBS, "--follows", `${REPO}#${prog.n}`, "--sub-act", "deploy-ms"]), /a program \(--sub\) or a follow-on \(--follows\), not both/, "both");
  assert.equal(writes(gh).length, w, "nothing written");
  // Covered.
  const f1 = fol("deploy-ms");
  assert.equal(f1.status, 0, f1.stderr);
  assert.match(issue(gh, f1.n).body, new RegExp(`## Decision\\ndo powch deploy-ms\\n\\nFollows: acme/twin#${prog.n} sub-act deploy-ms\\n`));
  assert.match(f1.stderr, new RegExp(`covered: sub-act deploy-ms of the program acme/twin#${prog.n}, approved at ${approval.replace(/[.#]/g, "\\$&")}`));
  // The generated board: the follow-on right under its program, covered, not counted as the decider's turn.
  const other = file("an unrelated row");
  const b = run("board.sh", ["--assignee", "alice"]);
  assert.equal(b.status, 0, b.stderr);
  const rows = b.stdout.split("\n").filter((l) => /^\| (decision|covered|under|PR)/.test(l));
  const pi = rows.findIndex((l) => l.includes(`[${REPO}#${prog.n}]`));
  assert.ok(pi >= 0, b.stdout);
  assert.match(rows[pi], /^\| decision · program: deploy-ms, deploy-site \|/, rows[pi]);
  assert.match(rows[pi + 1], new RegExp(`^\\| covered by acme/twin#${prog.n} \\(deploy-ms\\) \\| ↳ \\[acme/twin#${f1.n}\\]`), rows[pi + 1]);
  assert.ok(rows.some((l) => l.includes(`[${REPO}#${other.n}]`)));
  assert.match(b.stdout, /3 open \(decision issues and PRs for review; 0 queued behind an open row and 1 follow-on\(s\) under a program, not your turn\)/);
  // Closed by its own seat, with no words, citing the program's approval.
  refused(run("decision.sh", ["close", `${REPO}#${f1.n}`, "--covered", "--by", "BUILDER"]), /neither the row's filer/, "a stranger seat");
  refused(run("decision.sh", ["close", `${REPO}#${f1.n}`, "--covered", "--words", "go", "--by", "DEVPLANE"]), /a covered close quotes no words/, "words");
  refused(run("decision.sh", ["close", `${REPO}#${other.n}`, "--covered", "--by", "DEVPLANE"]), /is not a follow-on row/, "a normal row");
  const c = run("decision.sh", ["close", `${REPO}#${f1.n}`, "--covered", "--by", "DEVPLANE"]);
  assert.equal(c.status, 0, c.stderr);
  assert.equal(issue(gh, f1.n).state, "closed");
  const close = comments(gh, f1.n).at(-1).body;
  assert.equal(close.split("\n")[0], `Closed as covered by <${approval}> by alice/DEVPLANE`);
  assert.doesNotMatch(close, /verbatim/, "a covered close quotes no words");
  const kind = sh(`close_of_comments "$1" | jq -r '.kind + " " + .record + " " + .seat'`, [JSON.stringify(comments(gh, f1.n))]);
  assert.equal(kind.stdout.trim(), `covered ${approval} alice/DEVPLANE`, kind.stderr);
  const d = run("board.sh", ["--assignee", "alice"]);
  assert.match(d.stdout, new RegExp(`\\| covered \\| \\[acme/twin#${f1.n}\\]\\([^)]*\\) \\| powch deploy-ms \\| no words: covered by the program approval ${approval.replace(/[.#]/g, "\\$&")}, closed by alice/DEVPLANE \\|`), d.stdout);
  // A revise of the program re-opens every sub-act: a filed follow-on no longer closes covered, and none is filed.
  const f2 = fol("deploy-site");
  assert.equal(f2.status, 0, f2.stderr);
  say(prog.n, "revise: split the site deploy", "2026-10-22T13:00:00Z");
  w = writes(gh).length;
  refused(run("decision.sh", ["close", `${REPO}#${f2.n}`, "--covered", "--by", "DEVPLANE"]), /asked for a revision at .*: the program covers nothing until it is revised and approved again/, "close under a revise-pending program");
  refused(fol("deploy-site"), /asked for a revision/, "a follow-on of a revise-pending program");
  assert.equal(writes(gh).length, w, "nothing written");
  const b2 = run("board.sh", ["--assignee", "alice"]);
  assert.match(b2.stdout, new RegExp(`\\| under acme/twin#${prog.n} \\(deploy-site\\): not covered: acme/twin#${prog.n}: the decider asked for a revision`), b2.stdout);
  // A rejected program covers nothing.
  const prog2 = file("site program", SUBS);
  say(prog2.n, "reject: not this quarter", "2026-10-22T13:00:00Z");
  refused(file("site deploy-ms", ["--follows", `${REPO}#${prog2.n}`, "--sub-act", "deploy-ms"]), /was rejected .*: a rejected program covers nothing/, "a follow-on of a rejected program");
});

// ---- (2) on the page ----
const BODY = (extra = "") => `## Decision\nd${extra}\n\n## Unblocks\nu\n\n## Waits\nw\n\n## Recommendation\nr\n\n## Approve with\n"go"\n\n## Record\nrec\n`;
const item = (n, body, state = "open") => ({ number: n, title: `Decision: t${n}`, body, state, html_url: `https://github.com/${REPO}/issues/${n}`,
  labels: ["decision", "seat:alice/DEVPLANE"], assignees: ["alice"], created_at: "2026-10-22T10:00:00Z", updated_at: "2026-10-22T10:00:00Z",
  closed_at: state === "closed" ? "2026-10-22T12:00:00Z" : null, repository_url: `https://api.github.com/repos/${REPO}`, comments: 1 });
const ackc = (n) => ({ body: `${P}ACK seat=alice/DEVPLANE at=2026-10-22T10:00:01Z state=seen next=filed`, user: { login: "alice" }, created_at: "2026-10-22T10:00:01Z", html_url: `https://github.com/${REPO}/issues/${n}#issuecomment-1${n}` });
const said = (n, body, at) => ({ body, user: { login: "alice" }, created_at: at, html_url: `https://github.com/${REPO}/issues/${n}#issuecomment-2${n}` });
const PROG = BODY().replace("## Unblocks", "## Sub-acts\n- deploy-ms: deploy the microservice\n- deploy-site: deploy the site\n\n## Unblocks");

test("(2) page: the follow-on renders right under its approved program, covered, never in Waiting on you", async () => {
  const rows = [item(74, PROG), item(75, BODY(`\nFollows: ${REPO}#74 sub-act deploy-ms`)), item(76, BODY())];
  const comments = { [`${REPO}#74`]: [ackc(74), said(74, "go", "2026-10-22T11:00:00Z")], [`${REPO}#75`]: [ackc(75)], [`${REPO}#76`]: [ackc(76)] };
  const p = await loadPage(PAGE, { rows, comments });
  assert.deepEqual(p.turnRows().map((c) => c.key), [`${REPO}#76`], "only the unrelated row waits on the decider");
  assert.match(p.text("turn"), /^1 decision is waiting on you/);
  const ws = p.withSeats();
  const i = ws.findIndex((c) => c.key === `${REPO}#74`);
  assert.ok(i >= 0, JSON.stringify(ws));
  assert.match(ws[i].text, /program · 2 sub-acts/);
  assert.equal(ws[i + 1]?.key, `${REPO}#75`, "the follow-on is the card right after its program");
  assert.equal(ws[i + 1].status, `Covered by ${REPO}#74 (deploy-ms)`);
  assert.equal(ws.filter((c) => c.key === `${REPO}#75`).length, ws.filter((c) => c.key === `${REPO}#74`).length, "once under every copy of its program, nowhere else");
  // Before the program is approved, the follow-on is still under it and still not the decider's turn: the word goes on the program.
  const q = await loadPage(PAGE, { rows, comments: { ...comments, [`${REPO}#74`]: [ackc(74)] } });
  const t = q.turnRows();
  assert.deepEqual(t.map((c) => c.key), [`${REPO}#74`, `${REPO}#75`, `${REPO}#76`].filter((k) => t.some((c) => c.key === k)));
  const fo = t.find((c) => c.key === `${REPO}#75`);
  assert.match(fo.status, /^Under acme\/twin#74 \(deploy-ms\): the program is not approved yet$/);
  assert.equal(t[t.findIndex((c) => c.key === `${REPO}#74`) + 1].key, `${REPO}#75`);
  assert.match(q.text("turn"), /^2 decisions are waiting on you/, "the program and the unrelated row; the follow-on is not counted");
});

test("(2) page: a covered close reads as kind covered with the program's approval linked", () => {
  const { closeOf } = pageFns(PAGE, ["closeOf", "ms"], ["CLOSE_RE"]);
  const url = `https://github.com/${REPO}/issues/74#issuecomment-501`;
  const c = closeOf([{ body: `Closed as covered by <${url}> by alice/DEVPLANE\n\nClosed by seat alice/DEVPLANE at 2026-10-22T12:00:00Z.`, created_at: "2026-10-22T12:00:00Z", html_url: "x" }]);
  assert.deepEqual(JSON.parse(JSON.stringify(c)), { kind: "covered", record: url, seat: "alice/DEVPLANE", url: "x" });
});

test("(2) the readers: lib.sh sub_acts_parse / follows_parse / waits_on_parse and the page's subActsOf / followsOf / waitsOnRows agree", () => {
  const { sh } = world("readers");
  const f = pageFns(PAGE, ["subActsOf", "followsOf", "waitsOnRows"], ["SUBACT_RE", "FOLLOWS_RE", "WAITS_RE"]);
  const TABLE = [
    PROG,
    BODY(`\nFollows: ${REPO}#74 sub-act deploy-ms`),
    BODY(`\nFollows: some.org/repo_x#9 sub-act a-1  `),
    BODY().replace("## Waits\nw", `## Waits\nw\nWaits on: ${REPO}#71\nWaits on: alice/DEVX\nWaits on: other/repo#3`),
    BODY(),
    BODY().replace("## Unblocks", "## Sub-acts\n\n## Unblocks"),
  ];
  for (const body of TABLE) {
    const lib = (fn, jqp) => { const r = sh(`${fn} t "$1"`, [body]); assert.equal(r.status, 0, r.stderr); return r.stdout.split("\n").filter(Boolean).map(jqp); };
    assert.deepEqual(lib("sub_acts_parse", (l) => { const [slug, act] = l.split("\t"); return { slug, act }; }), JSON.parse(JSON.stringify(f.subActsOf(body))), body);
    assert.deepEqual(lib("follows_parse", (l) => { const [ref, slug] = l.split("\t"); return { ref, slug }; })[0] ?? null, JSON.parse(JSON.stringify(f.followsOf(body))), body);
    assert.deepEqual(lib("waits_on_parse", (l) => l).filter((r) => r.includes("#")), Array.from(f.waitsOnRows(body)), body);
  }
  // A malformed line: the scripts die naming it; the page reads none.
  for (const [fn, body] of [["sub_acts_parse", BODY().replace("## Unblocks", "## Sub-acts\n- Deploy: x\n\n## Unblocks")], ["follows_parse", BODY("\nFollows: acme/twin#74 deploy-ms")],
    ["follows_parse", BODY(`\nFollows: ${REPO}#74 sub-act a\nFollows: ${REPO}#74 sub-act b`)]]) {
    const r = sh(`${fn} t "$1"`, [body]);
    assert.notEqual(r.status, 0, `${fn} accepted ${body}`);
    assert.ok(fn === "sub_acts_parse" ? f.subActsOf(body).length === 0 : f.followsOf(body) === null);
  }
});

// ---- (3) desk.sh ask --supersedes ----
test("(3) desk.sh ask --supersedes: the new ask replaces n, n is withdrawn, desk and page show replaces n=; refused when n is not open", async () => {
  const { gh, run, sh } = world("supersede");
  const o = run("desk.sh", ["open", "DEVPLANE"]);
  assert.equal(o.status, 0, o.stderr);
  const dn = Number(o.stdout.match(/issues\/(\d+)/)[1]);
  const ask = (args) => run("desk.sh", ["ask", "DEVPLANE", ...args]);
  assert.equal(ask(["--text", "Deploy the microservice with the site?", "--options", "yes | no"]).status, 0);   // n=1
  assert.equal(ask(["--text", "Name the program?"]).status, 0);   // n=2
  assert.equal(run("desk.sh", ["answer", "DEVPLANE", "2", "powch program", "--by", "DEVPLANE"]).status, 0);
  let w = writes(gh).length;
  refused(ask(["--text", "x", "--supersedes", "2"]), /n=2 is answered on the desk of alice\/DEVPLANE, not an open ask/, "an answered ask");
  refused(ask(["--text", "x", "--supersedes", "9"]), /n=9 is not an ask on the desk/, "no such ask");
  refused(ask(["--text", "Replaces: n=1\nx"]), /may not start with .*Replaces:/, "a question line shaped like the replaces line");
  assert.equal(writes(gh).length, w, "nothing written");
  const s = ask(["--text", "Deploy the microservice with the site, now that Powch#15 is ready?", "--options", "yes | no | split", "--supersedes", "1"]);
  assert.equal(s.status, 0, s.stderr);
  const cs = comments(gh, dn);
  assert.match(cs.at(-2).body, new RegExp(`^${P}ASK n=3 seat=alice/DEVPLANE at=\\S+\\nDeploy the microservice with the site, now that Powch#15 is ready\\?\\nReplaces: n=1\\noptions: yes \\| no \\| split$`), cs.at(-2).body);
  assert.equal(cs.at(-1).body, `${P}WITHDRAW n=1`, "then n=1 is withdrawn");
  const parsed = JSON.parse(sh(`desk_parse alice/DEVPLANE "$(row_read ${REPO} ${dn})"`).stdout);
  assert.deepEqual(parsed.asks.map((a) => [a.n, a.state, a.replaces]), [[1, "withdrawn", null], [2, "answered", null], [3, "open", 1]]);
  assert.deepEqual(parsed.asks[2].question, ["Deploy the microservice with the site, now that Powch#15 is ready?"]);
  assert.match(issue(gh, dn).body, /\| 3 \| \(replaces n=1\) Deploy the microservice with the site, now that Powch#15 is ready\? \|/);
  refused(ask(["--text", "x", "--supersedes", "1"]), /n=1 is withdrawn on the desk/, "a withdrawn ask");
  // The page reads the same and shows it.
  const desk = { ...issue(gh, dn), labels: ["desk", "seat:alice/DEVPLANE"], assignees: ["alice"], comments: cs.length };
  const p = await loadPage(PAGE, { rows: [desk], comments: { [`${REPO}#${dn}`]: cs } });
  const asks = p.turnAsks();
  assert.equal(asks.length, 1, JSON.stringify(asks.map((a) => a.head)));
  assert.match(asks[0].head, /desk ask n=3/);
  assert.match(asks[0].el.textContent, /replaces n=1/);
});

// ---- (4) queued behind an open row ----
test("(4) board.sh: a row waiting on an open row is queued behind it, not the decider's turn, until that row closes", () => {
  const { gh, run, sh, edit, file } = world("queued");
  const a = file("cloud+sites: deploy");
  const b = file("deploy the Powch microservice", ["--waits-on", `${REPO}#1`]);
  assert.equal(b.status, 0, b.stderr);
  const q = () => sh(`row_queued_behind t "$1"`, [issue(gh, b.n).body]).stdout.trim();
  assert.equal(q(), `${REPO}#${a.n}`);
  let out = run("board.sh", ["--assignee", "alice"]);
  assert.equal(out.status, 0, out.stderr);
  const line = (o, n) => o.stdout.split("\n").find((l) => l.includes(`[${REPO}#${n}]`));
  assert.match(line(out, b.n), new RegExp(`^\\| decision · queued behind ${REPO}#${a.n} \\|`), line(out, b.n));
  assert.match(line(out, a.n), /^\| decision \|/);
  assert.match(out.stdout, /2 open \(decision issues and PRs for review; 1 queued behind an open row/);
  edit((s) => { const it = s.issues[`${REPO}#${a.n}`]; it.state = "closed"; it.closed_at = "2026-10-22T12:00:00Z"; });
  assert.equal(q(), "");
  out = run("board.sh", ["--assignee", "alice"]);
  assert.match(line(out, b.n), /^\| decision \|/, line(out, b.n));
  assert.match(out.stdout, /1 open \(decision issues and PRs for review; 0 queued behind an open row/);
});

test("(4) page: a row #73 waiting on #71 is queued while #71 is open (on the board or not), and your turn once #71 closes", async () => {
  const W73 = BODY().replace("## Waits\nw", `## Waits\nthe microservice deploy waits on the backend deploy\nWaits on: ${REPO}#71`);
  const cm = { [`${REPO}#71`]: [ackc(71)], [`${REPO}#73`]: [ackc(73)] };
  const open = await loadPage(PAGE, { rows: [item(71, BODY()), item(73, W73)], comments: cm });
  assert.deepEqual(open.turnRows().map((c) => c.key), [`${REPO}#71`]);
  assert.match(open.text("turn"), /^1 decision is waiting on you/);
  assert.equal(open.withSeats().find((c) => c.key === `${REPO}#73`)?.status, `Queued behind ${REPO}#71`);
  // #71 assigned to someone else: not on the viewer's board, read once with issue_read get.
  const elsewhere = await loadPage(PAGE, { rows: [item(73, W73)], comments: cm, others: [{ ...item(71, BODY()), assignees: ["bob"] }] });
  assert.deepEqual(elsewhere.turnRows(), []);
  assert.equal(elsewhere.withSeats().find((c) => c.key === `${REPO}#73`)?.status, `Queued behind ${REPO}#71`);
  assert.ok(elsewhere.calls.some((c) => c.tool === "issue_read" && c.args.method === "get" && c.args.issue_number === 71));
  const closed = await loadPage(PAGE, { rows: [item(71, BODY(), "closed"), item(73, W73)], comments: cm });
  assert.deepEqual(closed.turnRows().map((c) => [c.key, c.status]), [[`${REPO}#73`, "Your turn"]]);
});
