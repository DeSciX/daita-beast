// A seat's address is its session's live name, read from Claude Code's session files (lib.sh claude_session_of,
// claude_sessions_live), end to end against a stub gh (gh-stub.mjs) and a fake HOME with no network:
//   - a seated session's SessionStart (seat-hello.sh, rejoin) records its live name with no manual step;
//   - the watchdog tick re-stamps a renamed session's address (seats.sh touch), and reports a dead claimed session
//     without re-stamping it;
//   - a name two live sessions carry is recorded with a printed warning;
//   - a session file of another shape fails loud, naming the file and the field;
//   - an address recorded as "name [ref]" still parses (name and ref);
//   - the relay's messenger map carries the new address's name, and a new address resets the not-reachable count.
//   node --test plugin/tests/
// BEAST_TEST_SCRIPTS points the test at another tree (a gate's negative control); BEAST_TEST_TMP is where the fixtures
// are written (default: the OS temp dir).
import { test, after } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawn, spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync, chmodSync } from "node:fs";
import { tmpdir, hostname } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { ghStub } from "./gh-stub.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPTS = process.env.BEAST_TEST_SCRIPTS || join(here, "..", "scripts");
const LIB = join(SCRIPTS, "lib.sh");
const W = mkdtempSync(join(process.env.BEAST_TEST_TMP || tmpdir(), "beast-addr-"));
const P = "BEAST" + "-";   // assembled, so no line of this file is itself a coordination line
const HOST = execFileSync("bash", ["-c", "hostname -s 2>/dev/null || hostname"], { encoding: "utf8" }).trim();
const ID = "beast/BEAST/alice", TRACK = "acme/twin#1", ACCOUNT = "alice@example.com";

// Live pids: sleeping children, killed after the run; a dead pid: a child that has exited.
const kids = [];
const livePid = () => { const c = spawn("sleep", ["600"], { stdio: "ignore" }); kids.push(c); return c.pid; };
const deadPid = () => Number(execFileSync("bash", ["-c", "echo $$"], { encoding: "utf8" }).trim());
after(() => { for (const c of kids) c.kill(); });

const git = (dir, ...a) => execFileSync("git", ["-C", dir, ...a], { encoding: "utf8" }).trim();

// world(name, opts): a fake HOME (its ~/.claude.json, ~/.claude/sessions/<pid>.json files, ~/.beast/sessions.json
// claim), a checkout of acme/twin whose roster seats alice/BEAST in workstream beast (home: the checkout), and a stub gh
// serving the tracking issue acme/twin#1 with the seat's one BEAST-ADDRESS comment.
function world(name, { addr = "twin-old [abc123]", at = "2026-10-21T09:00:00Z", sessions = [], claim = null, files = {} } = {}) {
  const D = join(W, name), HOME = join(D, "home"), R = join(D, "twin");
  mkdirSync(join(HOME, ".claude", "sessions"), { recursive: true });
  mkdirSync(join(HOME, ".beast"), { recursive: true });
  writeFileSync(join(HOME, ".claude.json"), JSON.stringify({ oauthAccount: { emailAddress: ACCOUNT } }));
  for (const s of sessions) writeFileSync(join(HOME, ".claude", "sessions", `${s.pid}.json`), JSON.stringify({ kind: "interactive", nameSource: "derived", status: "idle", ...s }));
  for (const [f, body] of Object.entries(files)) writeFileSync(join(HOME, ".claude", "sessions", f), body);
  execFileSync("git", ["init", "-q", "-b", "main", R]);
  git(R, "remote", "add", "origin", "https://github.com/acme/twin.git");
  mkdirSync(join(R, ".beast"), { recursive: true });
  writeFileSync(join(R, ".beast", "roster.json"), JSON.stringify({ repo: "acme/twin", board: "acme/twin",
    people: [{ github: "alice", name: "Alice", role: "owner" }],
    seats: [{ label: "BEAST", github: "alice", repo: "acme/twin", agent: "daita-beast:seat", workstream: "beast", home: { kind: "checkout", branch: null } }],
    relay: { permissionMode: "bypassPermissions" } }));
  writeFileSync(join(R, ".beast", "seat.json"), JSON.stringify({ id: "alice/BEAST", kind: "checkout" }));
  if (claim) writeFileSync(join(HOME, ".beast", "sessions.json"), JSON.stringify({ [ID]: { tracking: TRACK, launch: R, cwd: R, address: addr, account: ACCOUNT, machine: HOST, recorded_at: at, ...claim } }));
  const tracking = { number: 1, title: "Workstream: beast", state: "open", html_url: "https://github.com/acme/twin/issues/1", labels: [{ name: "workstream" }, { name: "ws:beast" }],
    assignees: [], user: { login: "alice" }, created_at: "2026-10-20T18:00:00Z", updated_at: "2026-10-20T18:00:00Z", closed_at: null, repository_url: "https://api.github.com/repos/acme/twin",
    body: ["## Seats", "| Seat | Repo | Home | Agent | Account | Address | Seen |", "|---|---|---|---|---|---|---|", `| alice/BEAST | acme/twin | checkout | daita-beast:seat | ${ACCOUNT} | ${addr} | ${at} |`, ""].join("\n") };
  const comments = addr === null ? [] : [{ id: 500, body: `${P}ADDRESS seat=${ID} account=${ACCOUNT} address="${addr}" machine=${HOST} at=${at}`, user: { login: "alice" }, created_at: at, html_url: "https://github.com/acme/twin/issues/1#issuecomment-500" }];
  const gh = ghStub(D, { login: "alice", repos: { "acme/twin": { private: true } }, issues: { [TRACK]: tracking }, comments: { [TRACK]: comments } });
  const env = { ...process.env, HOME, PATH: `${gh.bin}:${process.env.PATH}`, CLAUDE_PLUGIN_ROOT: join(SCRIPTS, "..") };
  for (const k of Object.keys(env)) if (k.startsWith("BEAST_") || k === "CLAUDE_CODE_SESSION_ID" || k === "GH_TOKEN" || k === "GITHUB_TOKEN") delete env[k];
  const run = (cmd, args = [], extra = {}, input) => {
    const r = spawnSync(cmd, args, { cwd: R, encoding: "utf8", env: { ...env, ...extra }, input });
    return { out: r.stdout, err: r.stderr, status: r.status };
  };
  const address = () => {
    const c = (gh.state().comments[TRACK] || []).find((x) => x.body.startsWith(`${P}ADDRESS seat=${ID} `));
    return c ? /address="([^"]*)"/.exec(c.body)[1] : null;
  };
  return { D, HOME, R, gh, env, run, address, lib: (cmd, extra = {}) => run("bash", ["-c", `source '${LIB}'; ${cmd}`], extra) };
}

