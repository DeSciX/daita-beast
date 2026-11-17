#!/usr/bin/env node
// build-run-sheet.mjs — a run (JSON) for a hands row into one self-contained run-sheet page, in the shape the Artifact
// tool publishes (plugin/templates/run-sheet/page.html, filled; the stage-hands skill says how a seat publishes it and
// links it on the row with decision.sh new|revise --run-sheet).
//   node build-run-sheet.mjs run.json --out page.html [--standalone]
// The run's shape (validateRun is its one owner and refuses anything else):
//   run  = {id, title, anchor, fallback, minutes?, goal: [sentence], checked?: [sentence], stops: [sentence],
//           never: [sentence], steps: [step]}
//   step = {id, title, kind: "read"|"change", where?: {url, account?}, hands?: true|sentence, do?: [sentence],
//           rule?: sentence, capture?: [{key, label, shape?, multiline?: false, rows?}]}
// anchor is the hands row it serves, <owner/repo>#<N>; fallback is that row's own URL (https://github.com/<owner>/<repo>/
// issues/<N>), where the results are posted as one comment when the page cannot be typed into. Every link is https.
// A capture key that looks like a secret is refused unless it names a path, file, name, id, status or count. A run
// names a team's systems, so a real run and its built page live in that team's private repo, never in the plugin.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const PLUGIN = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const TEMPLATE = join(PLUGIN, "templates", "run-sheet", "page.html");
const embed = (v) => JSON.stringify(v).replace(/</g, "\\u003c");
const esc = (s) => String(s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]);
const SECRETISH = /pass(word|code|key)?s?\b|secret|token|recovery|private.?key|credential/i;
const ANCHOR_RE = /^([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)#([0-9]+)$/;

/** The problems with a run, as sentences. An empty list means it can be built. */
export function validateRun(run) {
  const e = [], idOk = (s) => typeof s === "string" && /^[a-z0-9][a-z0-9-]*$/.test(s);
  if (!run || typeof run !== "object") return ["The run is not an object."];
  if (!idOk(run.id)) e.push("id must be lowercase letters, digits and hyphens.");
  if (!run.title) e.push("title is missing.");
  const a = ANCHOR_RE.exec(run.anchor || "");
  if (!a) e.push("anchor must be the hands row it serves, <owner/repo>#<N>.");
  else if (run.fallback !== `https://github.com/${a[1]}/${a[2]}/issues/${a[3]}`) e.push(`fallback must be the row's own URL, https://github.com/${a[1]}/${a[2]}/issues/${a[3]}.`);
  if (!Array.isArray(run.goal) || !run.goal.length) e.push("goal needs at least one sentence.");
  if (!Array.isArray(run.stops) || !run.stops.length) e.push("stops needs at least one stop condition.");
  if (!Array.isArray(run.never) || !run.never.length) e.push("never needs at least one thing that must not be recorded.");
  if (!Array.isArray(run.steps) || !run.steps.length) return [...e, "steps is empty."];
  const ids = new Set(), keys = new Set();
  let seenChange = false;
  run.steps.forEach((s, i) => {
    const at = "Step " + (i + 1) + ": ";
    if (!idOk(s.id)) e.push(at + "id must be lowercase letters, digits and hyphens.");
    else if (ids.has(s.id)) e.push(at + 'id "' + s.id + '" is used twice.');
    else ids.add(s.id);
    if (!s.title) e.push(at + "title is missing.");
    if (!["read", "change"].includes(s.kind)) e.push(at + 'kind must be "read" or "change".');
    if (s.kind === "change") seenChange = true;
    if (s.kind === "change" && !(s.do && s.do.length)) e.push(at + "a change step must say exactly what to do.");
    if (s.where && !/^https:\/\/\S+$/.test(s.where.url || "")) e.push(at + "where.url must be an https link.");
    for (const c of s.capture || []) {
      if (!/^[a-z][a-z0-9_]*$/.test(c.key || "")) e.push(at + 'capture key "' + c.key + '" must be snake_case.');
      else if (keys.has(c.key)) e.push(at + 'capture key "' + c.key + '" is used twice.');
      else keys.add(c.key);
      if (!c.label) e.push(at + 'capture "' + c.key + '" needs a label.');
      if (SECRETISH.test(c.key) && !/(_path|_file|_name|_id|_status|_count)$/.test(c.key)) e.push(at + 'capture key "' + c.key + '" looks like a secret. Capture a file path or a name, never the value.');
    }
  });
  if (seenChange && run.steps[0].kind !== "read") e.push("A run that changes something starts with a read step.");
  return e;
}

export function buildRunSheet(run) {
  const errs = validateRun(run);
  if (errs.length) throw new Error("The run cannot be built:\n- " + errs.join("\n- "));
  let page = readFileSync(TEMPLATE, "utf8");
  for (const [k, v] of [["/*__TITLE__*/", esc(run.title)], ["/*__RUN__*/", embed(run)]]) {
    if (!page.includes(k)) throw new Error(TEMPLATE + " lacks " + k);
    page = page.replace(k, () => v);
  }
  return page;
}

export const standalone = (page) => '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><style>body{margin:0}[hidden]{display:none!important}</style></head><body>\n' + page + "</body></html>\n";

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [src, ...rest] = process.argv.slice(2), i = rest.indexOf("--out"), out = i >= 0 ? rest[i + 1] : null;
  if (!src || !out) { console.error("usage: build-run-sheet.mjs run.json --out page.html [--standalone]"); process.exit(2); }
  try {
    const page = buildRunSheet(JSON.parse(readFileSync(src, "utf8")));
    writeFileSync(out, rest.includes("--standalone") ? standalone(page) : page);
    console.log("wrote " + out);
  } catch (err) { console.error("daita-beast: " + err.message); process.exit(1); }
}
