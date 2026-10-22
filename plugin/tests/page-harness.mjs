// The board page (plugin/templates/board.html) run in node: its one <script> evaluated in a vm context with a minimal
// DOM and a stubbed GitHub connector (window.claude.use("mcp")), so a test reads what the page renders for a fixture
// of rows and comments. The stub models the connector as it is defined: search_issues is scoped to is:issue (it never
// returns a pull request) and search_pull_requests to is:pr; labels and assignees come back as strings.
import { readFileSync } from "node:fs";
import vm from "node:vm";

class Node_ {
  constructor(tag, doc) { this.tagName = tag; this.doc = doc; this.childNodes = []; this.attrs = {}; this.className = ""; this.hidden = false; this.disabled = false; this.parent = null; this.listeners = {}; this._text = null; }
  get textContent() { return this._text !== null ? this._text : this.childNodes.map((c) => c.textContent).join(""); }
  set textContent(v) { this.childNodes.forEach((c) => { c.parent = null; }); this.childNodes = []; this._text = this.tagName === "#text" ? String(v) : null; if (this.tagName !== "#text" && v !== "" && v != null) this.appendChild(this.doc.createTextNode(String(v))); }
  get firstChild() { return this.childNodes[0] || null; }
  appendChild(c) { return this.insertBefore(c, null); }
  insertBefore(c, ref) {
    if (c.tagName === "#fragment") { c.childNodes.slice().forEach((k) => this.insertBefore(k, ref)); return c; }
    if (c.parent) c.parent.childNodes.splice(c.parent.childNodes.indexOf(c), 1);
    const i = ref ? this.childNodes.indexOf(ref) : -1;
    if (i < 0) this.childNodes.push(c); else this.childNodes.splice(i, 0, c);
    c.parent = this; return c;
  }
  remove() { if (this.parent) { this.parent.childNodes.splice(this.parent.childNodes.indexOf(this), 1); this.parent = null; } }
  setAttribute(k, v) { this.attrs[k] = String(v); if (k === "id") this.doc.ids.set(String(v), this); }
  getAttribute(k) { return this.attrs[k] ?? null; }
  addEventListener(k, f) { (this.listeners[k] = this.listeners[k] || []).push(f); }
  focus() {} scrollIntoView() {}
  all() { return [this, ...this.childNodes.flatMap((c) => c.all())]; }
  querySelector(sel) { const cls = sel.replace(/^\./, ""); return this.all().slice(1).find((n) => (" " + n.className + " ").includes(" " + cls + " ")) || null; }
  find(cls) { return this.all().filter((n) => (" " + n.className + " ").includes(" " + cls + " ")); }
}
class Doc {
  constructor() { this.ids = new Map(); this.hidden = false; this.listeners = {}; }
  createElement(t) { return new Node_(t, this); }
  createTextNode(s) { const n = new Node_("#text", this); n._text = String(s); return n; }
  createDocumentFragment() { return new Node_("#fragment", this); }
  getElementById(id) { if (!this.ids.has(id)) { const n = this.createElement("div"); n.setAttribute("id", id); } return this.ids.get(id); }
  addEventListener(k, f) { (this.listeners[k] = this.listeners[k] || []).push(f); }
}

const isPR = (it) => /\/pull\/\d+/.test(it.html_url);
// labels:"a,b" OR terms of a query, and is:open / is:closed.
function matches(it, q) {
  const st = /is:(open|closed)/.exec(q); if (st && it.state !== st[1]) return false;
  const lab = /label:(\S+)/.exec(q); if (lab && !lab[1].split(",").some((l) => it.labels.includes(l))) return false;
  const who = /assignee:(\S+)/.exec(q); if (who && !it.assignees.includes(who[1])) return false;
  return true;
}