test("a seated session's SessionStart records its live name, with no manual step", () => {
  const pid = livePid();
  const w = world("hello", { claim: { session: "s-held", session_at: "2026-10-21T10:00:00Z" } });
  // the session file's cwd is the checkout (written after the world, which makes it)
  writeFileSync(join(w.HOME, ".claude", "sessions", `${pid}.json`), JSON.stringify({ pid, sessionId: "s-held", cwd: w.R, name: "twin-14", nameSource: "derived", status: "idle", kind: "interactive" }));
  const r = w.run(join(SCRIPTS, "seat-hello.sh"), [], {}, JSON.stringify({ source: "resume", session_id: "s-held" }));
  assert.equal(r.status, 0, r.err);
  const ctx = JSON.parse(r.out).hookSpecificOutput.additionalContext;
  assert.match(ctx, /This session is the Beast seat beast\/BEAST\/alice again/, ctx.slice(0, 600));
  assert.match(ctx, /recorded beast\/BEAST\/alice -> twin-14 /);
  assert.doesNotMatch(ctx, /ListAgents/, "the context asks the session for no ListAgents step");
  assert.equal(w.address(), "twin-14");
  const cache = JSON.parse(readFileSync(join(w.HOME, ".beast", "sessions.json"), "utf8"))[ID];
  assert.equal(cache.session, "s-held", "the claim stays the session join claimed");
  assert.equal(cache.address, "twin-14");
  assert.deepEqual(cache.previous || [], [], "no claim moved");
});

test("a session file of another shape fails loud, naming the file and the field; the hook names the failure", () => {
  const pid = livePid();
  const w = world("shape", { files: { [`${pid}.json`]: JSON.stringify({ pid, sessionId: "s-held", cwd: "/x", status: "idle", title: "renamed field" }) }, claim: { session: "s-held", session_at: "2026-10-21T10:00:00Z" } });
  const r = w.lib(`claude_session_of s-held`);
  assert.notEqual(r.status, 0);
  assert.match(r.err, new RegExp(`${pid}\\.json: field name .*missing or of another shape`));
  const notJson = world("shape2", { files: { "1.json": "{not json" } });
  const n = notJson.lib(`claude_sessions_live`);
  assert.notEqual(n.status, 0);
  assert.match(n.err, /1\.json is not JSON/);
  const h = w.run(join(SCRIPTS, "seat-hello.sh"), [], {}, JSON.stringify({ source: "resume", session_id: "s-held" }));
  assert.equal(h.status, 0, h.err);
  const ctx = JSON.parse(h.out).hookSpecificOutput.additionalContext;
  assert.match(ctx, /^scripts: [^\n]*address: not recorded — the Claude Code session file [^ ]*\.json: field name/);
  assert.equal(w.address(), "twin-old [abc123]", "nothing recorded");
});

