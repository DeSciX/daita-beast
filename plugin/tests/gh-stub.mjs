// A stub `gh` for the scripts' tests: serves GitHub's REST shapes from one JSON state file and applies writes to it,
// never touching the network. ghStub(dir, state) writes <dir>/bin/gh (a node script) and <dir>/state.json and returns
// {bin, state(), log()}: PATH=<bin>:$PATH runs a script against it; state() re-reads the file; log() is every call,
// one line each, writes prefixed WRITE. An unsupported call exits 2 naming it, so a test never passes on a call the
// stub did not model.
//   state: {login, repos: {"o/r": {private}}, issues: {"o/r#N": <issue, REST shape>}, comments: {"o/r#N": [...]},
//           milestones: {"o/r": [...]}}
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
  if ((m = /^repos\/([^/]+)\/([^/]+)$/.exec(route))) { const r = S.repos[m[1] + "/" + m[2]]; if (!r) out(404, { message: "Not Found" }, head); out(200, { full_name: m[1] + "/" + m[2], private: r.private, default_branch: "main" }, head); }
  if ((m = /^repos\/([^/]+)\/([^/]+)\/issues\/(\d+)$/.exec(route))) { const it = S.issues[key(m[1], m[2], m[3])]; if (!it) out(404, { message: "Not Found" }, head); out(200, it, head); }
  if ((m = /^repos\/([^/]+)\/([^/]+)\/issues\/(\d+)\/comments$/.exec(route))) { const all = S.comments[key(m[1], m[2], m[3])] || [], pg = Number(q.get("page") || 1), pp = Number(q.get("per_page") || 30); out(200, all.slice((pg - 1) * pp, pg * pp), head); }
  if ((m = /^repos\/([^/]+)\/([^/]+)\/milestones$/.exec(route))) out(200, (S.milestones || {})[m[1] + "/" + m[2]] || [], head);
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
      if (/^sort:/.test(t)) return true;
      fail("search term " + t);
    }));
    if (Number(q.get("page") || 1) > 1) out(200, { total_count: items.length, items: [] }, head);
    out(200, { total_count: items.length, items }, head);
  }
  if ((m = /^repos\/([^/]+)\/([^/]+)\/issues$/.exec(route))) { const r = m[1] + "/" + m[2]; out(200, Number(q.get("page") || 1) > 1 ? [] : Object.entries(S.issues).filter(([k, it]) => k.startsWith(r + "#") && (!q.get("state") || it.state === q.get("state"))).map(([, it]) => it), head); }
  fail("GET " + p);
}
if (route === "graphql") out(200, { data: {} });
if ((m = /^repos\/([^/]+)\/([^/]+)\/labels(\/.*)?$/.exec(route))) out(200, { name: fields.name || fields.new_name });
if ((m = /^repos\/([^/]+)\/([^/]+)\/issues\/(\d+)(\/(labels|assignees|comments))?$/.exec(route))) {
  const k = key(m[1], m[2], m[3]), it = S.issues[k]; if (!it) out(404, { message: "Not Found" });
  it.updated_at = now();
  if (m[5] === "labels" && method === "POST") { for (const l of fields.labels) if (!it.labels.some((x) => x.name === l)) it.labels.push({ name: l }); save(); out(200, it.labels); }
  if (m[5] === "assignees" && method === "POST") { for (const l of fields.assignees) if (!it.assignees.some((x) => x.login === l)) it.assignees.push({ login: l }); save(); out(200, it); }
  if (m[5] === "comments" && method === "POST") { const list = S.comments[k] = S.comments[k] || []; const id = 1000 + list.length + Object.keys(S.comments).length * 100;
    const c = { id, body: fields.body, user: { login: S.login }, created_at: now(), html_url: it.html_url + "#issuecomment-" + id }; list.push(c); save(); out(201, c); }
  if (!m[5] && method === "PATCH") { for (const f of ["body", "state", "title"]) if (f in fields) it[f] = fields[f]; if (fields.milestone) it.milestone = { number: Number(fields.milestone) }; save(); out(200, it); }
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
