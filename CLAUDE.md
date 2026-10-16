# daita-beast

Beast is a coordination protocol for agent teams built on GitHub's own objects (Projects, issues, labels, pull requests, milestones) plus a thin Claude Code plugin under `plugin/` that wraps the few `gh` calls a seat makes. GitHub keeps the permissions, the history and the cost. `docs/protocol.md` is the design authority: read it before changing a shape, a script or a skill.

## Working here
- Scripts live in `plugin/scripts/`, one per skill, sharing `lib.sh`. They parse by shape and exit non-zero naming what they could not read; never add tolerance to a renderer, fix the input instead.
- A change to an issue or comment shape changes the template, the script that writes it and the script that reads it in one commit; the protocol doc states the shape once.
- Nothing about a particular team is built into the plugin: every per-team fact (seats, the decider, the board repo, the public repo a twin publishes to) is read from the coordinating repo's `.beast/roster.json`, and a missing fact fails loud.
- Examples in docs and skills use placeholders (`<owner/repo>`, `<LABEL>`, `<login>`) or the fictional `acme/widgets`.

## Tests
- `npm test` runs `plugin/tests/*.test.mjs` with Node's test runner (Node 22, `jq` installed). CI runs it on every push and pull request.
- `bash -n plugin/scripts/*.sh plugin/scripts/realign/*.sh` checks every script parses.
- Try the plugin from a checkout with `claude --plugin-dir plugin`.

## Coordination
This repository receives code and docs only. Each Beast user coordinates in their own private repo (the private twin of a public product): decision rows, desks, status, notes and acks never go on a public repo, and the scripts refuse to write them there. Contributions here are ordinary pull requests.
