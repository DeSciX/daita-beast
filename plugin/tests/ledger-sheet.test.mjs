// ledger.sh --sheet: the month's awards as the CSV the DeSciX platform's Offers import reads, run against the stub gh.
// The import's contract (measured from the platform's owner, never read here): header in row 1, columns matched by
// header name case-insensitively, contactemail required on every row, new_amount a plain decimal, wallet_address blank.
//   node --test plugin/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { ghStub } from "./gh-stub.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const LEDGER = join(here, "..", "scripts", "ledger.sh");
const LIB = join(here, "..", "scripts", "lib.sh");
const REPO = "acme/widgets";
const MONTH = "2026-10";

// The fixture month: three ACME awards (one decimal, one of a million) and one BETA award, on two items.
function world(name) {
  const D = mkdtempSync(join(tmpdir(), `beast-sheet-${name}-`));
  let cn = 0;
  const item = (n) => ({ number: n, title: `item ${n}`, state: "closed", html_url: `https://github.com/${REPO}/pull/${n}`, labels: [{ name: "awarded" }],
    assignees: [], user: { login: "acme" }, created_at: "2026-10-01T00:00:00Z", updated_at: "2026-10-02T00:00:00Z", closed_at: "2026-10-02T00:00:00Z",
    repository_url: `https://api.github.com/repos/${REPO}`, milestone: null, comments: 2 });
  const cm = (n, body, at) => ({ id: ++cn, body, user: { login: "acme" }, created_at: at, html_url: `https://github.com/${REPO}/pull/${n}#issuecomment-${cn}` });
  const gh = ghStub(join(D, "gh"), { login: "acme", repos: { [REPO]: { private: true } }, roles: { [REPO]: { acme: "admin" } },
    issues: { [`${REPO}#1`]: item(1), [`${REPO}#2`]: item(2) },
    comments: {
      [`${REPO}#1`]: [cm(1, 'BEAST-AWARD amount=500 token=ACME to=@Alice for="the logo"', "2026-10-03T10:00:00Z"),
        cm(1, 'BEAST-AWARD amount=12.5 token=ACME to=@bob for="a review, with care"', "2026-10-04T10:00:00Z")],
      [`${REPO}#2`]: [cm(2, 'BEAST-AWARD amount=1000000 token=ACME to=@alice for="the engine"', "2026-10-05T10:00:00Z"),
        cm(2, 'BEAST-AWARD amount=40 token=BETA to=@carol for="docs"', "2026-10-06T10:00:00Z")] } });
  const env = { ...process.env, PATH: `${gh.bin}:${process.env.PATH}`, HOME: D, BEAST_CACHE_DIR: join(D, "cache") };
  const out = join(D, "out"), sheet = join(D, "sheet.csv"), emails = join(D, "emails.csv");
  writeFileSync(emails, "login,email\nalice,alice@example.org\nBob,bob.smith+awards@example.co.uk\ncarol,carol@example.net\n");
  const run = (args, token = "ACME") => spawnSync(LEDGER, ["--community", token, "--repos", REPO, "--month", MONTH, "--out", out, ...args],
    { cwd: D, encoding: "utf8", env });
  return { D, gh, out, sheet, emails, run };
}

// The import's reading of a sheet: RFC 4180 fields, header in row 1, columns by name, case-insensitive.
function parseCsv(text) {
  const rows = []; let row = [], f = "", q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"' && text[i + 1] === '"') { f += '"'; i++; } else if (c === '"') q = false; else f += c; continue; }
    if (c === '"' && f === "") q = true;
    else if (c === ",") { row.push(f); f = ""; }
    else if (c === "\n" || c === "\r") { if (c === "\r" && text[i + 1] === "\n") i++; row.push(f); rows.push(row); row = []; f = ""; }
    else f += c;
  }
  if (f !== "" || row.length) { row.push(f); rows.push(row); }
  return rows;
}
function readSheet(text) {
  const [head, ...data] = parseCsv(text);
  const col = Object.fromEntries(head.map((h, i) => [h.trim().toLowerCase(), i]));
  return { columns: Object.keys(col), rows: data.map((r) => Object.fromEntries(Object.entries(col).map(([k, i]) => [k, r[i]]))) };
}

const EXPECTED = [
  "contactemail,token,new_amount,batch,wallet_address",
  "alice@example.org,ACME,500,awards-2026-10,",
  "bob.smith+awards@example.co.uk,ACME,12.5,awards-2026-10,",
  "alice@example.org,ACME,1000000,awards-2026-10,",
  "",
].join("\n");

test("gate 1: a month of 3 ACME awards and a BETA award emits exactly the expected ACME sheet; the BETA run emits its own", () => {
  const w = world("exact");
  const r = w.run(["--sheet", w.sheet, "--emails", w.emails]);
  assert.equal(r.status, 2, `the BETA comment is dropped from the ACME ledger, exit 2\n${r.stdout}\n${r.stderr}`);
  assert.match(r.stderr, /DROPPED .*token BETA is not ACME/);
  assert.equal(readFileSync(w.sheet, "utf8"), EXPECTED);
  assert.equal(readFileSync(join(w.out, `${MONTH}.jsonl`), "utf8").trim().split("\n").length, 3, "the jsonl holds the same three rows");
  const b = w.run(["--sheet", w.sheet, "--emails", w.emails, "--batch", "oct-airdrop"], "BETA");
  assert.equal(b.status, 2, b.stderr);
  assert.equal(readFileSync(w.sheet, "utf8"), "contactemail,token,new_amount,batch,wallet_address\ncarol@example.net,BETA,40,oct-airdrop,\n");
});

