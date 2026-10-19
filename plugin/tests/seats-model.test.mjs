// The seat model's pure parsers and identity forms (lib.sh), run through bash with no network: the `## Seats`
// table parser (one shape, dies naming the line), the home word, the identity forms (LABEL, login/LABEL,
// slug/LABEL/login resolve to one row of a fixture roster), the roster row check (role/tracking deleted, agent and
// workstream required, no peer rows), section_replace and block_replace.
//   node --test plugin/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const LIB = process.env.BEAST_TEST_LIB || join(here, "..", "scripts", "lib.sh");

// A fixture checkout: a git repo with an origin and a roster of this model's shape.
const W = mkdtempSync(join(tmpdir(), "beast-model-"));
const R = join(W, "twin");
mkdirSync(join(R, ".beast"), { recursive: true });
execFileSync("git", ["-C", R, "init", "-q"]);
execFileSync("git", ["-C", R, "remote", "add", "origin", "https://github.com/acme/twin.git"]);
const roster = (seats) => ({ repo: "acme/twin", board: "acme/twin", seats, people: [{ github: "alice", name: "Alice", role: "owner" }] });
const ROW = { label: "BEAST", github: "alice", repo: "acme/twin", lane: "app", agent: "daita-beast:seat", workstream: "beast", home: { kind: "checkout", branch: null } };
writeFileSync(join(R, ".beast", "roster.json"), JSON.stringify(roster([ROW])));

// sh(cmd): run a lib.sh call in the fixture checkout; {out, err, status}.
function sh(cmd, env = {}) {
  const r = spawnSync("bash", ["-c", `source '${LIB}'; ${cmd}`], { cwd: R, encoding: "utf8", env: { ...process.env, HOME: W, ...env } });
  return { out: r.stdout.trim(), err: r.stderr.trim(), status: r.status };
}
const HDR = "| Seat | Repo | Home | Agent | Account | Address | Seen |";
const SEP = "|---|---|---|---|---|---|---|";
const parse = (...rows) => sh(`ws_seats_table_parse who "$(printf '%s\\n' ${[HDR, SEP, ...rows].map((l) => `'${l}'`).join(" ")})"`);

test("ws_seats_table_parse: the rendered 7-column table yields the 4-cell definition per seat", () => {
  const r = parse("| alice/BEAST | acme/twin | checkout | daita-beast:seat | alice@example.com | twin-1 [abc123] | 2026-10-19T00:00:00Z |", "| alice/DEVX | acme/twin | worktree seat/DEVX | evp | — | — | — |");
  assert.equal(r.status, 0, r.err);
  assert.equal(r.out, "alice/BEAST\tacme/twin\tcheckout\tdaita-beast:seat\nalice/DEVX\tacme/twin\tworktree seat/DEVX\tevp");
});

test("ws_seats_table_parse: an empty table is fine; every malformed line dies naming it", () => {
  assert.equal(parse().status, 0);
  const cases = [
    [["| alice/BEAST | acme/twin | checkout |"], /line 3 .*3 cell\(s\), a row has 7/],
    [["| alice/BEAST | acme/twin | subdirectory X | evp | — | — | — |"], /line 3 .*Home `subdirectory X` is not one of: checkout, worktree <branch>, wrapper, subdir <dir>/],
    [["| alice/BEAST | acme/twin | checkout | evp | — | — | — |", "| alice/BEAST | acme/twin | wrapper | evp | — | — | — |"], /line 4 .*seat alice\/BEAST is already on line 3/],
    [["| alice/beast | acme/twin | checkout | evp | — | — | — |"], /line 3 .*Seat `alice\/beast` is not <login>\/<LABEL>/],
    [["| alice/BEAST | twin | checkout | evp | — | — | — |"], /line 3 .*Repo `twin` is not owner\/repo/],
    [["| alice/BEAST | acme/twin | checkout | bad name | — | — | — |"], /line 3 .*Agent `bad name` is not an agent name/],
    [["not a row"], /line 3 .*not a table row/],
  ];
  for (const [rows, re] of cases) {
    const r = parse(...rows);
    assert.equal(r.status, 1, `expected a refusal for ${JSON.stringify(rows)}`);
    assert.match(r.err, re);
  }
  const noHeader = sh(`ws_seats_table_parse who "$(printf '%s\\n' '| Seat | Repo |' '|---|---|')"`);
  assert.equal(noHeader.status, 1); assert.match(noHeader.err, /line 1 .*the header must be exactly/);
  const noSep = sh(`ws_seats_table_parse who "$(printf '%s\\n' '${HDR}' '| a/B | c/d | checkout | e | — | — | — |')"`);
  assert.equal(noSep.status, 1); assert.match(noSep.err, /the separator row .* must follow the header/);
});

test("ws_home_word and ws_home_parse are inverses over the vocabulary", () => {
  for (const [kind, arg, word] of [["checkout", "", "checkout"], ["wrapper", "", "wrapper"], ["worktree", "seat/X", "worktree seat/X"], ["subdir", "DeSciX", "subdir DeSciX"]]) {
    assert.equal(sh(`ws_home_word ${kind} ${arg ? `'${arg}'` : ""}`).out, word);
    assert.equal(sh(`ws_home_parse '${word}' | tr '\\t' ' '`).out, `${kind} ${arg}`.trim());
  }
  assert.match(sh("ws_home_parse 'subdirectory X'").err, /is not one of: checkout, worktree <branch>, wrapper, subdir <dir>/);
  assert.match(sh("ws_home_word worktree").err, /needs its branch/);
});

