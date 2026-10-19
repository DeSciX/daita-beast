// The page (plugin/templates/board.html) parses desk asks with JS twins of the shapes lib.sh owns. This test extracts
// both sides from the source files as they stand and runs them on one fixture list of lines: lib.sh's through jq (the
// engine desk_parse uses), the page's through node. Any line the two read differently fails the test, naming it.
//   node --test plugin/tests/
// Needs jq on PATH (the plugin needs it anyway).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const LIB = process.env.BEAST_TEST_LIB || join(here, "..", "scripts", "lib.sh");
const PAGE = process.env.BEAST_TEST_PAGE || join(here, "..", "templates", "board.html");

// lib.sh: NAME='<regex>' on one line (single-quoted, no embedded quote).
function libRe(name) {
  const m = new RegExp("^" + name + "='([^']*)'$", "m").exec(readFileSync(LIB, "utf8"));
  assert.ok(m, `${LIB} has no line ${name}='<regex>'`);
  return m[1];
}
// board.html: var NAME = /<regex>/<flags>;
function pageRe(name) {
  const m = new RegExp("var " + name + " = (/(?:\\\\/|[^/\\n])+/[a-z]*);").exec(readFileSync(PAGE, "utf8"));
  assert.ok(m, `${PAGE} has no line var ${name} = /<regex>/;`);
  return (0, eval)(m[1]);
}

// Both sides read a line right-trimmed (desk_parse: sub("\\s+$"; ""); parseDesk: replace(/\s+$/, "")).
const rtrim = (s) => s.replace(/\s+$/, "");

// jq's capture of each line with the lib regex: null when it does not match, else the named groups.
function jqCaptures(re, lines) {
  const out = execFileSync("jq", ["-c", "--arg", "re", re, ".[] | (capture($re) // null)"], {
    input: JSON.stringify(lines.map(rtrim)),
    encoding: "utf8",
  });
  return out.trim().split("\n").map((l) => JSON.parse(l));
}

// The protocol prefix is assembled, so no line of this file is itself a filled-in coordination line.
const P = "BEAST" + "-";
const ASK_LINES = [
  `${P}ASK n=1 seat=acme/BEAST at=2026-10-16T10:00:00Z`,
  `${P}ASK n=12 seat=acme/PLAN-2 at=2026-10-16T10:00:00Z milestone="M4 wrap-up"`,
  `${P}ASK n=3 seat=BEAST at=2026-10-16T10:00:00Z`,
  `${P}ASK n=4 seat=acme/BEAST at=2026-10-16T10:00:00Z   `,
  `${P}ASK n=5 seat=acme/BEAST at=2026-10-16T10:00:00Z milestone="M5 public release" `,
  `${P}ASK n=6 seat=acme/beast at=2026-10-16T10:00:00Z`,
  `${P}ASK n=7 seat=acme/BEAST.x at=2026-10-16T10:00:00Z`,
  `${P}ASK n=8 seat=some.one/BEAST at=2026-10-16T10:00:00Z`,
  `${P}ASK n=9 seat=acme/BEAST at=2026-10-16T10:00:00Z milestone=""`,
  `${P}ASK n=10 seat=acme/BEAST at=2026-10-16T10:00:00Z milestone=M4`,
  `${P}ASK n=x seat=acme/BEAST at=2026-10-16T10:00:00Z`,
  `${P}ASK n=11 seat=acme/BEAST`,
  `${P}ASK  n=13 seat=acme/BEAST at=2026-10-16T10:00:00Z`,
  `${P}ASK n=14 seat=acme/BEAST at=2026-10-16T10:00:00Z extra`,
  `${P}ASKX n=15 seat=acme/BEAST at=2026-10-16T10:00:00Z`,
  `${P}ASK n=16 seat=a/b/C at=2026-10-16T10:00:00Z`,
];

const WAITS_LINES = [
  "Waits on: acme/BEAST",
  "Waits on: acme/widget-app#37",
  "Waits on: Example-Org/site#1  ",
  "Waits on: some.org/repo_x.y#9",
  "Waits on: BEAST",
  "Waits on: acme/beast",
  "Waits on: acme/widget-app",
  "Waits on: acme/widget-app#",
  "Waits on: acme/widget-app#37 and more",
  "Waits on:acme/BEAST",
  "waits on: acme/BEAST",
  "Waits on: https://github.com/acme/widget-app/issues/37",
  "Waits on: acme/BE AST",
];

