// The published DeSciX CLI version has one owner, DESCIX_CLI_PKG in plugin/scripts/lib.sh; every printed descix command
// reads it through descix_cmd. This test fails when the owner line is missing or doubled, or when any other file of
// plugin/ or docs/ names a CLI version (a hand copy that drifts).
//   node --test plugin/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = process.env.BEAST_TEST_ROOT || join(here, "..", "..");
const LIB = join(ROOT, "plugin", "scripts", "lib.sh");
// Assembled, so this file does not itself name a version.
const PIN = new RegExp("@descix/cli" + "@[0-9]");

function files(dir) {
  return readdirSync(dir).flatMap((n) => {
    const p = join(dir, n);
    return statSync(p).isDirectory() ? (n === "node_modules" ? [] : files(p)) : [p];
  });
}

test("lib.sh owns the CLI pin in one line, and descix_cmd prints it", () => {
  const owners = readFileSync(LIB, "utf8").split("\n").filter((l) => l.startsWith("DESCIX_CLI_PKG="));
  assert.equal(owners.length, 1, `${LIB}: want one DESCIX_CLI_PKG= line, found ${owners.length}`);
  const pkg = /^DESCIX_CLI_PKG='(@descix\/cli@[0-9]+\.[0-9]+\.[0-9]+)'$/.exec(owners[0]);
  assert.ok(pkg, `${LIB}: the owner line is not DESCIX_CLI_PKG='@descix/cli@<x.y.z>': ${owners[0]}`);
  const out = execFileSync("bash", ["-c", 'source "$1"; descix_cmd whoami', "_", LIB], { encoding: "utf8" });
  assert.equal(out, `npx -y -p ${pkg[1]} descix whoami`);
});

test("no other file of plugin/ or docs/ names a CLI version", () => {
  const hits = [];
  for (const f of [...files(join(ROOT, "plugin")), ...files(join(ROOT, "docs"))]) {
    if (f === LIB) continue;
    readFileSync(f, "utf8").split("\n").forEach((l, i) => { if (PIN.test(l)) hits.push(`${relative(ROOT, f)}:${i + 1}`); });
  }
  assert.deepEqual(hits, [], `hand copies of the CLI version (read DESCIX_CLI_PKG / descix_cmd instead): ${hits.join(", ")}`);
});
