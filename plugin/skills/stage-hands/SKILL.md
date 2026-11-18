---
name: stage-hands
description: Stage a browser act or walk for the decider as a run-sheet page — a hands row (an act only the decider can perform in a browser, such as a passkey or two-factor tap, a signed-in admin console, a consent screen, a DNS change, a public flip) or an acceptance walk (steps to try on a live site, each judged Pass / Partly / Fail / N/A, with an Accept / Not yet / Roll back verdict). The page carries the prompt for their browser agent (Claude in Chrome), saves results per step, and is read back by the seat. Use for "stage this for the browser", "make a run sheet", "make an acceptance walk", "hand this to Claude in Chrome", or when a row filed with --hands needs the decider's own clicks.
---

# stage-hands — a browser act or walk becomes a run sheet

Some rows wait on the decider in a browser: a `hands` row (an act only they can perform) or an acceptance walk (they try the change on the live site and give a verdict). Do not hand them a long request to drive by memory and type the findings back: stage it as a **run sheet**, one private page built from one run. The page shows each step, carries a prompt for their browser agent generated from the same steps, and saves each step's result in its own store, where you read it back.

## 1. Is it a run sheet?

Stage it when the act needs a signed-in browser **and** the decider: their passkey or two-factor code, a console only they can open, a consent screen, a button that sends, pays, signs, flips or publishes; or a walk of a change on the live site whose verdict is theirs. Do not stage a choice between options (a desk ask), anything you can do yourself, or a step whose only content is "approve": a page cannot give the word, and the row's approving phrase stays on the row. One sitting: put every browser step on one sheet.

## 2. Write the run

The run's shape is the header of `${CLAUDE_PLUGIN_ROOT}/scripts/build-run-sheet.mjs` (`validateRun`, its one owner); `${CLAUDE_PLUGIN_ROOT}/templates/run-sheet/fixtures/sample-run.json` is a worked example.

- `id`: lowercase with hyphens. It is the store key: results land in the collection `runs/<id>/results`.
- `anchor`: the row, `<owner/repo>#<N>`. `fallback`: that row's own URL; if the page cannot be typed into, the results are posted there as one comment (a plain comment, never an answer form).
- `cost`: what the walk is expected to spend (AI credits or anything else), shown before the steps; `"none"` when it costs nothing. A step that drives a metered surface (a chat, a model call, a paid API) carries `metered: true`, and then `cost` may not be "none".
- `goal`: what is being done and why, for someone who has forgotten the thread. `checked`: only what you verified yourself, with the time. `stops`: the conditions under which the walk stops, each with what to record (the row's `## Stops if` lines belong here too). `never`: what must not be typed into the page (codes, passwords, recovery words, keys, full account or wallet identifiers).
- Steps: the first is a `read`. Every step names `env`, where its behaviour is deployed: `"prod"` (on the live site), `"branch"` (only on an unmerged branch: on the live site it is marked N/A, never Fail) or `"both"` (live, with a branch-only part the step's text names). A `change` step says exactly what to do, with exact https links and exact values. `hands` names what the decider does at that step; every passkey, code, consent, payment, signature and final send is a `hands` step. `asks` are the exact words to type into the site (a chat question). `expect` is what should happen; `measured` (`{at, text}`) is your last machine measurement of it, shown beside `expect` so the decider sees the delta. A decision inside the run is a `rule` over an earlier capture. `capture` keys are snake_case and unique.

## 3. Build, publish, link

```
node ${CLAUDE_PLUGIN_ROOT}/scripts/build-run-sheet.mjs run.json --out page.html
node ${CLAUDE_PLUGIN_ROOT}/scripts/build-run-sheet.mjs --check page.html
```
The build refuses a run that breaks the rules: an anchor that is not a row or a fallback that is not its URL, a missing `cost` or `env`, "none" with a metered step, a change before any read, a link that is not https, a capture key that looks like a secret. `--check` refuses a page whose embedded browser prompt no longer matches its steps: rebuild, never edit the prompt. Keep `run.json` in your private home repo (it names your team's systems), never in the plugin.

Publish `page.html` as a private artifact with the `db` capability (`capabilities: {db: {}}`). A changed run is rebuilt and republished to the same artifact: change the file with Edit (or rebuild it), then publish the file path. Do not publish with an `edits` list: a file-edit hook can refuse it. A hands row links it; a walk is linked from the row or desk ask it answers:
```
${CLAUDE_PLUGIN_ROOT}/scripts/decision.sh new … --hands --run-sheet <artifact url>       (when filing)
${CLAUDE_PLUGIN_ROOT}/scripts/decision.sh revise <row> --by <YOUR SEAT> --run-sheet <artifact url>   (an unanswered row)
```
The row's `## Decision` ends with `Run sheet: <url>`; the board page shows a "run sheet" chip on the card.

## 4. The walk, with Claude in Chrome

Tell the decider in one line what it is, how long it takes, what it costs, and what they need at hand. Then:

1. They open the page, and in Chrome open the first step's site and **sign in themselves**. The agent never signs in or out.
2. They open Claude in Chrome on that tab, press **Copy prompt** on the page, and paste it. The prompt's rules are fixed: the person signs in; the agent never signs in or out, changes a setting no CHANGE step names, or opens a site the steps do not name; it stops at every HANDS step; quotes each reply; checks every address; marks a branch-only step N/A; judges each step Pass, Partly or Fail; and ends with a table.
3. As the agent reports, they mark each step and paste what it said into the step's notes, its closing table into Overall notes, and press a verdict: **Accept**, **Not yet** or **Roll back**.

## 5. Read it back

The results are in the page's store, collection `runs/<id>/results`: one document per step, `step-<n>` (`n` its 1-based position) = `{n, id, status, note, results: {key: text}, at}` with `status` one of `pass`, `partly`, `fail`, `na`, `blocked`, `skipped` or null; `overall` = `{text, at}`; `verdict` = `{verdict: "accept"|"not-yet"|"roll-back"|null, at}`. Read them with the `ArtifactData` tool, `list` on collection `runs/<id>/results`. The store's `set()` replaces a whole document, so the page writes every step document whole; never write a partial one from your side. If the decider used Copy results instead, the block is a comment on the row.

Then post the reading where the work waits (on the row as a comment, or on the desk ask) as a report, never as the decider's word: the verdict as they pressed it, and every step not Pass split in two: **not deployed** (`na`, or a fault in a `branch` part) is work still to ship, a **real fault** (`fail` or `partly` on a deployed step, `blocked`) is work to fix. A result is a reading of a screen: verify what can be verified another way (a server read, a hash) before anything is built on it. A row closes only on the decider's own word on it.

The evidence store is one seam in the page (`EVIDENCE_STORE` and `openEvidenceStore` in `templates/run-sheet/page.html`): the page's own artifact store today, DeSciX private media once its contract is published. Until then, nothing names that contract's calls.

## Never

A run sheet is never a way around a gate (a send, payment, signature, public release or deploy stays the decider's own click on a `hands` step; a verdict on the page is not the row's approving phrase), never a store for secrets (a secret ends as a file saved to a named folder; the capture is its file name), and never left dangling (a sheet that was not run is re-staged with a fresh `checked` list and relinked with `decision.sh revise --run-sheet`).
