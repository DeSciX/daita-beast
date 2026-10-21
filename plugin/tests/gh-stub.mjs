// A stub `gh` for the scripts' tests: serves GitHub's REST shapes from one JSON state file and applies writes to it,
// never touching the network. ghStub(dir, state) writes <dir>/bin/gh (a node script) and <dir>/state.json and returns
// {bin, state(), log()}: PATH=<bin>:$PATH runs a script against it; state() re-reads the file; log() is every call,
// one line each, writes prefixed WRITE. An unsupported call exits 2 naming it, so a test never passes on a call the
// stub did not model.
//   state: {login, repos: {"o/r": {private}}, issues: {"o/r#N": <issue, REST shape>}, comments: {"o/r#N": [...]},
//           milestones: {"o/r": [...]}, files: {"o/r": {"<full sha>": ["<path>", ...]}}, pulls: {"o/r": [<PR, REST shape,
//           head.ref>]}, git: {"o/r": "<bare repo dir>"}, roles: {"o/r": {"<login>": "admin|maintain|write|read"}}}
//   edits: {"o/r#N": [{editedAt, deletedAt, diff}, ...]}, oldest first: the body's edit history, served newest first to
//   the GraphQL userContentEdits query (as GitHub does) and appended by every PATCH that changes an issue's body (the first
//   one also records the body as created); edits_fail makes that query fail with its text
//   the issues list honours state (open, closed, all) and labels (every one named); collaborators/<login>/permission
//   answers roles (a login it does not list is "none")
//   rate_limit answers a full quota; issues/comments/<id> takes PATCH (body) and DELETE; POST issues creates one (its
//   labels minus any named in state.drop_labels, to model a label that does not land).
//   files serves commits/<sha or prefix> and contents/<path>?ref=<sha>; pulls serves the PR list (state, head=<owner>:<ref>)
//   and the squash-merge, made for real in the bare repo git names (a commit with the PR head's tree on main); a
//   DELETE git/refs/heads/<ref> deletes it there.
import { writeFileSync, readFileSync, mkdirSync, chmodSync } from "node:fs";
import { join } from "node:path";

