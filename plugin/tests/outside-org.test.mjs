// The outside-organization parsers (lib.sh), run through bash with no network: the roster's "workstream_owners" (one
// parser, dies naming the field) and the award policy's Token and Community lines (award_policy).
//   node --test plugin/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const LIB = join(here, "..", "scripts", "lib.sh");
const W = mkdtempSync(join(tmpdir(), "beast-outside-"));
const R = join(W, "app");
mkdirSync(join(R, ".beast"), { recursive: true });
execFileSync("git", ["-C", R, "init", "-q"]);
execFileSync("git", ["-C", R, "remote", "add", "origin", "https://github.com/acme/app.git"]);
const ROSTER = { repo: "acme/app-dev", board: "acme/app-dev", seats: [], people: [] };
function sh(cmd) {
  const r = spawnSync("bash", ["-c", `source '${LIB}'; ${cmd}`], { cwd: R, encoding: "utf8", env: { ...process.env, HOME: W } });
  return { out: r.stdout.trim(), err: r.stderr.trim(), status: r.status };
}
const roster = (x) => writeFileSync(join(R, ".beast", "roster.json"), JSON.stringify({ ...ROSTER, ...x }));

test("roster_workstream_owners: absent is none; a list of owners is read; anything else dies naming the field", () => {
  roster({});
  assert.deepEqual(sh("roster_workstream_owners"), { out: "", err: "", status: 0 });
  roster({ workstream_owners: ["threejs", "other-org"] });
  assert.equal(sh("roster_workstream_owners").out, "threejs\nother-org");
  for (const bad of ["threejs", [1], ["three js"], ["threejs", "ThreeJS"], ["acme"], {}]) {
    roster({ workstream_owners: bad });
    const r = sh("roster_workstream_owners");
    assert.equal(r.status, 1, JSON.stringify(bad));
    assert.match(r.err, /"workstream_owners" /);
  }
});

test("award_policy: prints the token and the community repo; a missing or malformed Community line dies naming it", () => {
  const pol = (lines) => writeFileSync(join(R, ".beast", "award-policy.md"), ["# Award policy — acme/app", "", ...lines, ""].join("\n"));
  pol(["Token: ACME (units).", "Community: acme/ACME (the community)."]);
  assert.equal(sh("award_policy acme/app ACME").out, "ACME acme/ACME");
  pol(["Token: ACME (units)."]);
  assert.match(sh("award_policy acme/app").err, /no 'Community: <owner\/repo>' line/);
  pol(["Token: ACME (units).", "Community: ACME (the community)."]);
  assert.match(sh("award_policy acme/app").err, /'Community: ACME' is not owner\/repo/);
  pol(["Token: ACME (units).", "Community: <COMMUNITY>"]);
  assert.match(sh("award_policy acme/app").err, /still carries a fill field: <COMMUNITY>/);
});
