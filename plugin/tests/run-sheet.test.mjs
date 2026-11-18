// The run sheet (plugin/scripts/build-run-sheet.mjs, plugin/templates/run-sheet/page.html): the validator's rules, the
// browser agent's prompt built from the same steps, the build, and the page's writes to its store. Each refusal is shown
// failing on a run that breaks it and passing on the sample.
//   node --test plugin/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";
import { validateRun, buildRunSheet, browserPrompt, verifyPage } from "../scripts/build-run-sheet.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const PAGE = join(here, "..", "templates", "run-sheet", "page.html");
const sample = () => JSON.parse(readFileSync(join(here, "..", "templates", "run-sheet", "fixtures", "sample-run.json"), "utf8"));
const block = (page, id) => JSON.parse(page.match(new RegExp('<script type="application/json" id="' + id + '">([\\s\\S]*?)</script>'))[1]);

test("the sample run is valid and builds into the artifact shape", () => {
  assert.deepEqual(validateRun(sample()), []);
  const page = buildRunSheet(sample());
  assert.ok(page.startsWith("<title>Verify a domain for outbound mail</title>"));
  assert.ok(!page.includes("/*__"));
  assert.ok(!/<!doctype|<html[\s>]|<head[\s>]|<body[\s>]/i.test(page));
  assert.equal(block(page, "run").steps.length, 4);
  assert.equal(block(page, "prompt"), browserPrompt(sample()));
  assert.deepEqual(verifyPage(page), []);
});

test("the run serves one row: anchor is <owner/repo>#<N> and fallback is that row's URL", () => {
  const r = sample(); r.anchor = "issue 12";
  assert.ok(validateRun(r).some((x) => x.includes("anchor must be the row it serves")));
  const r2 = sample(); r2.fallback = "https://github.com/acme/widgets/issues/13";
  assert.ok(validateRun(r2).some((x) => x.includes("fallback must be the row's own URL, https://github.com/acme/widgets/issues/12")));
  const r3 = sample(); delete r3.fallback;
  assert.ok(validateRun(r3).some((x) => x.includes("fallback must be the row's own URL")));
});

test("a run that changes something must start with a read step", () => {
  const r = sample(); r.steps.unshift(r.steps.splice(1, 1)[0]);
  assert.ok(validateRun(r).some((e) => e.includes("starts with a read step")));
});

test("ids and capture keys must be well formed and unique", () => {
  const r = sample(); r.steps[1].id = r.steps[0].id; r.steps[2].capture[0].key = "nameservers";
  const e = validateRun(r).join("\n");
  assert.match(e, /used twice/); assert.match(e, /capture key "nameservers" is used twice/);
  const r2 = sample(); r2.steps[0].capture[0].key = "Bad-Key";
  assert.ok(validateRun(r2).some((x) => x.includes("snake_case")));
});

test("a capture that would hold a secret is refused; its path or name is allowed", () => {
  for (const key of ["admin_password", "client_secret", "refresh_token", "recovery_codes", "private_key"]) {
    const r = sample(); r.steps[0].capture[0].key = key;
    assert.ok(validateRun(r).some((x) => x.includes("looks like a secret")), key);
  }
  for (const key of ["client_secret_file", "token_path", "credential_name", "passkey_status"]) {
    const r = sample(); r.steps[0].capture[0].key = key;
    assert.deepEqual(validateRun(r), [], key);
  }
});

test("links are https only (a loopback helper too is refused); a change step says what to do; stops and never are required", () => {
  for (const url of ["http://x.example.org", "http://127.0.0.1:8123/cb", "ftp://x.example.org", "https://"]) {
    const r = sample(); r.steps[0].where.url = url;
    assert.ok(validateRun(r).some((x) => x.includes("https link")), url);
  }
  const r = sample(); r.steps[1].do = []; r.stops = []; r.never = [];
  const e = validateRun(r).join("\n");
  assert.match(e, /must say exactly what to do/); assert.match(e, /stop condition/); assert.match(e, /must not be recorded/);
  assert.throws(() => buildRunSheet(r), /cannot be built/);
});

test("every step names where it is deployed (env), so a step not deployed is N/A, never failed", () => {
  for (const env of [undefined, "", "dev", "PROD", "live"]) {
    const r = sample(); if (env === undefined) delete r.steps[2].env; else r.steps[2].env = env;
    assert.ok(validateRun(r).some((x) => x.startsWith("Step 3: env must be \"prod\", \"branch\" or \"both\"")), String(env));
    assert.throws(() => buildRunSheet(r), /env must be/);
  }
  for (const env of ["prod", "branch", "both"]) { const r = sample(); r.steps[2].env = env; assert.deepEqual(validateRun(r), [], env); }
});