test("a name two live sessions carry is recorded, with a printed warning", () => {
  const a = livePid(), b = livePid();
  const w = world("ambiguous", { sessions: [{ pid: a, sessionId: "s-a", cwd: "/w", name: "twin-3" }, { pid: b, sessionId: "s-b", cwd: "/w", name: "twin-3" }] });
  const r = w.run(join(SCRIPTS, "seats.sh"), ["record", "BEAST"], { CLAUDE_CODE_SESSION_ID: "s-a" });
  assert.equal(r.status, 0, r.err);
  assert.match(r.out, /recorded beast\/BEAST\/alice -> twin-3 /);
  assert.match(r.out, /^ambiguous: 2 live sessions on this machine are named "twin-3"/m);
  assert.equal(w.address(), "twin-3");
  const one = world("unique", { sessions: [{ pid: a, sessionId: "s-a", cwd: "/w", name: "twin-4" }] });
  const u = one.run(join(SCRIPTS, "seats.sh"), ["record", "BEAST"], { CLAUDE_CODE_SESSION_ID: "s-a" });
  assert.equal(u.status, 0, u.err);
  assert.doesNotMatch(u.out, /ambiguous/);
});

test("an address recorded as \"name [ref]\" parses into its name and ref; a bare name is valid", () => {
  const w = world("parse", { addr: "unkamon-b5 [78f2c2]" });
  const r = w.lib(`seat_addresses_at ${TRACK}`);
  assert.equal(r.status, 0, r.err);
  const a = JSON.parse(r.out.trim());
  assert.equal(a.address, "unkamon-b5 [78f2c2]"); assert.equal(a.name, "unkamon-b5"); assert.equal(a.ref, "78f2c2");
  const bare = world("parse-bare", { addr: "unkamon-14" });
  const b = JSON.parse(bare.lib(`seat_addresses_at ${TRACK}`).out.trim());
  assert.equal(b.name, "unkamon-14"); assert.equal(b.ref, null);
  const rec = w.run(join(SCRIPTS, "seats.sh"), ["record", "BEAST", "unkamon-c7 [0a1b2c]"]);
  assert.equal(rec.status, 0, rec.err);
  assert.equal(w.address(), "unkamon-c7 [0a1b2c]");
  for (const bad of ["a [xyz]", " lead", "q\"x", "a [78f2c2] [78f2c2]"]) assert.notEqual(w.run("bash", ["-c", `source '${LIB}'; address_parse "$1"`, "x", bad]).status, 0, bad);
});

// tick(w): one watchdog tick against the world (relay not installed; the plugin root is the tree under test).
const tick = (w) => {
  const r = w.run(join(SCRIPTS, "watchdog.sh"), ["--repo", w.R, "--permission-mode", "bypassPermissions"]);
  const log = existsSync(join(w.HOME, ".beast", "watchdog.log")) ? readFileSync(join(w.HOME, ".beast", "watchdog.log"), "utf8") : "";
  return { ...r, log };
};

test("the watchdog tick re-stamps a renamed session's address with its live name", () => {
  const pid = livePid();
  const w = world("renamed", { addr: "twin-b5 [78f2c2]", at: new Date(Date.now() - 3600e3).toISOString().replace(/\.\d+Z$/, "Z"), claim: { session: "s-live", session_at: "2026-10-21T10:00:00Z" } });
  writeFileSync(join(w.HOME, ".claude", "sessions", `${pid}.json`), JSON.stringify({ pid, sessionId: "s-live", cwd: w.R, name: "twin-14", status: "busy" }));
  const r = tick(w);
  assert.equal(r.status, 0, r.err + r.log);
  assert.match(r.log, /address: repaired beast\/BEAST\/alice \(renamed: recorded "twin-b5 \[78f2c2\]", live "twin-14"\)/, r.log);
  assert.equal(w.address(), "twin-14");
  assert.match(w.gh.state().issues[TRACK].body, /\| alice\/BEAST \| acme\/twin \| checkout \| daita-beast:seat \| alice@example\.com \| twin-14 \|/, "the rendered Seats table");
  // the second tick finds nothing to do
  const r2 = tick(w);
  assert.equal(r2.status, 0, r2.err);
  assert.equal((r2.log.match(/address: repaired/g) || []).length, 1, r2.log);
  // a session in another folder is never re-stamped (touch refuses: not the home, not the launch folder)
  const pid2 = livePid();
  const o = world("elsewhere", { addr: "twin-b5 [78f2c2]", claim: { session: "s-else", session_at: "2026-10-21T10:00:00Z" } });
  writeFileSync(join(o.HOME, ".claude", "sessions", `${pid2}.json`), JSON.stringify({ pid: pid2, sessionId: "s-else", cwd: "/", name: "other-1", status: "idle" }));
  const t = tick(o);
  assert.match(t.log, /address: beast\/BEAST\/alice not touched .*neither its home/, t.log);
  assert.equal(o.address(), "twin-b5 [78f2c2]");
});