const STUB = String.raw`#!/usr/bin/env node
const fs = require("fs"), path = require("path");
const DIR = path.join(__dirname, "..");
const SF = path.join(DIR, "state.json");
const S = JSON.parse(fs.readFileSync(SF, "utf8"));
const argv = process.argv.slice(2);
const log = (l) => fs.appendFileSync(path.join(DIR, "gh.log"), l + "\n");
const save = () => fs.writeFileSync(SF, JSON.stringify(S, null, 1));
const out = (code, body, head) => { process.stdout.write(head ? "HTTP/2.0 " + code + " X\r\nContent-Type: application/json\r\n\r\n" + JSON.stringify(body) + "\n" : JSON.stringify(body) + "\n"); process.exit(code < 300 ? 0 : 1); };
const fail = (m) => { process.stderr.write("stub gh: unsupported " + m + "\n"); process.exit(2); };
if (argv[0] === "auth" && argv[1] === "token") { process.stdout.write("stubtoken\n"); process.exit(0); }
if (argv[0] !== "api") fail(argv.join(" "));
let head = false, method = "GET", p = null; const fields = {};
for (let i = 1; i < argv.length; i++) {
  const a = argv[i];
  if (a === "-i") head = true;
  else if (a === "-X") method = argv[++i];
  else if (a === "-H") i++;
  else if (a === "-f" || a === "-F") { const kv = argv[++i], k = kv.slice(0, kv.indexOf("=")); let v = kv.slice(kv.indexOf("=") + 1);
    if (a === "-F" && v.startsWith("@")) v = fs.readFileSync(v.slice(1), "utf8");
    if (k.endsWith("[]")) (fields[k.slice(0, -2)] = fields[k.slice(0, -2)] || []).push(v); else fields[k] = v; }
  else p = a;
}
log((method === "GET" ? "" : "WRITE ") + method + " " + p + (method === "GET" ? "" : " " + JSON.stringify(fields)));
const [route, qs] = p.split("?"); const q = new URLSearchParams(qs || "");
let m;
const key = (o, r, n) => o + "/" + r + "#" + n;
const now = () => new Date().toISOString().replace(/\.\d+Z$/, "Z");
if (method === "GET") {
  if (route === "user") out(200, { login: S.login }, head);
  if (route === "rate_limit") out(200, { resources: { core: { remaining: 5000, limit: 5000 }, search: { remaining: 30, limit: 30 } } }, head);
  if ((m = /^repos\/([^/]+)\/([^/]+)$/.exec(route))) { const r = S.repos[m[1] + "/" + m[2]]; if (!r) out(404, { message: "Not Found" }, head); out(200, { full_name: m[1] + "/" + m[2], private: r.private, default_branch: "main" }, head); }
  if ((m = /^repos\/([^/]+)\/([^/]+)\/issues\/(\d+)$/.exec(route))) { const it = S.issues[key(m[1], m[2], m[3])]; if (!it) out(404, { message: "Not Found" }, head); out(200, it, head); }
  if ((m = /^repos\/([^/]+)\/([^/]+)\/issues\/(\d+)\/comments$/.exec(route))) { const all = S.comments[key(m[1], m[2], m[3])] || [], pg = Number(q.get("page") || 1), pp = Number(q.get("per_page") || 30); out(200, all.slice((pg - 1) * pp, pg * pp), head); }
  if ((m = /^repos\/([^/]+)\/([^/]+)\/milestones$/.exec(route))) out(200, (S.milestones || {})[m[1] + "/" + m[2]] || [], head);
  if ((m = /^users\/([^/]+)$/.exec(route))) out(200, { login: m[1], type: "User" }, head);
  if (route === "user/repos") out(200, Number(q.get("page") || 1) > 1 ? [] : Object.entries(S.repos).filter(([k, r]) => k.split("/")[0] === S.login && r.private).map(([k]) => ({ full_name: k, private: true })), head);
  if ((m = /^repos\/([^/]+)\/([^/]+)\/commits\/([0-9a-fA-F]+)$/.exec(route))) { const shas = Object.keys((S.files || {})[m[1] + "/" + m[2]] || {}).filter((x) => x.startsWith(m[3].toLowerCase()));
    if (shas.length !== 1) out(shas.length ? 409 : 422, { message: "No commit found for SHA: " + m[3] }, head); out(200, { sha: shas[0] }, head); }
  if ((m = /^repos\/([^/]+)\/([^/]+)\/contents\/(.+)$/.exec(route))) { const t = ((S.files || {})[m[1] + "/" + m[2]] || {})[q.get("ref")]; const pth = decodeURIComponent(m[3]);
    if (!t) out(404, { message: "No commit found for the ref " + q.get("ref") }, head);
    if (t.includes(pth)) out(200, { type: "file", path: pth }, head);
    if (t.some((f) => f.startsWith(pth + "/"))) out(200, t.filter((f) => f.startsWith(pth + "/")).map((f) => ({ type: "file", path: f })), head);
    out(404, { message: "Not Found" }, head); }
  if ((m = /^repos\/([^/]+)\/([^/]+)\/pulls$/.exec(route))) { const hd = q.get("head"), st = q.get("state") || "open";
    out(200, Number(q.get("page") || 1) > 1 ? [] : ((S.pulls || {})[m[1] + "/" + m[2]] || []).filter((pr) => (st === "all" || pr.state === st) && (!hd || hd === m[1] + ":" + pr.head.ref)), head); }
  if (route === "search/issues") {
    const terms = q.get("q").match(/(?:[^\s"]+|"[^"]*")+/g) || [];
    const items = Object.values(S.issues).filter((it) => terms.every((t) => {
      let mm;
      if (t === "is:open" || t === "is:closed") return it.state === t.slice(3);
      if (t === "is:pr") return !!it.pull_request; if (t === "is:issue") return !it.pull_request;
      if ((mm = /^label:(.+)$/.exec(t))) return mm[1].replace(/"/g, "").split(",").some((l) => it.labels.some((x) => x.name === l));
      if ((mm = /^assignee:(.+)$/.exec(t))) return it.assignees.some((a) => a.login === mm[1]);
      if ((mm = /^user:(.+)$/.exec(t))) return it.repository_url.split("/repos/")[1].split("/")[0] === mm[1];
      if ((mm = /^closed:>=(.+)$/.exec(t))) return !!it.closed_at && it.closed_at >= mm[1];
      if ((mm = /^updated:>=(.+)$/.exec(t))) return !!it.updated_at && it.updated_at >= mm[1];
      if (/^sort:/.test(t)) return true;
      fail("search term " + t);
    }));
    if (Number(q.get("page") || 1) > 1) out(200, { total_count: items.length, items: [] }, head);
    out(200, { total_count: items.length, items }, head);
  }
  if ((m = /^repos\/([^/]+)\/([^/]+)\/issues$/.exec(route))) { const r = m[1] + "/" + m[2], st = q.get("state"), lb = q.get("labels");
    out(200, Number(q.get("page") || 1) > 1 ? [] : Object.entries(S.issues).filter(([k, it]) => k.startsWith(r + "#") && (!st || st === "all" || it.state === st)
      && (!lb || lb.split(",").every((l) => it.labels.some((x) => x.name === l)))).map(([, it]) => it), head); }
  if ((m = /^repos\/([^/]+)\/([^/]+)\/collaborators\/([^/]+)\/permission$/.exec(route))) { const p = ((S.roles || {})[m[1] + "/" + m[2]] || {})[m[3]];
    out(200, { permission: p || "none" }, head); }
  fail("GET " + p);
}
if (route === "graphql" && /userContentEdits/.test(fields.query || "")) {
  if (S.edits_fail) { process.stderr.write("gh: " + S.edits_fail + "\n"); process.exit(1); }
  const it = S.issues[key(fields.o, fields.r, fields.n)];
  if (!it) out(200, { data: { repository: { issueOrPullRequest: null } } });
  out(200, { data: { repository: { issueOrPullRequest: { userContentEdits: { pageInfo: { hasNextPage: false, endCursor: null },
    nodes: ((S.edits || {})[key(fields.o, fields.r, fields.n)] || []).slice().reverse() } } } } });
}
if (route === "graphql") out(200, { data: {} });
if ((m = /^repos\/([^/]+)\/([^/]+)\/pulls\/(\d+)\/merge$/.exec(route)) && method === "PUT") {
  const { execFileSync } = require("child_process");
  const r = m[1] + "/" + m[2], pr = ((S.pulls || {})[r] || []).find((x) => x.number === Number(m[3])), bare = (S.git || {})[r];
  if (!pr || !bare || pr.state !== "open") out(405, { message: "Pull Request is not mergeable" });
  const g = (...a) => execFileSync("git", ["-C", bare, ...a], { encoding: "utf8" }).trim();
  const headSha = g("rev-parse", "refs/heads/" + pr.head.ref);
  if (fields.sha && fields.sha !== headSha) out(409, { message: "Head branch was modified" });
  const base = g("rev-parse", "refs/heads/main");
  const sha = g("commit-tree", headSha + "^{tree}", "-p", base, "-m", (fields.commit_title || "squash") + "\n\n" + (fields.commit_message || ""));
  g("update-ref", "refs/heads/main", sha, base);
  pr.state = "closed"; pr.merged = true; save(); out(200, { sha, merged: true });
}
if ((m = /^repos\/([^/]+)\/([^/]+)\/git\/refs\/heads\/(.+)$/.exec(route)) && method === "DELETE") {
  const bare = (S.git || {})[m[1] + "/" + m[2]]; if (!bare) out(404, { message: "Not Found" });
  require("child_process").execFileSync("git", ["-C", bare, "update-ref", "-d", "refs/heads/" + m[3]]); process.exit(0);
}
if ((m = /^repos\/([^/]+)\/([^/]+)\/labels(\/.*)?$/.exec(route))) out(200, { name: fields.name || fields.new_name });
if ((m = /^repos\/([^/]+)\/([^/]+)\/issues$/.exec(route)) && method === "POST") {
  const r = m[1] + "/" + m[2], n = 1 + Math.max(0, ...Object.keys(S.issues).filter((k) => k.startsWith(r + "#")).map((k) => Number(k.split("#")[1])));
  const it = { number: n, title: fields.title, body: fields.body, state: "open", html_url: "https://github.com/" + r + "/issues/" + n, labels: (fields.labels || []).map((name) => ({ name })),
    assignees: (fields.assignees || []).map((login) => ({ login })), user: { login: S.login }, comments: 0, created_at: now(), updated_at: now(), closed_at: null,
    repository_url: "https://api.github.com/repos/" + r, milestone: fields.milestone ? { number: Number(fields.milestone) } : null };
  if (S.drop_labels) it.labels = it.labels.filter((l) => !S.drop_labels.includes(l.name));
  S.issues[r + "#" + n] = it; save(); out(201, it);
}
if ((m = /^repos\/([^/]+)\/([^/]+)\/issues\/comments\/(\d+)$/.exec(route)) && (method === "PATCH" || method === "DELETE")) {
  const r = m[1] + "/" + m[2], id = Number(m[3]);
  for (const k of Object.keys(S.comments).filter((x) => x.startsWith(r + "#"))) {
    const i = S.comments[k].findIndex((c) => c.id === id); if (i < 0) continue;
    if (method === "DELETE") { S.comments[k].splice(i, 1); save(); process.exit(0); }
    S.comments[k][i].body = fields.body; S.comments[k][i].updated_at = now(); save(); out(200, S.comments[k][i]);
  }
  out(404, { message: "Not Found" });
}
if ((m = /^repos\/([^/]+)\/([^/]+)\/issues\/(\d+)(\/(labels|assignees|comments))?$/.exec(route))) {
  const k = key(m[1], m[2], m[3]), it = S.issues[k]; if (!it) out(404, { message: "Not Found" });
  it.updated_at = now();
  if (m[5] === "labels" && method === "POST") { for (const l of fields.labels) if (!it.labels.some((x) => x.name === l)) it.labels.push({ name: l }); save(); out(200, it.labels); }
  if (m[5] === "assignees" && method === "POST") { for (const l of fields.assignees) if (!it.assignees.some((x) => x.login === l)) it.assignees.push({ login: l }); save(); out(200, it); }
  if (m[5] === "comments" && method === "POST") { const list = S.comments[k] = S.comments[k] || []; const id = 1000 + list.length + Object.keys(S.comments).length * 100;
    const c = { id, body: fields.body, user: { login: S.login }, created_at: now(), html_url: it.html_url + "#issuecomment-" + id }; list.push(c); save(); out(201, c); }
  if (!m[5] && method === "PATCH" && "body" in fields && fields.body !== it.body) { const h = (S.edits = S.edits || {})[k] = S.edits[k] || [];
    if (!h.length) h.push({ editedAt: it.created_at, deletedAt: null, diff: it.body }); h.push({ editedAt: now(), deletedAt: null, diff: fields.body }); }
  if (!m[5] && method === "PATCH") { for (const f of ["body", "state", "title", "state_reason"]) if (f in fields) it[f] = fields[f]; if (fields.state === "closed") it.closed_at = now(); if (fields.milestone) it.milestone = { number: Number(fields.milestone) }; save(); out(200, it); }
}
fail(method + " " + p);
`;

export function ghStub(dir, state) {
  const bin = join(dir, "bin");
  mkdirSync(bin, { recursive: true });
  writeFileSync(join(bin, "gh"), STUB);
  chmodSync(join(bin, "gh"), 0o755);
  writeFileSync(join(dir, "state.json"), JSON.stringify(state, null, 1));
  writeFileSync(join(dir, "gh.log"), "");
  return {
    bin,
    state: () => JSON.parse(readFileSync(join(dir, "state.json"), "utf8")),
    log: () => readFileSync(join(dir, "gh.log"), "utf8").split("\n").filter(Boolean),
  };
}
