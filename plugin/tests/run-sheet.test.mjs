// The run sheet of a hands row (plugin/scripts/build-run-sheet.mjs, plugin/templates/run-sheet/page.html): the
// validator's rules and the build. Each refusal is shown failing on a run that breaks it and passing on the sample.
//   node --test plugin/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { validateRun, buildRunSheet } from "../scripts/build-run-sheet.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const PAGE = join(here, "..", "templates", "run-sheet", "page.html");
const sample = () => JSON.parse(readFileSync(join(here, "..", "templates", "run-sheet", "fixtures", "sample-run.json"), "utf8"));

test("the sample run is valid and builds into the artifact shape", () => {
  assert.deepEqual(validateRun(sample()), []);
  const page = buildRunSheet(sample());
  assert.ok(page.startsWith("<title>Verify a domain for outbound mail</title>"));
  assert.ok(!page.includes("/*__"));
  assert.ok(!/<!doctype|<html[\s>]|<head[\s>]|<body[\s>]/i.test(page));
  assert.equal(JSON.parse(page.match(/<script type="application\/json" id="run">([\s\S]*?)<\/script>/)[1]).steps.length, 3);
});

test("the run serves one hands row: anchor is <owner/repo>#<N> and fallback is that row's URL", () => {
  const r = sample(); r.anchor = "issue 12";
  assert.ok(validateRun(r).some((x) => x.includes("anchor must be the hands row")));
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

test("text in a run cannot break out of the page", () => {
  const r = sample(); r.title = "A </title><script>x</script>"; r.goal = ["</script><b>"];
  const page = buildRunSheet(r);
  assert.ok(page.startsWith("<title>A &lt;/title&gt;&lt;script&gt;x&lt;/script&gt;</title>"));
  assert.equal(page.split("</script>").length - 1, 2);
});

test("the evidence store has one seam: the page's own artifact store today, any other store fails loud", () => {
  const src = readFileSync(PAGE, "utf8");
  assert.equal((src.match(/var EVIDENCE_STORE = 'artifact-db';/g) || []).length, 1);
  assert.equal((src.match(/function openEvidenceStore\(\)/g) || []).length, 1);
  assert.match(src, /if\(EVIDENCE_STORE !== 'artifact-db'\) return Promise\.reject\(new Error\('unknown evidence store '/);
  // The store is opened only through the seam: no other call reaches the runtime's store.
  assert.equal((src.match(/window\.claude\.use\(/g) || []).length, 1);
  assert.equal((src.match(/db\.doc\('runs\/' \+ run\.id\)/g) || []).length, 1);
});