test("cost is required on every run; \"none\" is refused once a step is metered", () => {
  for (const cost of [undefined, "", "   "]) {
    const r = sample(); if (cost === undefined) delete r.cost; else r.cost = cost;
    assert.ok(validateRun(r).some((x) => x.startsWith("cost must say")), JSON.stringify(cost));
  }
  const metered = sample(); metered.cost = "none";
  assert.ok(validateRun(metered).some((x) => x.includes('cost is "none" but a step is metered')));
  const free = sample(); free.cost = "none"; delete free.steps[3].metered;
  assert.deepEqual(validateRun(free), []);
  const bad = sample(); bad.steps[3].metered = "yes";
  assert.ok(validateRun(bad).some((x) => x.includes("metered is true or absent")));
});

test("asks, expect and measured are well formed; measured needs the expect it is shown beside", () => {
  const r = sample(); r.steps[3].asks = [];
  assert.ok(validateRun(r).some((x) => x.includes("asks must be a non-empty list")));
  const r2 = sample(); r2.steps[2].measured = { text: "no date" };
  assert.ok(validateRun(r2).some((x) => x.includes("measured must be {at: YYYY-MM-DD, text}")));
  const r3 = sample(); delete r3.steps[2].expect;
  assert.ok(validateRun(r3).some((x) => x.includes("the step needs an expect")));
});

test("the browser prompt is built from the same steps: every title, address, ask and expectation, and the fixed guardrails", () => {
  const r = sample(), p = browserPrompt(r);
  r.steps.forEach((s, i) => {
    assert.ok(p.includes(`Step ${i + 1} of ${r.steps.length}: ${s.title}`), s.id);
    if (s.where) assert.ok(p.includes("Open: " + s.where.url), s.id);
    if (s.expect) assert.ok(p.includes("Should happen: " + s.expect), s.id);
    for (const q of s.asks || []) assert.ok(p.includes(`Ask: "${q}"`), s.id);
    for (const c of s.capture || []) assert.ok(p.includes("Record " + c.key + ":"), c.key);
  });
  for (const s of r.stops) assert.ok(p.includes("- " + s));
  assert.match(p, /I sign in myself: never sign in or sign out/);
  assert.match(p, /never open a site that is not written in the steps below/);
  assert.match(p, /quote the reply word for word/);
  assert.match(p, /Check every address/);
  assert.match(p, /Judge each step Pass, Partly or Fail/);
  assert.match(p, /BRANCH ONLY is not deployed on the live site: do not judge it; mark it N\/A/);
  assert.match(p, /\[BRANCH ONLY, not deployed on the live site\]/);
  assert.match(p, /End with a table: step, result/);
});

test("a page whose prompt drifted from its steps is refused", () => {
  const page = buildRunSheet(sample());
  // The run changed but the prompt was not rebuilt.
  const r = sample(); r.steps[2].expect = "example.org shows Verified at once.";
  const drifted = page.replace(/(<script type="application\/json" id="run">)[\s\S]*?(<\/script>)/, (_, a, b) => a + JSON.stringify(r).replace(/</g, "\\u003c") + b);
  assert.ok(verifyPage(drifted).some((x) => x.includes("does not match its steps")));
  // The prompt was edited by hand.
  const edited = page.replace(/(<script type="application\/json" id="prompt">)([\s\S]*?)(<\/script>)/, (_, a, p, b) => a + JSON.stringify(JSON.parse(p).replace("Should happen: example.org shows Verified within two minutes", "Should happen: anything")) + b);
  assert.ok(verifyPage(edited).some((x) => x.includes("does not match its steps")));
  // A page without a prompt, and a page whose run is no longer valid.
  assert.ok(verifyPage(page.replace(/<script type="application\/json" id="prompt">[\s\S]*?<\/script>/, "")).some((x) => x.includes('no "prompt" block')));
  const noEnv = sample(); delete noEnv.steps[0].env;
  assert.ok(verifyPage(page.replace(/(<script type="application\/json" id="run">)[\s\S]*?(<\/script>)/, (_, a, b) => a + JSON.stringify(noEnv) + b)).some((x) => x.includes("env must be")));
});

test("text in a run cannot break out of the page", () => {
  const r = sample(); r.title = "A </title><script>x</script>"; r.goal = ["</script><b>"]; r.steps[3].asks = ["</script><i>"];
  const page = buildRunSheet(r);
  assert.ok(page.startsWith("<title>A &lt;/title&gt;&lt;script&gt;x&lt;/script&gt;</title>"));
  assert.equal(page.split("</script>").length - 1, 3);
  assert.deepEqual(verifyPage(page), []);
});