test("identity: LABEL, login/LABEL and slug/LABEL/login name one row; the composite is derived, never stored", () => {
  assert.equal(sh("seat_id BEAST").out, "alice/BEAST");
  assert.equal(sh("seat_id alice/BEAST").out, "alice/BEAST");
  assert.equal(sh("seat_id beast/BEAST/alice").out, "alice/BEAST");
  assert.equal(sh("seat_identity BEAST").out, "beast/BEAST/alice");
  assert.equal(sh("seat_identity alice/BEAST").out, "beast/BEAST/alice");
  assert.equal(sh("seat_short beast/BEAST/alice").out, "alice/BEAST");
  assert.equal(sh("seat_login beast/BEAST/alice").out, "alice");
  assert.equal(sh("seat_label beast/BEAST/alice").out, "BEAST");
  const wrong = sh("seat_id other/BEAST/alice");
  assert.equal(wrong.status, 1); assert.match(wrong.err, /is in workstream 'beast', not 'other'/);
  assert.match(sh("seat_resolve beast/BEAST/alice").out, /^alice\/BEAST$/);
});

test("roster_check_unique: role and tracking are refused naming the key; agent and workstream are required; no peer rows", () => {
  const check = (row) => { writeFileSync(join(W, "r.json"), JSON.stringify(roster([row]))); return sh(`roster_check_unique '${join(W, "r.json")}'`); };
  assert.equal(check(ROW).status, 0);
  assert.equal(check({ ...ROW, retired: "2026-10-19" }).status, 0);
  for (const [row, re] of [
    [{ ...ROW, role: "x" }, /seat row alice\/BEAST: key "role" is deleted/],
    [{ ...ROW, tracking: "a/b#1" }, /key "tracking" is deleted/],
    [{ ...ROW, agent: undefined }, /key "agent" is required/],
    [{ ...ROW, workstream: "Not A Slug" }, /key "workstream" is required \(a slug/],
    [{ ...ROW, retired: "yesterday" }, /key "retired" is a date YYYY-MM-DD/],
    [{ ...ROW, repo: "acme/elsewhere" }, /a peer row \(repo "acme\/elsewhere".*peers live on the workstream issue/],
  ]) {
    const r = check(row);
    assert.equal(r.status, 1, `expected a refusal for ${JSON.stringify(row)}`);
    assert.match(r.err, re);
  }
});

test("section_replace replaces one section by shape and appends an absent one; block_replace replaces between markers", () => {
  const body = "## A\none\n\n## Seats\nold\nrows\n\n## Z\nlast\n";
  const r = sh(`printf '%b' "${body.replace(/\n/g, "\\n")}" | section_replace Seats "$(printf 'NEW\\nTABLE')"`);
  assert.equal(r.out, "## A\none\n\n## Seats\nNEW\nTABLE\n\n## Z\nlast");
  const a = sh(`printf '%b' "## A\\none" | section_replace Seats "T"`);
  assert.equal(a.out, "## A\none\n\n## Seats\nT");
  const b1 = sh(`printf '%b' "top\\n<!-- beast:workstream begin x -->\\nold\\n<!-- beast:workstream end x -->\\nbottom\\n" | block_replace '<!-- beast:workstream begin x -->' '<!-- beast:workstream end x -->' "$(printf '<!-- beast:workstream begin x -->\\nnew\\n<!-- beast:workstream end x -->')"`);
  assert.equal(b1.out, "top\n<!-- beast:workstream begin x -->\nnew\n<!-- beast:workstream end x -->\nbottom");
  const b2 = sh(`printf '%b' "top\\n" | block_replace '<!-- beast:workstream begin y -->' '<!-- beast:workstream end y -->' "B"`);
  assert.equal(b2.out, "top\n\nB");
});

test("the seat-to-seat tag and the address line are written in their one shape", () => {
  assert.match(sh("msg_header beast/BEAST/alice other/BEAST/alice acme/twin#3").out, /^BEAST-MSG from=beast\/BEAST\/alice to=other\/BEAST\/alice re=acme\/twin#3 blocking=no at=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
  assert.match(sh("msg_header alice/BEAST other/BEAST/alice").err, /is not BEAST-MSG from=<slug>\/<LABEL>\/<login>/);
  assert.equal(sh(`address_header beast/BEAST/alice a@b.c 'twin-1 [abc123]' host 2026-10-19T00:00:00Z`).out, 'BEAST-ADDRESS seat=beast/BEAST/alice account=a@b.c address="twin-1 [abc123]" machine=host at=2026-10-19T00:00:00Z');
  assert.equal(sh(`comment_is_bookkeeping 'BEAST-COWORK by=sam at=x rows=1 asks=0 msgs=0' && echo bk`).out, "bk");
  assert.equal(sh(`comment_is_bookkeeping 'a reply' || echo news`).out, "news");
});