test("a dead claimed session is reported, not re-stamped", () => {
  const pid = deadPid();
  const w = world("dead", { addr: "twin-b5 [78f2c2]", claim: { session: "s-dead", session_at: "2026-10-21T10:00:00Z" } });
  writeFileSync(join(w.HOME, ".claude", "sessions", `${pid}.json`), JSON.stringify({ pid, sessionId: "s-dead", cwd: w.R, name: "twin-99", status: "idle" }));
  const r = tick(w);
  assert.equal(r.status, 0, r.err + r.log);
  assert.match(r.log, /dead-claim: beast\/BEAST\/alice is claimed by session s-dead, which no live Claude Code session file names .*reported, not re-stamped/, r.log);
  assert.doesNotMatch(r.log, /address: repaired/);
  assert.equal(w.address(), "twin-b5 [78f2c2]");
  const t = w.run(join(SCRIPTS, "seats.sh"), ["touch", ID]);
  assert.notEqual(t.status, 0);
  assert.match(t.err, /refused: the session s-dead claiming beast\/BEAST\/alice is not alive/);
});

// relayWorld(name, ledger): the world's scripts copied with watch.sh replaced by one event for alice/BEAST, and a
// `claude` stub that writes its prompt to a file and answers queued; the unreachable ledger seeded.
function relay(w, ledger) {
  const S = join(w.D, "scripts");
  cpSync(SCRIPTS, S, { recursive: true });
  writeFileSync(join(S, "watch.sh"), `#!/usr/bin/env bash\necho "${P}EVENT kind=DECIDED seat=alice/BEAST row=acme/twin#9 at=2026-10-21T12:00:00Z"\n`);
  chmodSync(join(S, "watch.sh"), 0o755);
  const bin = join(w.D, "claude-bin"); mkdirSync(bin, { recursive: true });
  writeFileSync(join(bin, "claude"), `#!/usr/bin/env bash\nwhile [[ $# -gt 0 ]]; do [[ "$1" == -p ]] && { printf '%s' "$2" > "${w.D}/prompt.txt"; shift; }; shift; done\necho "alice/BEAST queued m1"\n`);
  chmodSync(join(bin, "claude"), 0o755);
  writeFileSync(join(w.HOME, ".beast", "relay-unreachable.json"), JSON.stringify(ledger));
  const r = w.run(join(S, "relay.sh"), ["--repo", w.R], { PATH: `${bin}:${w.env.PATH}` });
  const prompt = existsSync(join(w.D, "prompt.txt")) ? readFileSync(join(w.D, "prompt.txt"), "utf8") : "";
  const log = existsSync(join(w.HOME, ".beast", "relay.log")) ? readFileSync(join(w.HOME, ".beast", "relay.log"), "utf8") : "";
  return { ...r, prompt, log, ledger: JSON.parse(readFileSync(join(w.HOME, ".beast", "relay-unreachable.json"), "utf8")) };
}
const nowIso = () => new Date().toISOString().replace(/\.\d+Z$/, "Z");

test("the relay's map sends the new address's name, and a new address resets the not-reachable count", () => {
  const w = world("relay", { addr: "twin-14", at: nowIso() });
  const r = relay(w, { "alice/BEAST": { address: "twin-b5 [78f2c2]", n: 2, first: "2026-10-21T08:00:00Z", last: "2026-10-21T08:10:00Z" } });
  assert.equal(r.status, 0, r.err + r.log);
  assert.match(r.prompt, /^ADDRESS alice\/BEAST = twin-14$/m, r.log);
  assert.deepEqual(r.ledger, {}, "the queued reply on the new address cleared the ledger");
  // a recorded "name [ref]" is sent as its bare name
  const v = world("relay-ref", { addr: "twin-15 [0a1b2c]", at: nowIso() });
  const s = relay(v, {});
  assert.match(s.prompt, /^ADDRESS alice\/BEAST = twin-15$/m, s.log);
  // the same address with two not-reachable replies is not sent to (the control)
  const x = world("relay-same", { addr: "twin-14", at: nowIso() });
  const t = relay(x, { "alice/BEAST": { address: "twin-14", n: 2, first: "2026-10-21T08:00:00Z", last: "2026-10-21T08:10:00Z" } });
  assert.equal(t.prompt, "", "no messenger for an address not reachable twice");
  assert.match(t.log, /not sending to alice\/BEAST at twin-14: not reachable on 2/);
});