test("the evidence store has one seam: the page's own artifact store today, any other store fails loud", () => {
  const src = readFileSync(PAGE, "utf8");
  assert.equal((src.match(/var EVIDENCE_STORE = 'artifact-db';/g) || []).length, 1);
  assert.equal((src.match(/function openEvidenceStore\(\)/g) || []).length, 1);
  assert.match(src, /if\(EVIDENCE_STORE !== 'artifact-db'\) return Promise\.reject\(new Error\('unknown evidence store '/);
  // The store is opened only through the seam: no other call reaches the runtime's store.
  assert.equal((src.match(/window\.claude\.use\(/g) || []).length, 1);
  assert.equal((src.match(/db\.collection\('runs\/' \+ run\.id \+ '\/results'\)/g) || []).length, 1);
  // Every write is a whole-document set() built by docFor; there is no partial update().
  assert.equal((src.match(/\.set\(/g) || []).length, 1);
  assert.match(src, /col\.doc\(docId\)\.set\(docFor\(docId\)\)/);
  assert.ok(!/\.update\(/.test(src));
});

// ---- the page run in node, against a stub store that records every set() ----
class El {
  constructor(tag, doc) { this.tagName = tag.toUpperCase(); this.doc = doc; this.kids = []; this.parent = null; this.attrs = {}; this.dataset = {}; this.className = ""; this.value = ""; this.hidden = false; this.listeners = {}; this._t = ""; }
  setAttribute(k, v) { v = String(v); this.attrs[k] = v; if (k === "id") this.doc.ids.set(v, this); if (k.startsWith("data-")) this.dataset[k.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = v; }
  getAttribute(k) { return this.attrs[k] ?? null; }
  get id() { return this.attrs.id || ""; }
  append(...cs) { for (const c of cs) { const n = typeof c === "string" ? Object.assign(new El("#text", this.doc), { _t: c }) : c; n.parent = this; this.kids.push(n); } }
  set textContent(v) { this.kids = []; this._t = String(v); }
  get textContent() { return this._t + this.kids.map((k) => k.textContent).join(""); }
  addEventListener(k, f) { (this.listeners[k] = this.listeners[k] || []).push(f); }
  closest(tag) { for (let n = this; n; n = n.parent) if (n.tagName === tag.toUpperCase()) return n; return null; }
  all() { return [this, ...this.kids.flatMap((k) => k.all())]; }
  focus() {} select() {}
}
function loadSheet(run, { failSet = false } = {}) {
  const page = buildRunSheet(run), doc = { ids: new Map(), listeners: {}, activeElement: null };
  for (const [, id, body] of page.matchAll(/<script type="application\/json" id="(\w+)">([\s\S]*?)<\/script>/g)) Object.assign(new El("script", doc), { _t: body }).setAttribute("id", id);
  for (const id of ["title", "sub", "cost", "prompt-text", "copy-prompt", "copied-prompt", "goal", "checked", "checked-box", "stops", "never", "fallback", "steps", "overall", "out", "copy", "copied", "tally", "saved", "verdict-bar"]) new El("div", doc).setAttribute("id", id);
  const roots = () => [...doc.ids.values()].filter((n) => !n.parent);
  Object.assign(doc, {
    getElementById: (id) => doc.ids.get(id) || null,
    createElement: (t) => new El(t, doc),
    addEventListener: (k, f) => { (doc.listeners[k] = doc.listeners[k] || []).push(f); },
    querySelectorAll: (sel) => {
      const m = /^\[data-([a-z-]+)(?:="([^"]*)")?\]$/.exec(sel); if (!m) throw new Error("selector " + sel);
      const key = m[1].replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      return roots().flatMap((r) => r.all()).filter((n) => key in n.dataset && (m[2] === undefined || n.dataset[key] === m[2]));
    },
  });
  const sets = [], timers = new Map(), subs = [];
  let seq = 0;
  const col = { doc: (id) => ({ set: (body) => { sets.push({ id, body: JSON.parse(JSON.stringify(body)) }); return failSet ? Promise.reject(new Error("refused")) : Promise.resolve(); } }), onSnapshot: (next) => { subs.push(next); } };
  const db = { collection: (path) => { db.path = path; return col; } };
  const ctx = vm.createContext({ document: doc, JSON, Object, String, Date, Promise, Error, console,
    setTimeout: (f) => { timers.set(++seq, f); return seq; }, clearTimeout: (i) => { timers.delete(i); },
    localStorage: { getItem: () => null, setItem: () => { throw new Error("no storage"); } },
    window: { claude: { use: (name) => Promise.resolve(name === "db" ? db : null) } } });
  vm.runInContext(page.match(/<script>([\s\S]*?)<\/script>/)[1], ctx);
  const fire = (type, target) => doc.listeners[type].forEach((f) => f({ target }));
  const tick = async () => { for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r)); };
  // Runs every pending timer and the promises they start (the 10-second "no store" fallback is cleared by the first snapshot).
  const runTimers = async () => { await tick(); while (timers.size) { const fs = [...timers.values()]; timers.clear(); fs.forEach((f) => f()); await tick(); } };
  return { doc, sets, db, subs, fire, tick, runTimers, q: doc.querySelectorAll };
}

test("the page writes one whole document per step, plus overall and verdict, under runs/<id>/results", async () => {
  const run = sample(), s = loadSheet(run);
  await s.tick();
  assert.equal(s.db.path, "runs/" + run.id + "/results");
  s.subs[0]({ docs: [], empty: true });
  // A capture typed into step 1, then step 1 marked Pass: each write carries the whole step document.
  const cap = s.q('[data-key="nameservers"]')[0]; cap.value = "ns1.example.org"; s.fire("input", cap);
  await s.runTimers();
  s.fire("click", s.q('[data-step="1"]').find((b) => b.dataset.v === "pass"));
  await s.runTimers();
  const step1 = s.sets.filter((x) => x.id === "step-1");
  assert.equal(step1.length, 2);
  for (const w of step1) assert.deepEqual(Object.keys(w.body).sort(), ["at", "id", "n", "note", "results", "status"]);
  assert.deepEqual(step1[1].body.results, { nameservers: "ns1.example.org" }, "the second write keeps the capture the first wrote");
  assert.equal(step1[1].body.status, "pass"); assert.equal(step1[1].body.id, "read-records"); assert.equal(step1[1].body.n, 1);
  // Step 4 (branch only) marked N/A, an overall note, and the verdict.
  s.fire("click", s.q('[data-step="4"]').find((b) => b.dataset.v === "na"));
  const ov = s.doc.getElementById("overall"); ov.value = "table pasted"; s.fire("input", ov);
  s.fire("click", s.q('[data-verdict="not-yet"]')[0]);
  await s.runTimers();
  const last = (id) => s.sets.filter((x) => x.id === id).pop().body;
  assert.equal(last("step-4").status, "na");
  assert.deepEqual(Object.keys(last("overall")).sort(), ["at", "text"]); assert.equal(last("overall").text, "table pasted");
  assert.deepEqual(Object.keys(last("verdict")).sort(), ["at", "verdict"]); assert.equal(last("verdict").verdict, "not-yet");
  assert.deepEqual([...new Set(s.sets.map((x) => x.id))].sort(), ["overall", "step-1", "step-4", "verdict"]);
  assert.deepEqual(s.q("[data-verdict]").map((b) => b.dataset.verdict), ["accept", "not-yet", "roll-back"]);
});

test("the page reads results back from the store, and refuses a saved step whose id moved", async () => {
  const run = sample(), s = loadSheet(run);
  await s.tick();
  s.subs[0]({ empty: false, docs: [
    { id: "step-2", exists: true, data: () => ({ n: 2, id: "add-record", status: "fail", note: "saw x", results: { record_saved_as: "TXT @" }, at: "2026-11-17T00:00:00Z" }) },
    { id: "step-3", exists: true, data: () => ({ n: 3, id: "some-old-step", status: "pass", note: "", results: {}, at: "2026-11-17T00:00:00Z" }) },
    { id: "verdict", exists: true, data: () => ({ verdict: "accept", at: "2026-11-17T00:00:00Z" }) },
  ] });
  assert.equal(s.doc.getElementById("note-2").value, "saw x");
  assert.equal(s.q('[data-key="record_saved_as"]')[0].value, "TXT @");
  assert.equal(s.q('[data-step="2"]').find((b) => b.dataset.v === "fail").getAttribute("aria-pressed"), "true");
  assert.equal(s.q('[data-step="3"]').find((b) => b.dataset.v === "pass").getAttribute("aria-pressed"), "false");
  assert.match(s.doc.getElementById("saved").textContent, /step 3 belong to a step that moved/);
  assert.equal(s.q('[data-verdict="accept"]')[0].getAttribute("aria-pressed"), "true");
  assert.equal(s.sets.length, 0, "reading writes nothing");
});
