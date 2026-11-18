#!/usr/bin/env node
// build-run-sheet.mjs — a run (JSON) into one self-contained run-sheet page, in the shape the Artifact tool publishes
// (plugin/templates/run-sheet/page.html, filled). One component serves a hands row (the act only the decider can perform
// in a browser) and a decider's acceptance walk (steps to try on a live site, each judged against what should happen);
// the stage-hands skill says how a seat publishes it, hands the browser agent its prompt, and reads the results back.
//   node build-run-sheet.mjs run.json --out page.html [--standalone]
//   node build-run-sheet.mjs --check page.html            (the page's embedded prompt still matches its embedded run)
// The run's shape (validateRun is its one owner and refuses anything else):
//   run  = {id, title, anchor, fallback, cost: sentence, minutes?, goal: [sentence], checked?: [sentence],
//           stops: [sentence], never: [sentence], steps: [step]}
//   step = {id, title, kind: "read"|"change", env: "prod"|"branch"|"both", where?: {url, account?}, hands?: true|sentence,
//           do?: [sentence], asks?: [sentence], rule?: sentence, expect?: sentence, measured?: {at: "YYYY-MM-DD", text},
//           metered?: true, capture?: [{key, label, shape?, multiline?: false, rows?}]}
// anchor is the row it serves, <owner/repo>#<N>; fallback is that row's own URL (https://github.com/<owner>/<repo>/
// issues/<N>), where the results are posted as one comment when the page cannot be typed into. Every link is https.
// cost is the walk's expected spend (AI credits or anything else), "none" when it costs nothing; a step with
// metered: true drives a metered surface, and a run with one may not say "none".
// env says where the step's behaviour is deployed: "prod" (on the live site), "branch" (only on an unmerged branch, so on
// the live site it is marked N/A, not failed) or "both" (live, with a branch-only part the step's text names).
// asks are the exact words to type into the site (a chat question); expect is what should happen, and measured the
// last machine measurement of it, shown beside expect so the decider sees the delta.
// A capture key that looks like a secret is refused unless it names a path, file, name, id, status or count. A run
// names a team's systems, so a real run and its built page live in that team's private repo, never in the plugin.
// browserPrompt(run) is the one writer of the browser agent's prompt, from the same steps; the page embeds it, and
// verifyPage refuses a page whose prompt no longer matches its run.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const PLUGIN = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const TEMPLATE = join(PLUGIN, "templates", "run-sheet", "page.html");
const embed = (v) => JSON.stringify(v).replace(/</g, "\\u003c");
const esc = (s) => String(s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]);
const SECRETISH = /pass(word|code|key)?s?\b|secret|token|recovery|private.?key|credential/i;
const ANCHOR_RE = /^([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)#([0-9]+)$/;
export const ENVS = { prod: "PROD", branch: "BRANCH ONLY, not deployed on the live site", both: "PROD, with a branch-only part" };
const text = (v) => typeof v === "string" && v.trim() !== "";
const texts = (v) => Array.isArray(v) && v.every(text);

/** The problems with a run, as sentences. An empty list means it can be built. */
export function validateRun(run) {
  const e = [], idOk = (s) => typeof s === "string" && /^[a-z0-9][a-z0-9-]*$/.test(s);
  if (!run || typeof run !== "object") return ["The run is not an object."];
  if (!idOk(run.id)) e.push("id must be lowercase letters, digits and hyphens.");
  if (!run.title) e.push("title is missing.");
  const a = ANCHOR_RE.exec(run.anchor || "");
  if (!a) e.push("anchor must be the row it serves, <owner/repo>#<N>.");
  else if (run.fallback !== `https://github.com/${a[1]}/${a[2]}/issues/${a[3]}`) e.push(`fallback must be the row's own URL, https://github.com/${a[1]}/${a[2]}/issues/${a[3]}.`);
  if (!text(run.cost)) e.push('cost must say what the walk is expected to spend (AI credits or anything else), or "none".');
  if (!Array.isArray(run.goal) || !run.goal.length) e.push("goal needs at least one sentence.");
  if (!Array.isArray(run.stops) || !run.stops.length) e.push("stops needs at least one stop condition.");
  if (!Array.isArray(run.never) || !run.never.length) e.push("never needs at least one thing that must not be recorded.");
  if (!Array.isArray(run.steps) || !run.steps.length) return [...e, "steps is empty."];
  const ids = new Set(), keys = new Set();
  let seenChange = false, metered = false;
  run.steps.forEach((s, i) => {
    const at = "Step " + (i + 1) + ": ";
    if (!idOk(s.id)) e.push(at + "id must be lowercase letters, digits and hyphens.");
    else if (ids.has(s.id)) e.push(at + 'id "' + s.id + '" is used twice.');
    else ids.add(s.id);
    if (!s.title) e.push(at + "title is missing.");
    if (!["read", "change"].includes(s.kind)) e.push(at + 'kind must be "read" or "change".');
    if (!Object.hasOwn(ENVS, s.env)) e.push(at + 'env must be "prod", "branch" or "both": where the step\'s behaviour is deployed.');
    if (s.kind === "change") seenChange = true;
    if (s.kind === "change" && !(s.do && s.do.length)) e.push(at + "a change step must say exactly what to do.");
    if (s.do !== undefined && !texts(s.do)) e.push(at + "do must be a list of sentences.");
    if (s.asks !== undefined && !(texts(s.asks) && s.asks.length)) e.push(at + "asks must be a non-empty list of the exact words to type.");
    if (s.expect !== undefined && !text(s.expect)) e.push(at + "expect must be a sentence.");
    if (s.measured !== undefined) {
      if (!s.measured || !/^\d{4}-\d{2}-\d{2}$/.test(s.measured.at || "") || !text(s.measured.text)) e.push(at + "measured must be {at: YYYY-MM-DD, text}.");
      if (!text(s.expect)) e.push(at + "measured is shown beside expect: the step needs an expect.");
    }
    if (s.metered !== undefined && s.metered !== true) e.push(at + "metered is true or absent.");
    if (s.metered === true) metered = true;
    if (s.where && !/^https:\/\/\S+$/.test(s.where.url || "")) e.push(at + "where.url must be an https link.");
    for (const c of s.capture || []) {
      if (!/^[a-z][a-z0-9_]*$/.test(c.key || "")) e.push(at + 'capture key "' + c.key + '" must be snake_case.');
      else if (keys.has(c.key)) e.push(at + 'capture key "' + c.key + '" is used twice.');
      else keys.add(c.key);
      if (!c.label) e.push(at + 'capture "' + c.key + '" needs a label.');
      if (SECRETISH.test(c.key) && !/(_path|_file|_name|_id|_status|_count)$/.test(c.key)) e.push(at + 'capture key "' + c.key + '" looks like a secret. Capture a file path or a name, never the value.');
    }
  });
  if (metered && text(run.cost) && /^none\b/i.test(run.cost.trim())) e.push('cost is "none" but a step is metered: say what the walk is expected to spend.');
  if (seenChange && run.steps[0].kind !== "read") e.push("A run that changes something starts with a read step.");
  return e;
}

/** The prompt the decider pastes into their browser agent (Claude in Chrome), from the run's own steps. */
export function browserPrompt(run) {
  const L = [
    `You are walking "${run.title}" with me in this browser, one step at a time. I have signed in to the sites myself.`,
    "",
    "Rules:",
    "- I sign in myself: never sign in or sign out. Never change a setting unless a CHANGE step below says exactly what to enter, and never open a site that is not written in the steps below.",
    "- Work through the steps in order. A step marked HANDS needs me: stop, tell me exactly what to do, and wait until I say it is done.",
    "- A CHANGE step alters something: enter the values exactly as written and nothing else. Every other step only looks.",
    "- When the site replies (a chat answer, a message, an error), quote the reply word for word.",
    "- Check every address: each link you are given and each link in a reply. Say whether it opens the right place.",
    "- A step tagged BRANCH ONLY is not deployed on the live site: do not judge it; mark it N/A and say what you saw. A step tagged PROD, with a branch-only part: judge the live part only.",
    "- Judge each step Pass, Partly or Fail against its 'Should happen' (a step without one: against doing it as written), with a one-line reason. If you cannot go on, mark it Blocked and stop. Where a step's rule says so, mark it Skipped by rule.",
    "- Report each 'Record' item as key: value.",
    "- Never write down a password, sign-in code, token, key or other secret.",
    "",
    "Stop and report what you saw if:",
    ...run.stops.map((s) => "- " + s),
    "",
    "Never record:",
    ...run.never.map((s) => "- " + s),
    "",
  ];
  run.steps.forEach((s, i) => {
    const tags = [ENVS[s.env], s.kind === "change" ? "CHANGE" : null, s.hands ? "HANDS" : null].filter(Boolean).join(" · ");
    L.push(`Step ${i + 1} of ${run.steps.length}: ${s.title} [${tags}]`);
    if (s.where) L.push(`  Open: ${s.where.url}` + (s.where.account ? ` (signed in as ${s.where.account})` : ""));
    if (s.hands) L.push(`  HANDS: ${s.hands === true ? "stop here: I act at this step." : s.hands} Stop and wait for me.`);
    for (const d of s.do || []) L.push(`  Do: ${d}`);
    for (const q of s.asks || []) L.push(`  Ask: "${q}"`);
    if (s.rule) L.push(`  Rule: ${s.rule}`);
    if (s.expect) L.push(`  Should happen: ${s.expect}`);
    for (const c of s.capture || []) L.push(`  Record ${c.key}: ${c.label}` + (c.shape ? ` (${c.shape})` : ""));
    L.push("");
  });
  L.push("End with a table: step, result (Pass / Partly / Fail / N/A / Blocked / Skipped by rule), one-line reason.");
  return L.join("\n");
}

export function buildRunSheet(run) {
  const errs = validateRun(run);
  if (errs.length) throw new Error("The run cannot be built:\n- " + errs.join("\n- "));
  let page = readFileSync(TEMPLATE, "utf8");
  for (const [k, v] of [["/*__TITLE__*/", esc(run.title)], ["/*__RUN__*/", embed(run)], ["/*__PROMPT__*/", embed(browserPrompt(run))]]) {
    if (!page.includes(k)) throw new Error(TEMPLATE + " lacks " + k);
    page = page.replace(k, () => v);
  }
  return page;
}

/** The problems with a built page: its run must still be valid and its prompt must be browserPrompt(run). */
export function verifyPage(page) {
  const pick = (id) => {
    const m = page.match(new RegExp('<script type="application/json" id="' + id + '">([\\s\\S]*?)</script>'));
    if (!m) throw new Error('the page has no "' + id + '" block');
    return JSON.parse(m[1]);
  };
  let run, prompt;
  try { run = pick("run"); prompt = pick("prompt"); } catch (err) { return ["The page cannot be read: " + err.message + "."]; }
  const e = validateRun(run);
  if (!e.length && prompt !== browserPrompt(run)) e.push("The page's browser prompt does not match its steps: rebuild the page from the run.");
  return e;
}

export const standalone = (page) => '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><style>body{margin:0}[hidden]{display:none!important}</style></head><body>\n' + page + "</body></html>\n";

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args[0] === "--check") {
    if (!args[1]) { console.error("usage: build-run-sheet.mjs --check page.html"); process.exit(2); }
    const errs = verifyPage(readFileSync(args[1], "utf8"));
    if (errs.length) { console.error("daita-beast: " + args[1] + ":\n- " + errs.join("\n- ")); process.exit(1); }
    console.log("ok " + args[1]);
    process.exit(0);
  }
  const [src, ...rest] = args, i = rest.indexOf("--out"), out = i >= 0 ? rest[i + 1] : null;
  if (!src || !out) { console.error("usage: build-run-sheet.mjs run.json --out page.html [--standalone]"); process.exit(2); }
  try {
    const page = buildRunSheet(JSON.parse(readFileSync(src, "utf8")));
    writeFileSync(out, rest.includes("--standalone") ? standalone(page) : page);
    console.log("wrote " + out);
  } catch (err) { console.error("daita-beast: " + err.message); process.exit(1); }
}
