---
name: stage-hands
description: Stage a hands row (an act only the decider can perform in a browser, such as a passkey or two-factor tap, a signed-in admin console, a consent screen, a DNS change, a public flip) as a run-sheet page a browser agent follows with them, results saved on the page and read back by key, and link it on the row. Use for "stage this for the browser", "make a run sheet", "hand this to the browser agent", or when a row filed with --hands needs the decider's own clicks.
---

# stage-hands — a hands row becomes a run sheet

A row labelled `hands` waits on an act only the decider can perform. When that act happens in a browser, do not hand them a long request to drive by memory and type the findings back: stage it as a **run sheet**, one private page that a browser agent works through with them, stopping where only they may act, and saving every finding on the page under a fixed key.

## 1. Is it a hands act for a run sheet?

Stage it when the act needs a signed-in browser **and** the decider: their passkey or two-factor code, a console only they can open, a consent screen, a button that sends, pays, signs, flips or publishes. Do not stage a choice between options (a desk ask), anything you can do yourself, or a step whose only content is "approve": a page cannot give the word, and the row's approving phrase stays on the row. One sitting: put every browser step the act needs on one sheet.

## 2. Write the run

The run's shape is the header of `${CLAUDE_PLUGIN_ROOT}/scripts/build-run-sheet.mjs` (`validateRun`, its one owner); `${CLAUDE_PLUGIN_ROOT}/templates/run-sheet/fixtures/sample-run.json` is a worked example.

- `id`: lowercase with hyphens. It is the store key: results land at `runs/<id>`.
- `anchor`: the hands row, `<owner/repo>#<N>`. `fallback`: that row's own URL; if the page cannot be typed into, the results are posted there as one comment (a plain comment, never an answer form).
- `goal`: what is being done and why, for someone who has forgotten the thread, with what the sheet must never do. `checked`: only what you verified yourself, with the time. `stops`: the conditions under which the browser agent stops, each with what to record (the row's `## Stops if` lines belong here too). `never`: what must not be typed into the page (codes, passwords, recovery words, keys, full account or wallet identifiers).
- Steps: the first is a `read`. A `change` step says exactly what to do, with exact https links and exact values. `hands` names what the decider does at that step; every passkey, code, consent, payment, signature and final send is a `hands` step, and the agent's last instruction before it is STOP. A decision inside the run is a `rule` over an earlier capture. `capture` keys are snake_case and unique: they are the contract you read back by.

## 3. Build, publish, link

```
node ${CLAUDE_PLUGIN_ROOT}/scripts/build-run-sheet.mjs run.json --out page.html
```
The build refuses a run that breaks the rules: an anchor that is not a row or a fallback that is not its URL, a change before any read, a link that is not https, a capture key that looks like a secret. Keep `run.json` in your private home repo (it names your team's systems), never in the plugin.

Publish `page.html` as a private artifact with the `db` capability (`capabilities: {db: {}}`); a changed run republishes to the same artifact. Then link it on the row, which must carry `hands`:
```
${CLAUDE_PLUGIN_ROOT}/scripts/decision.sh new … --hands --run-sheet <artifact url>       (when filing)
${CLAUDE_PLUGIN_ROOT}/scripts/decision.sh revise <row> --by <YOUR SEAT> --run-sheet <artifact url>   (an unanswered row)
```
The row's `## Decision` ends with `Run sheet: <url>`; the board page shows a "run sheet" chip on the card. Tell the decider in one line what it is, how long it takes, what they need at hand, and the sentence to give their browser agent: "Open <link> and follow the page."

## 4. Read it back

The results are in the page's own artifact store at `runs/<id>`: `{results: {key: text}, steps: {id: {status, note}}, updatedAt}`; read them by key (the `ArtifactData` tool, `get` collection `runs`, doc `<id>`). If the decider used Copy results instead, the block is a comment on the row. A result is a reading of a screen: verify what can be verified another way (a server read, a hash) before anything is built on it. The row closes on the decider's report that the act is done, as every hands row does.

The evidence store is one seam in the page (`EVIDENCE_STORE` and `openEvidenceStore` in `templates/run-sheet/page.html`): the page's own artifact store today, DeSciX private media once its contract is published. Until then, nothing names that contract's calls.

## Never

A run sheet is never a way around a gate (a send, payment, signature, public release or deploy stays the decider's own click on a `hands` step), never a store for secrets (a secret ends as a file saved to a named folder; the capture is its file name), and never left dangling (a sheet that was not run is re-staged with a fresh `checked` list and relinked with `decision.sh revise --run-sheet`).