const T = "at=2026-10-16T10:00:00Z";
const MSG_LINES = [
  `${P}MSG from=beast/BEAST/acme to=platform/DEVPLANE/acme re=none blocking=no ${T}`,
  `${P}MSG from=beast/BEAST/acme to=platform/DEVPLANE/acme re=acme/twin#12 blocking=no ${T}`,
  `${P}MSG from=beast/BEAST/acme to=platform/DEVPLANE/acme re=https://github.com/acme/twin/pull/3 blocking=no ${T}  `,
  `${P}MSG from=acme/BEAST to=acme/DEVPLANE re=none blocking=no ${T}`,
  `${P}MSG from=beast/BEAST/acme to=platform/DEVPLANE/acme ${T}`,
  `${P}MSG from=beast/BEAST/acme to=platform/DEVPLANE/acme re=none blocking=no`,
  `${P}MSG from=beast/BEAST/acme to=platform/DEVPLANE/acme re=none blocking=yes ${T}`,
  `${P}MSG from=beast/BEAST/acme to=platform/DEVPLANE/acme re= blocking=no ${T}`,
  `${P}MSG from=Beast/BEAST/acme to=platform/DEVPLANE/acme re=none blocking=no ${T}`,
  `${P}MSG from=beast/beast/acme to=platform/DEVPLANE/acme re=none blocking=no ${T}`,
  `${P}MSG from=beast/BEAST/acme to=platform/DEVPLANE/acme re=none blocking=no ${T} extra`,
];

// compare <lib regex name> <page regex name> <lines> <group names in the page's capture order>
function compare(libName, pageName, lines, groups) {
  const libCap = jqCaptures(libRe(libName), lines);
  const page = pageRe(pageName);
  const diffs = [];
  lines.forEach((line, i) => {
    const m = page.exec(rtrim(line));
    const pageCap = m ? Object.fromEntries(groups.map((g, k) => [g, m[k + 1] ?? null])) : null;
    const l = libCap[i] ? Object.fromEntries(groups.map((g) => [g, libCap[i][g] ?? null])) : null;
    // jq yields "" for an optional group that did not take part; the page yields undefined: both mean absent.
    const norm = (o) => (o ? Object.fromEntries(Object.entries(o).map(([k, v]) => [k, v === "" ? null : v])) : null);
    if (JSON.stringify(norm(l)) !== JSON.stringify(norm(pageCap)))
      diffs.push(`  ${JSON.stringify(line)}\n    lib.sh ${libName}: ${JSON.stringify(l)}\n    page   ${pageName}: ${JSON.stringify(pageCap)}`);
  });
  assert.equal(diffs.length, 0, `lib.sh ${libName} and the page's ${pageName} read ${diffs.length} line(s) differently:\n${diffs.join("\n")}`);
}

test("the ask header: lib.sh ASK_HEADER_RE and the page's ASK_RE read every fixture line alike", () => {
  compare("ASK_HEADER_RE", "ASK_RE", ASK_LINES, ["n", "seat", "at", "ms"]);
});

test("waits-on: lib.sh WAITS_ON_RE and the page's WAITS_RE read every fixture line alike", () => {
  compare("WAITS_ON_RE", "WAITS_RE", WAITS_LINES, ["ref"]);
});

test("the seat-to-seat tag: lib.sh MSG_HEADER_RE and the page's MSG_RE read every fixture line alike", () => {
  compare("MSG_HEADER_RE", "MSG_RE", MSG_LINES, ["from", "to", "re", "at"]);
});

test("the fixtures exercise both outcomes on both shapes", () => {
  for (const [name, lines] of [["ASK_HEADER_RE", ASK_LINES], ["WAITS_ON_RE", WAITS_LINES], ["MSG_HEADER_RE", MSG_LINES]]) {
    const caps = jqCaptures(libRe(name), lines);
    assert.ok(caps.some((c) => c) && caps.some((c) => !c), `${name}: the fixtures must hold lines that match and lines that do not`);
  }
});