// loadPage(pagePath, {login, rows, comments}): rows are connector-shaped items ({number, title, body, state, html_url,
// labels: [names], assignees: [logins], created_at, updated_at, repository_url}); comments maps "owner/repo#N" (or a bare number) -> [{body, user:{login},
// created_at, html_url}]; issuesScoped false makes search_issues return pull requests too (the connector as measured
// 2026-10-12); a tool named in missing is refused as outside the page's grant; hash is the location hash the page opens
// with (a deep link). add_issue_comment appends the comment to the thread it names and answers it as the connector does.
// issue_read get answers an item of rows or of others (connector-shaped items no search returns: rows assigned to
// someone else), by owner/repo and number; any other item is refused as not found.
// Resolves once the page has rendered every read; returns {doc, calls, text(id), turnRows(), withSeats(), turnAsks(),
// click(node), settle()}.
export async function loadPage(pagePath, { login = "alice", rows = [], comments = {}, issuesScoped = true, missing = [], hash = "", others = [] } = {}) {
  const html = readFileSync(pagePath, "utf8");
  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  if (!scripts.length) throw new Error(`${pagePath}: no inline <script>`);
  const src = scripts[scripts.length - 1][1];
  const doc = new Doc(), calls = [];
  const mcp = {
    callTool(server, tool, args) {
      calls.push({ tool, args });
      const ok = (payload) => Promise.resolve({ payload });
      if (missing.includes(tool)) return Promise.reject({ code: "not_in_manifest", message: "the page's grant has no " + tool });
      if (tool === "get_me") return ok({ login });
      if (tool === "search_issues") return ok({ total_count: 0, items: rows.filter((it) => (!issuesScoped || !isPR(it)) && matches(it, args.query)) });
      if (tool === "search_pull_requests") return ok({ total_count: 0, items: rows.filter((it) => isPR(it) && matches(it, args.query)) });
      if (tool === "add_issue_comment") {
        const k = `${args.owner}/${args.repo}#${args.issue_number}`, list = comments[k] = comments[k] || [];
        const c = { body: args.body, user: { login }, created_at: new Date().toISOString(), html_url: `https://github.com/${args.owner}/${args.repo}/issues/${args.issue_number}#issuecomment-${9000 + list.length}` };
        list.push(c);
        const it = rows.find((r) => r.html_url.endsWith(`/${args.owner}/${args.repo}/issues/${args.issue_number}`)); if (it) it.updated_at = c.created_at;
        return ok(c);
      }
      if (tool === "issue_read" && args.method === "get") {
        const it = rows.concat(others).find((r) => r.html_url.replace(/\/pull\//, "/issues/").endsWith(`/${args.owner}/${args.repo}/issues/${args.issue_number}`));
        return it ? ok(it) : Promise.reject({ code: "tool_error", message: "Not Found" });
      }
      if (tool === "issue_read" && args.method === "get_comments") return ok((comments[`${args.owner}/${args.repo}#${args.issue_number}`] || comments[args.issue_number] || []).slice((args.page - 1) * args.perPage, args.page * args.perPage));
      return Promise.reject({ code: "tool_error", message: "stub connector has no " + tool });
    },
  };
  let pending = 0;
  const ctx = {
    document: doc, console, Promise, Date, JSON, Math, Map, Set, Object, Array, String, Number, RegExp, Error, isNaN, encodeURIComponent,
    location: { hash, pathname: "/", search: "" }, sessionStorage: { getItem: () => null, setItem() {} }, localStorage: { getItem: () => null, setItem() {} },
    // Only immediate timers run (the first tick); the 2-minute and 15-minute re-reads are never due in a test.
    setTimeout: (f, ms) => { if (ms > 0) return 0; pending++; setImmediate(() => { pending--; f(); }); return 1; },
    clearTimeout() {},
  };
  ctx.window = { claude: { use: () => Promise.resolve(mcp) } };
  vm.createContext(ctx);
  vm.runInContext(src, ctx, { filename: pagePath });
  const settle = async () => { for (let i = 0; i < 200; i++) await new Promise((r) => setImmediate(r)); };
  await settle();
  const text = (id) => doc.getElementById(id).textContent;
  // The cards in a list: [{key, status}] from each card's summary row (the ref link and the status word).
  const cardsOf = (id) => doc.getElementById(id).find("crow").map((b) => ({ key: b.find("ref")[0]?.textContent, status: b.find("status")[0]?.textContent || "", text: b.parent.textContent }));
  // The desk asks in "Waiting on you": [{n, head, question, buttons, el}] from each ask card, in list order.
  const turnAsks = () => doc.getElementById("list").find("askcard").map((c) => ({ head: c.find("arow")[0].textContent, question: c.find("q")[0]?.textContent || "",
    buttons: c.all().filter((n) => n.tagName === "button").map((b) => b.textContent), el: c }));
  const click = (node) => (node.listeners.click || []).forEach((f) => f({ stopPropagation() {}, preventDefault() {}, target: node }));
  return { doc, calls, text, turnRows: () => cardsOf("list"), withSeats: () => cardsOf("tlist"), turnAsks, click, settle };
}

// pageFns(pagePath, fnNames, varNames): the named functions and `var NAME = …;` lines of the page's script, evaluated
// together in a fresh context, as {name: fn}. A function is cut from "function <name>(" to its matching brace.
export function pageFns(pagePath, fnNames, varNames = []) {
  const html = readFileSync(pagePath, "utf8");
  const src = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].pop()[1];
  const parts = varNames.map((v) => {
    const m = new RegExp("^\\s*var " + v + " = .*;$", "m").exec(src);
    if (!m) throw new Error(`${pagePath}: no line var ${v} = …;`);
    return m[0];
  });
  for (const f of fnNames) {
    const i = src.indexOf("function " + f + "(");
    if (i < 0) throw new Error(`${pagePath}: no function ${f}`);
    let d = 0, j = src.indexOf("{", i);
    for (; j < src.length; j++) { if (src[j] === "{") d++; else if (src[j] === "}" && --d === 0) break; }
    parts.push(src.slice(i, j + 1));
  }
  const ctx = { String, RegExp, Date, Object, Array, isNaN };
  vm.createContext(ctx);
  vm.runInContext(parts.join("\n") + "\n;globalThis.__f = {" + fnNames.join(",") + "};", ctx);
  return ctx.__f;
}