test("gate 2: an awarded login with no email refuses, names it, and writes nothing", () => {
  const w = world("unmapped");
  writeFileSync(w.emails, "login,email\nalice,alice@example.org\ncarol,carol@example.net\n");
  const r = w.run(["--sheet", w.sheet, "--emails", w.emails]);
  assert.equal(r.status, 1, r.stderr);
  assert.match(r.stderr, /refused: --emails .* maps no email for the awarded login\(s\) @bob; nothing written/);
  assert.equal(existsSync(w.sheet), false, "no sheet");
  assert.equal(existsSync(join(w.out, `${MONTH}.jsonl`)), false, "no jsonl");
  assert.equal(existsSync(join(w.out, `${MONTH}.md`)), false, "no md");
});

test("gate 3: a sheet path inside a git checkout is refused before anything is read, ignored or not", () => {
  const w = world("checkout");
  const R = join(w.D, "repo");
  mkdirSync(join(R, ".scratch"), { recursive: true });
  execFileSync("git", ["-C", R, "init", "-q"]);
  writeFileSync(join(R, ".gitignore"), ".scratch/\n");
  for (const p of [join(R, "sheet.csv"), join(R, ".scratch", "sheet.csv")]) {
    const r = w.run(["--sheet", p, "--emails", w.emails]);
    assert.equal(r.status, 1, r.stderr);
    assert.match(r.stderr, /refused: --sheet .* is inside the git checkout .*: write it outside every git checkout/);
    assert.equal(existsSync(p), false, p);
  }
  assert.equal(w.gh.log().length, 0, `nothing read from GitHub:\n${w.gh.log().join("\n")}`);
});

test("gate 4: decimal and large amounts round-trip as plain decimals, no separator", () => {
  const w = world("decimal");
  w.run(["--sheet", w.sheet, "--emails", w.emails]);
  const amounts = readSheet(readFileSync(w.sheet, "utf8")).rows.map((r) => r.new_amount);
  assert.deepEqual(amounts, ["500", "12.5", "1000000"]);
  for (const a of amounts) assert.match(a, /^\d+(\.\d+)?$/);
});

test("gate 5: a header-only map, a duplicate login, a malformed email or header refuse loud, writing nothing", () => {
  const cases = [
    ["header only", "login,email\n", /maps no login: it has the header and no <login>,<email> line/],
    ["duplicate login", "login,email\nalice,a@example.org\nbob,b@example.org\nALICE,c@example.org\n", /line 4: login alice is listed twice/],
    ["malformed email", "login,email\nalice,alice-at-example.org\n", /line 2: 'alice-at-example.org' is not an email address/],
    ["no header", "alice,alice@example.org\n", /line 1 must be the header login,email/],
    ["quoted field", 'login,email\nalice,"a,b"@example.org\n', /line 2: not <login>,<email>/],
  ];
  for (const [what, body, re] of cases) {
    const w = world("map");
    writeFileSync(w.emails, body);
    const r = w.run(["--sheet", w.sheet, "--emails", w.emails]);
    assert.equal(r.status, 1, `${what}: ${r.stderr}`);
    assert.match(r.stderr, re, what);
    assert.equal(existsSync(w.sheet), false, what);
    assert.equal(w.gh.log().length, 0, `${what}: nothing read from GitHub`);
  }
});

test("gate 6: the import's reader (header by name, case-insensitive) reads the rows back to the award values", () => {
  const w = world("parse");
  w.run(["--sheet", w.sheet, "--emails", w.emails]);
  const { columns, rows } = readSheet(readFileSync(w.sheet, "utf8"));
  assert.deepEqual(columns.toSorted(), ["batch", "contactemail", "new_amount", "token", "wallet_address"]);
  for (const k of ["offer_id", "offered_at", "sent_at", "current_holdings"]) assert.equal(columns.includes(k), false, k);
  const map = Object.fromEntries(readFileSync(w.emails, "utf8").trim().split("\n").slice(1).map((l) => l.split(",")).map(([l, e]) => [l.toLowerCase(), e]));
  const awards = readFileSync(join(w.out, `${MONTH}.jsonl`), "utf8").trim().split("\n").map((l) => JSON.parse(l));
  assert.deepEqual(rows.map((r) => [r.contactemail, r.token, Number(r.new_amount), r.batch, r.wallet_address]),
    awards.map((a) => [map[a.to.toLowerCase()], a.token, a.amount, `awards-${MONTH}`, ""]));
  for (const r of rows) assert.ok(r.contactemail, "every row carries a contactemail");
});

test("AWARD_AMOUNT_RE: the one amount shape (award.sh, bounty.sh, ledger.sh)", () => {
  const ok = (a) => spawnSync("bash", ["-c", `source '${LIB}'; [[ '${a}' =~ $AWARD_AMOUNT_RE ]]`]).status === 0;
  for (const a of ["0", "500", "12.5", "0.25", "1000000"]) assert.ok(ok(a), a);
  for (const a of ["", "1,000", "12.50", "012", "-5", "1e6", ".5", "5.", "$5"]) assert.ok(!ok(a), a);
});
