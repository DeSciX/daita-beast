// ledger.sh: every row's ref. An award with no ref= cites the awarded item's URL; an award's own ref= is kept; a ref=
// present but empty or not an https URL stops the run before anything is written. Run against the stub gh.
//   node --test plugin/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { ghStub } from "./gh-stub.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const LEDGER = join(here, "..", "scripts", "ledger.sh");
const REPO = "acme/widgets";
const MONTH = "2026-10";
const PR1 = `https://github.com/${REPO}/pull/1`, ISSUE2 = `https://github.com/${REPO}/issues/2`;
const OWN = "https://github.com/acme/widgets/commit/0123abc";

function world(name, extra = []) {
  const D = mkdtempSync(join(tmpdir(), `beast-ref-${name}-`));
  let cn = 0;
  const item = (n, url) => ({ number: n, title: `item ${n}`, state: "closed", html_url: url, labels: [{ name: "awarded" }],
    assignees: [], user: { login: "acme" }, created_at: "2026-10-01T00:00:00Z", updated_at: "2026-10-02T00:00:00Z", closed_at: "2026-10-02T00:00:00Z",
    repository_url: `https://api.github.com/repos/${REPO}`, milestone: null, comments: 2 });
  const cm = (url, body, at) => ({ id: ++cn, body, user: { login: "acme" }, created_at: at, html_url: `${url}#issuecomment-${cn}` });
  const gh = ghStub(join(D, "gh"), { login: "acme", repos: { [REPO]: { private: true } }, roles: { [REPO]: { acme: "admin" } },
    issues: { [`${REPO}#1`]: item(1, PR1), [`${REPO}#2`]: item(2, ISSUE2) },
    comments: {
      [`${REPO}#1`]: [cm(PR1, 'BEAST-AWARD amount=500 token=ACME to=@alice for="the logo"', "2026-10-03T10:00:00Z"),
        cm(PR1, `BEAST-AWARD amount=12.5 token=ACME to=@bob for="a review" ref=${OWN}`, "2026-10-04T10:00:00Z")],
      [`${REPO}#2`]: [cm(ISSUE2, 'BEAST-AWARD amount=40 token=ACME to=@carol for="the bug"', "2026-10-05T10:00:00Z"),
        ...extra.map((b, i) => cm(ISSUE2, b, `2026-10-0${6 + i}T10:00:00Z`))] } });
  const env = { ...process.env, PATH: `${gh.bin}:${process.env.PATH}`, HOME: D, BEAST_CACHE_DIR: join(D, "cache") };
  const out = join(D, "out");
  const run = () => spawnSync(LEDGER, ["--community", "ACME", "--repos", REPO, "--month", MONTH, "--out", out], { cwd: D, encoding: "utf8", env });
  const rows = () => readFileSync(join(out, `${MONTH}.jsonl`), "utf8").trim().split("\n").map((l) => JSON.parse(l));
  return { out, run, rows };
}

test("gate 1: an award without ref= has ref == the awarded item's URL (a PR and an issue)", () => {
  const w = world("default");
  const r = w.run();
  assert.equal(r.status, 0, r.stderr);
  const by = Object.fromEntries(w.rows().map((x) => [x.to, x]));
  assert.equal(by.alice.ref, PR1);
  assert.equal(by.carol.ref, ISSUE2);
  assert.equal(by.alice.ref, by.alice.item);
});

test("gate 2: an award with ref= keeps its own ref", () => {
  const w = world("own");
  assert.equal(w.run().status, 0);
  const bob = w.rows().find((x) => x.to === "bob");
  assert.equal(bob.ref, OWN);
  assert.notEqual(bob.ref, bob.item);
});

test("gate 3: no row has an empty ref", () => {
  const w = world("nonempty");
  assert.equal(w.run().status, 0);
  const rows = w.rows();
  assert.equal(rows.length, 3);
  for (const x of rows) assert.ok(typeof x.ref === "string" && x.ref.length > 0, JSON.stringify(x));
});

test("gate 4: a ref= present but empty or not an https URL refuses the run, naming it, and writes nothing", () => {
  for (const bad of ["ref=", "ref=PR#12", "ref=http://example.org/x"]) {
    const w = world("bad", [`BEAST-AWARD amount=7 token=ACME to=@dave for="a fix" ${bad}`]);
    const r = w.run();
    assert.equal(r.status, 1, `${bad}: ${r.stdout}\n${r.stderr}`);
    assert.match(r.stderr, /refused: the BEAST-AWARD comment by acme at .* on https:\/\/github\.com\/acme\/widgets\/issues\/2 has ref='[^']*', which is not an https URL/, bad);
    assert.equal(existsSync(join(w.out, `${MONTH}.jsonl`)), false, `${bad}: no jsonl`);
    assert.equal(existsSync(join(w.out, `${MONTH}.md`)), false, `${bad}: no md`);
  }
});
