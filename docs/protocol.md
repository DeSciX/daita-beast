# The Beast protocol

Beast is how agent teams coordinate work on DeSciX using GitHub's own objects. It adds guidelines and a thin plugin, nothing else: GitHub keeps the permissions, the history and the cost. Any team can run it under its own owner; a dependency on the platform is an issue filed in the platform's repo.

## The mapping

| Beast concept | GitHub object | Where it lives |
|---|---|---|
| Workstream | one Projects v2 board plus one tracking issue labelled `workstream` | the Project under the owner that coordinates it; the tracking issue in the coordinating repo |
| Public description of a workstream | the Project README and the tracking issue body (northstar verbatim, repos, acceptance, seats) | the Project |
| Details and status reports | comments on the tracking issue, fixed `BEAST-STATUS` header | the coordinating repo |
| Pending decision (an act without code) | an issue labelled `decision`, assigned to the person whose word it needs, six fixed sections | the filing seat's home repo (the roster `repo`, always private); the repo it decides, when another, is a `Decides:` link at the end of its Decision section; added to the workstream's Project |
| Pull request for the decider's review | the PR itself, labelled `needs-review` and `seat:<login>/<LABEL>`, assigned to the decider (`pr.sh request`) | the PR's repo, when it is private |
| A decider's board | the search `is:open label:decision,needs-review assignee:<login>` (issues and PRs) and a generated issue pinned in the coordinating repo: the pending table and the decided table (last 7 days, with the words) | GitHub; nothing hosted |
| A seat's desk (questions across the desk, messages) | one long-lived issue per seat, `Desk: <login>/<LABEL>`, labelled `desk` and `seat:<login>/<LABEL>`, assigned to the decider; asks, answers and messages are its comments, its body is generated (`desk.sh`) | the seat's roster repo |
| An act only the assignee can do (public flip, chain, secret, scope grant) | `decision` plus the `hands` label | same |
| Cross-repo dependency | an issue filed in the target repo, added to the dependent Project | the target repo |
| A ruling, verbatim | the decider's answer comment on the row, or the words typed to a session quoted verbatim in the row's close comment; kept until the milestone's wrap-up folds them into the docs and deletes the row | the row's repo |
| Seat roster (who may be addressed from this repo, GitHub login) | `.beast/roster.json`, committed, repo-scoped | each coordinating repo, always a private one |
| Milestone (a dated deliverable a seat schedules) | a GitHub milestone: title, due date (GitHub's `due_on`), description of fixed lines (`milestone.sh`) | the repo its items live in; a seat's are on its home (the roster `repo`) |
| Dependency (what a seat waits on) | one line `Waits on: <seat id \| owner/repo#N>`, in a row's `## Waits`, an ask's lines or a milestone's description; measured by `deps.sh` | where it is declared |
| Twin (a public product's private repo) | the roster's `repo`, with `publishes_to` naming the public repo | the roster |
| Milestone wrap-up (release notes, fold-in, clean-out) | a plan file `.beast/wrapup/<slug>/plan.json` committed in the repo, one decision row `Decision: Wrap up <M>` approving it, a GitHub Release on the public repo (`wrapup.sh`) | the repo the milestone is on; the release on `publishes_to` |
| A seat's durable notes (what it must not relearn) | one comment `BEAST-NOTES seat=<login>/<LABEL>` on the seat's tracking issue, edited in place | the tracking issue's repo |
| A seat's home (the directory its sessions run in) | the roster row's `home` (`kind`, `branch`; `kind`, `dir` for a subdir); the local path is derived, and the home carries a machine-local `.beast/seat.json` | the roster; the machine |
| Live SendMessage addresses | `~/.beast/sessions.json`, machine-local, written by the seats skill | the machine |
| Hand-back | a pull request whose description carries the evidence section below | the repo |
| Contribution ledger | computed from merged PRs, reviews and closed issues per login | the daita-beast site (later) |

A Project can hold issues and pull requests from repositories under other owners (measured 2026-10-10: an issue of a repository under one owner added to a Project of another owner and read back). Linking a Project to a repository's sidebar is same-owner only and is cosmetic.

## Shapes

**Decision issue** (template `.github/ISSUE_TEMPLATE/decision.md`): title `Decision: <plain question>`; sections `## Decision`, `## Unblocks`, `## Waits`, `## Recommendation`, `## Approve with`, `## Record`. Every section non-empty. `decision.sh new --decides <owner/repo>` appends the line `Decides: https://github.com/<owner/repo>` to `## Decision` when the decided repo is not the one the row is filed in; there is no seventh section. A row is filed under a milestone (`--milestone`, below); each `--waits-on <ref>` appends `Waits on: <ref>` to `## Waits`. `Approve with` holds the exact phrase, one per row: `decision.sh new` refuses a phrase carrying `|` (a choice between options is a desk ask, `desk.sh ask --options`); any other wording from the decider is a question back. `decision.sh new` (and so `record`) reuses an OPEN `decision` issue of the repo with the identical title and the same `seat:` labels filed by the same login instead of filing a second, and returns only once the issues list shows the row it filed, so a rerun after a failure part-way never duplicates. `Record` cites where the words will be: the decider's answer comment, or a file committed in the repo; the close comment quotes the words verbatim. The board renderer parses these sections by shape and fails loudly on a body that lacks one.

**Workstream tracking issue** (template `workstream.md`): title `WS: <name>`; sections `## Northstar` (the definer's words, verbatim), `## Project`, `## Coordinating repo`, `## Repos involved`, `## Acceptance`, `## Seats`.

**Status report** (a comment on the tracking issue):
```
BEAST-STATUS seat=<login>/<LABEL> at=<UTC> state=working|blocked|done next=<the next critical-path act and when it is measured>

<evidence: what ran, exit codes, hashes, links to issues, PRs and records>
```
Posted at a blocker, a completion or a seam. Never a tick. A blocked report names the decision issue or the cross-repo issue it waits on.

**Ack** (a comment on a board row or a desk, one per seat per event):
```
BEAST-ACK seat=<login>/<LABEL> at=<UTC> state=seen|executed|blocked next=<the act and when it is measured>

<evidence or the blocker, optional>
```

**Hand-back** (a pull request description):
```
## What
## Evidence
<what ran and its exit code; served==built hashes where a deploy is involved; the negative control that failed before the fix>
## Review against the engineering rules
<the builder's own diff review: one owner per fact, no compat fences, fail loud, no hardcoded fallbacks>
## Closes
<issues this PR closes, decisions it consumed by number>
```
A PR without the evidence section is not hand-back ready.

**Roster** (`.beast/roster.json`): `repo` (private, never public-intended), `publishes_to` (optional: the public repo this repo is the private twin of; public on GitHub or public-intended), `public_intended` (optional: owners or `owner/repo`s that are public or will be; compared case-insensitively), `scrub` (optional: patterns the publish scrub gate refuses, besides its fixed classes: a regex string, applied to every text file, path name, commit message and body, or `{"pattern": "<regex>", "paths": ["<glob>", …]}`, applied only to text files and path names whose path matches a glob, Python `fnmatch` on the whole path with `*` crossing `/`), `scrub_allow` (optional: private repos' bare names that are also ordinary words; the bare-name class skips exactly those, their `owner/repo` is still refused; `scrub_allow_words` (optional: exact phrases of closed-row words that may publish, each one line of at least 5 words; the words class drops every stretch inside each phrase and nothing else), `roster_scrub` in `lib.sh` parses the three fields and dies naming a malformed entry), `license` (optional: the license every public repo of the roster's owners carries; its shape under License below), `coordinates` (one line), `seats[]` (`label`, `role`, `repo`, `lane`, `github`, `tracking`, `home`; the pair `github`/`label` is the seat's id and is unique; `home` is `{"kind": "checkout|worktree|wrapper", "branch": "<branch>" | null}` or `{"kind": "subdir", "dir": "<path relative to the checkout>"}`), `people[]` (`github`, `name`, `role`). Every home of a repo (its checkout, worktrees and wrappers) reads the main checkout's roster. The scripts read the roster from the repo's main checkout, never a worktree; try a roster change in a clone of the repo.

**Seat notes** (one comment on the seat's tracking issue, by the seat's login, edited in place by `notes.sh`):
```
BEAST-NOTES seat=<login>/<LABEL>
<one fact per line: where the home is, standing constraints, anything the seat must not relearn on another surface>
```
Two such comments for one seat are a defect: `notes.sh` names both and refuses to choose. A repo lists only the seats it legitimately coordinates with: the ecosystem index repo knows every seat, an app repo knows its own and its orchestrator.

## Seats and messages

A seat is a role held by one GitHub login under a label; its id is `<login>/<LABEL>` (for example `octocat/BUILDER`), and a label is unique per login, so two users may each hold a BUILDER and one user may hold several seats in one repo. The roster row carries `github` and `label`; the id is derived from them and never stored. Labels, acks, status headers, close comments, event lines and `~/.beast/sessions.json` all carry the id; scripts accept a bare LABEL where the roster resolves it to exactly one seat, and refuse it otherwise, naming the candidates. Displays shorten an id to its LABEL when the login is the viewer's own. Every row label is qualified (`relabel.sh --apply` qualifies bare ones). Comments written before a relabel can carry a bare `seat=<LABEL>` ack or status header or `Closed by seat <LABEL>`; those are read as the seat the label resolves to uniquely through the reading checkout's roster, and a bare label that does not resolve is named and dropped. A session holds a seat. Its first act is `/daita-beast:join <LABEL>`, which reads its own address from `ListAgents` and records it. Addresses change on every reload and are verified by a reply before anything is relied on. Inter-seat traffic is `SendMessage` at a seam, a blocker or a completion, nothing else; a cross-repo ask is an issue in the target repo. A human's words are relayed verbatim and labelled as theirs, never paraphrased.

## Two tiers: the board and the desks

The test: **would a development team put this on a PR or an issue for the lead's approval?** Yes: it goes on the **board**, as a pull request awaiting the decider's review (a code change) or a `decision` issue (an act without code: deploy PROD, release, spend, chain, secrets, scope, a design approval, ship-or-cut). No, it is a question you would ask the developer across the desk (what to name something, a rewording, which of two options, "did you mean"): it goes on the seat's **desk**, which never touches the board. An ask that turns out big is filed as a decision or a PR, and the ask is answered `→ <row url>`. Neither tier carries words the decider already gave in a session that need no explanatory content.

| | Board | Desk (one per seat) |
|---|---|---|
| holds | PRs for the decider's review; `decision` issues | asks (naming, wording, an option, a clarification); messages from seats or the decider |
| GitHub object | the PR (labels `needs-review` + `seat:<id>`, assignee the decider) or the `decision` issue | ONE issue per seat in its roster repo, labels `desk` + `seat:<id>`, assignee the decider |
| answered by | an assignee comment in one of the answer forms (below) | `BEAST-ANSWER n=<n> <option or text>` on the desk |
| record | the answer comment URL | the answer comment URL |
| visible on | the generated board and the board page | the desk's generated body; never in the board tables |
| written by | `pr.sh request`, `pr.sh close`; `decision.sh new`, `close`, `record` | `desk.sh open`, `ask`, `answer`, `withdraw`, `msg`, `publish` |
| read by | `board.sh`, `decision.sh inbox`, the relay | `desk.sh inbox` (and so `decision.sh inbox`), the relay |

**A PR on the board.** Every seat posts as the decider's login today, and GitHub refuses a review request to, or an approval by, a PR's own author, and does not notify a user of their own @mention. So `pr.sh request <pr> --seat <id>` labels the PR `needs-review` and `seat:<id>` and assigns the decider (the roster's `people[]` row whose role names "owner"; it dies when there is not exactly one, and `--assignee` names another). The PR's approving phrase is the first quoted phrase of a `## Approve with` section of its body, else `approve`; the decider answers with the decision forms (the phrase, `<phrase> — <comment>`, bare `approve`/`approved`, `revise: …`, `reject: …`). On approve the hearing seat runs `pr.sh close <pr> --merge --words … --record <answer url> --by <id>`: it merges (REST `PUT pulls/{n}/merge`) and dies naming GitHub's refusal (a conflict, a failing check) without commenting or closing; on reject `--rejected` closes it unmerged with the label `rejected`. Both write the same close comment as `decision.sh close` (one writer, `row_close_comment` in `lib.sh`), republish the board and print the row's seats.

**The desk.** `desk.sh open <id>` creates it once: it finds the desk by its labels through the issues list and dies when there are two. The issues list lags a create by seconds (measured 2026-10-15: a second `open` one second after the first minted a duplicate), so `open` returns only once the list shows the new desk; two `open`s of one seat run concurrently are not guarded. Comments, one fact each:
```
BEAST-ASK n=<seq> seat=<login>/<LABEL> at=<UTC> milestone="<title>"   desk.sh ask; n = the highest n on the desk + 1;
                                                     the milestone field is required while the desk's repo has an open
                                                     milestone, and an ask written before milestones has none
<the question, one or two lines>
options: a | b | c                                   optional
default: a                                           optional: what the seat does if no answer by its next seam
Waits on: <seat id | owner/repo#N>                   optional, one per dependency

BEAST-ANSWER n=<seq> <option or free text>           by an assignee of the desk, or posted by desk.sh answer, which adds
(words typed to <login>/<LABEL>'s session, verbatim)  this line when the decider typed the words to the seat's session

BEAST-WITHDRAW n=<seq>                               desk.sh withdraw: the seat withdraws its own open ask

BEAST-MSG from=<login>/<LABEL> to=<login>/<LABEL> at=<UTC>   desk.sh msg, on the recipient's desk
<the body>
```
A plain comment by an assignee is a message from the decider. An answer or withdrawal of no open ask, an ask or message for another seat, a malformed `BEAST-` line, and a plain comment by anyone else are named on stderr and dropped. The body is a view regenerated from the comments by `desk.sh publish` (every desk write publishes): a header line, "Open asks" (n, the question's first line, options, default, link), "Answered (last 20)" (withdrawn asks included), "Messages (last 10)". Nobody edits it, and the desk is never closed. The seat acks on its desk like on a row (`ack.sh <desk> --seat <id> --state seen --next …`); its desk inbox (`desk.sh inbox <id>`, printed at the end of `decision.sh inbox`) is every answer and every message newer than that ack.

## The board is a queue

Every board item (a decision, or a PR for review) is a message on the board before anyone acts on it, and nothing on the board's side of the test is decided off it. A seat enqueues (`decision.sh new`), the decider answers, the hearing seat closes on the words with the record. Anything a seat waits on from the decider is filed with `decision.sh new` before it is asked, and stays open until the word. `decision.sh record` (file and close in one act) is only for a significant word the decider already gave in a session before any row existed (scope, engine, ship-or-cut, release: anything that needs explanatory content), so it passes through the queue like every other; it is never used for a question the seat is about to ask, which leaves nothing pending on the board; a minor word (wording, copy, a link) is recorded verbatim in the repo's dated record with no row. The consumed log is the board's decided table (closed rows of the last 7 days with their words); the row keeps the words until its milestone's wrap-up folds them into the docs.

A row (a decision issue or a PR labelled `needs-review`) has the same queue mechanics. A row's **seats** are its `seat:<login>/<LABEL>` labels: every seat the decision affects. Its **latest event** is the newest of its creation, the decider's newest answer-form comment, and its close. Each seat **acks** for itself with one comment, `BEAST-ACK seat=<login>/<LABEL> at=<UTC> state=seen|executed|blocked next=<act>` (evidence below); a close by a seat is that seat's seen ack at the close (the close comment names its closer). A seat is **current** on a row when its newest ack is at or after the latest event, otherwise the row is in its **inbox**; a row is **consumed** when every seat is current after its close. The inbox is computed from GitHub alone (`decision.sh inbox`, or the connector recipe), so a seat on any machine or surface gets the same one; nothing is held locally. Delivery is at-least-once: the relay pushes an event line where a machine runs one (an optimization, never the contract), the inbox is the pull, and a seat de-duplicates by issue URL (an UPDATED whose last comment is the seat's own is its echo). A `revise:` is a new event for every seat. A row closed by mistake is reopened with a comment saying so; the close is withdrawn, never rewritten.

## Decisions

Decisions are repo- and project-specific, never Beast-wide. The seat that is blocked files the decision (`/daita-beast:decision`) BEFORE it asks the decider, in its home repo: `decision.sh new` files in the roster's `repo` unless `--repo` names another private repo, and `--decides <owner/repo>` names the repo the row decides (an app's decision names that app's repo, a platform decision the platform repo). A decider's board spans every repo they are assigned in and is published in one place (the roster's `board` repo), but a decision made on it is a rule only inside the repo it decides. A row is built from the current end of the record it cites, re-read at filing time, never from an earlier snapshot. It is assigned to the decider, carries a `seat:<login>/<LABEL>` label for every seat that waits on it, and is added to the workstream's Project.

The decider answers in either of two ways, and both are records: a comment on the issue in their own words (the comment URL is the record; GitHub stamps author and time), or the words typed to a session, which that session quotes verbatim in the close comment. The close comment quotes the words and cites the record. Four answers exist: **approve** (the issue's exact phrase; on the issue itself a bare `approve` or `approved` from the assignee counts the same, since the assignee and the issue are unambiguous there, while words typed to a session need the phrase to name the decision), **approve with comment** (`<phrase> — <comment>`, approves and shapes the act), **revise** (`revise: <what to change>`, not an approval: the seat answers on the issue and it stays open), **reject** (`reject: <reason>`, closed as not planned with the label `rejected`). A comment by anyone but the assignee is never an answer. Then the closing session tells each waiting seat one line (the words verbatim and the issue URL) by `SendMessage`, resolved through the roster; a seat that was not reachable finds the row in its inbox (`decision.sh inbox <SEAT>`, computed from acks) at its next wake. The decider answers by typing the approving phrase to the orchestrator or commenting it on the issue. The seat that hears the word closes the issue with the words verbatim and their record (the answer comment, or for words typed to a session the session's own account of them); the board republishes itself. A dated record file is not required: the words live on the row until the wrap-up. An act only the decider can perform carries `hands` and stays open until they report it done.

## Coordination stays private

A public product has a private **twin**: the roster's `repo`, whose `publishes_to` names the public repo. All work and coordination happen in the twin; the public repo receives only publishes. One guard in `lib.sh`, `coord_write_guard <repo> [<seat>]`, runs before the first API write of every coordination write: `decision.sh new`, `record` and `close`; every `desk.sh` write (`open`, and through `desk_of`: `ask`, `answer`, `withdraw`, `msg`, `publish`); `status.sh`; `notes.sh set` and `append`; `ack.sh`; `pr.sh request` and `close`; `board.sh --publish`; `workstream.sh new`; `milestone.sh new`, `move` and `close`; `report.sh milestone --post`. It exits 1 when the target repo is listed (or its owner is) in the roster's `public_intended`, or is public on GitHub (`repo_public_why`, the roster first, then the repo's visibility), naming the rule and the private repo to write in: the seat's roster repo, else the roster's `repo`. There is no override. A pull request on a public repo is not requested or closed through `pr.sh`: `publish.sh` (below) is the only writer to a public repo, and its writes are a publish's own (a push, the PR, its merge, its branch's deletion), never a coordination comment. Readers (`board.sh`, `decision.sh inbox`, `desk.sh inbox`, the relay) still read public repos' existing rows, so history renders.

`join.sh` (through `claude_block_render`) validates the pair with `roster_pair_check`: the roster's `repo` must be private and not public-intended, and `publishes_to`, when present, must be public or public-intended; either failure stops join, naming the field. When the roster has `publishes_to`, the generated CLAUDE.md block opens by naming the repo the private twin of the public one, with the publish steps. The block's protocol pointer is derived (`protocol_repo`): in a checkout of the plugin's own twin, its public repo once that repo, under its own name, carries `docs/protocol.md`, else the twin; in an installed copy without that roster, plugin.json's `repository`.

## Publishing

`publish.sh` (skill `/daita-beast:publish`), run in a checkout of the twin ("twin `main`" below is the twin's default branch on GitHub, "public `main`" the public repo's), is the only writer to the public repo, the roster's `publishes_to`. Its pushes go through one function (`public_push`, the remote `public`, never forced except the one sanctioned force-push, `request --amend`, leased on the PR's head) and its API writes through another (`public_send`, which refuses any path outside `repos/<publishes_to>/`); `coord_write_guard` is unchanged and still refuses every coordination write there. The public repo must exist under its own name before a publish (GitHub serves a renamed or transferred repo's old name as the new one, measured 2026-10-16, so a publish checks the name GitHub answers with); creating it is its owner's act.

1. `publish.sh prepare <slug> [--paths <path>… | --commits <sha>…] [--delete <path>]… --message-file <f>` adds (or checks) the remote `public` and fetches it, then builds ONE new commit in a temporary index on top of the public default branch: `--paths` takes each path as it is in the public view of twin `main` (the overlay, below; a path gone from it is deleted), `--commits` applies each named commit's own change (in topological order, oldest first, never by commit date; each must be on `main` and not a merge) and squashes them. The message is the file, written for outside readers; the author and date are new. The twin's history never travels. When the public repo is empty the branch is an orphan: an empty `Initial commit` root, then the publish commit. The license gate (below, License) and the scrub gate run on the commit before `publish/<slug>` is created: on a miss or a hit nothing is created.
2. **The scrub gate** (`publish.sh scrub <slug> [--body-file <f>]`; also inside `prepare`, `request` and `merge`) first checks the branch's shape: exactly one commit on its public base (the merge base with public `main`), or for an empty public repo the empty root plus one commit, which is what `prepare` makes. Any other branch is refused, naming its commit count: a scan of a longer branch's net diff would pass a phrase one commit adds and the next removes, and `request` would push both commits. A branch with no history in common with public `main` is refused in one line. One owner of the shape: `publish_base` in `publish.sh`. The gate then reads that commit's diff, its message (and the empty root's), and the PR body, and fails, listing every hit as `<file>:<line>`, `<path>: path name`, `commit <sha> message:<line>` or `body:<line>` with its class. The content classes read the added lines of every text file. A binary file (a NUL byte in its first 8000 bytes, the test git uses) is not read, and each one skipped is named on stderr. The classes:
   - **private repo**: an `owner/repo` (or its URL), in any case, of a private repo: every repo the roster names that GitHub reports private, and every private repo of every owner the roster names (its `repo`, `publishes_to`, `board`, seat repos and tracking refs), listed in full: an org's through `orgs/<o>/repos?type=private`, the gh login's through `user/repos`. A listing that fails, or another user's account, dies. The publish target and exact `public_intended` entries are excepted. A directory that is not a repo (a path inside a private repo) is not listed and goes in the roster's `scrub`.
   - **private name**: the bare name of each of those repos as a whole word, in its exact case (a twin's codename, an ecosystem index's paths). A name shorter than 5 characters is not checked bare, nor is a name in the roster's `scrub_allow`; their `owner/repo` still is.
   - **local path**: `/Users/<name>/` or `/home/<name>/`.
   - **BEAST- line**: a filled-in coordination line, one starting `BEAST-<WORD>` that carries no `<placeholder>` and no `$variable`.
   - **record path**: a `records/` directory under `org/` or `docs/`.
   - **words**: a stretch of 5 consecutive words, at least 2 of them outside a fixed common-word list (English stopwords and the protocol's verbs approve, publish, merge, close, revise, reject, record), of the words on a closed row of the twin (the verbatim words of every close comment on a closed `decision` or `needs-review` row). Words are letters and digits compared case-insensitively; whitespace and punctuation only separate them. A row whose close words are exactly its own approving phrase (its `## Approve with`) is skipped: that phrase is the protocol's, not the decider's prose. A phrase in the roster's `scrub_allow_words` is allowed: every stretch inside it is dropped, and nothing else. One owner of the rule: `WORDS_*` in `lib.sh`.
   - **roster scrub**: a regex of the roster's `scrub` list; a scoped entry only on the text files its globs match.
   - **path name**: every path the commit adds or changes, binaries included: a secret-shaped file name (`wallet.json`, `.env`, `.env.*`, `*.pem`, `*.key`, `id_rsa*`, `id_ed25519*`, `*.p12`, `*.pfx`, `keystore*.json`, `credentials*.json`, case-insensitive), and the private repo, private name and roster scrub classes applied to the path itself.

   One owner: `scrub_patterns` and the scanner `scrub_scan` in `lib.sh` (`publish.sh` runs them on a publish, `license.sh` on a license file's header); the roster's `scrub`, `scrub_allow` and `scrub_allow_words` are parsed by `roster_scrub` in `lib.sh`.

   **The stable contract** for any other tool is `publish.sh scan` and its output, never `lib.sh`, whose functions are internal and change with refactors. `publish.sh scan [--roster <file>] [--patterns-file <f>] (--base <ref> | --tree <dir>) [--paths <path>…]` runs exactly the classes above, through `scrub_patterns` and `scrub_scan`, on the diff `<ref>..HEAD` of the repo you stand in and those commits' messages, or on every file of a directory (`.git` excepted), only under `--paths` when given. It needs no twin checkout. stdout carries one line per hit: `<file>:<line> <class> <match>`, `<path>:0 path-name <match>` for a path, `commit-message <class> <match>` for a message; the classes are `private-repo`, `private-name`, `local-path`, `record-path`, `roster-scrub`, `beast-line`, `words` and `path-name`. It exits 1 on any hit, 0 when clean, and 2 on a usage or pattern error. `publish.sh scan [--roster <file>] --dump-patterns > f` writes the pattern bag (the JSON `scrub_patterns` builds, `"bag": "beast-scrub-patterns/1"`); `--patterns-file f` reads it, so a scan runs with no network.
3. `publish.sh request <slug> --seat <SEAT> --body-file <f>` re-runs the license gate, re-scrubs the branch and the body, pushes the empty root as the public default branch when the repo is empty, pushes `publish/<slug>`, opens the PR on the public repo with the body (an existing open PR from the branch is reused), and files the approval row in the twin (`decision.sh new`, the home repo, `--decides <public>`, the PR's URL in Decision and Record, approved with `publish <slug>`). Beast writes nothing else on the public repo: no label, no assignee, no comment.
4. **Amend** (the decider widened or narrowed a publish after its PR opened). `publish.sh prepare <slug> --amend [--paths … | --commits …] [--delete …] --message-file <f>` rebuilds the slug's ONE commit on the public base as it is now and reruns the license and scrub gates; it is refused when the slug was never requested (no row of its title in the twin), when its row is closed, and when nothing changes. `publish.sh request <slug> --amend --seat <SEAT> [--body-file <f>]` re-gates, then force-pushes `publish/<slug>` with `--force-with-lease` on the open PR's head: the one sanctioned force-push, through `public_push` only. It is refused when the PR branch is not one publish commit on its base (someone else pushed to it). It retitles the PR (and replaces its body when given), then posts ONE line on the twin row: `Amended at <UTC>: <n> files; added <list>; removed <list>; changed <list>` (relative to the replaced commit; each list cut after 8 with a count; `amend_line` and `row_amended_at` in `lib.sh` own the shape). If that line fails to post, rerunning `request --amend` posts it. An approval no newer than the row's latest amend line approved what the amend replaced: `row_answer_url` reads it as not approved and names the amend time, and `merge` on an amended row takes its approval only from the decider's comment on the row (`--record` is refused).
5. The decider answers on the twin's row. `publish.sh merge <slug> --words "<verbatim>" --by <SEAT>` takes the record from the decider's answer comment on the row (`--record` for words typed to a session, recorded first). On the approving forms it refuses when public `main` carries anything twin `main` lacks (run `pull` first), re-scrubs, squash-merges the PR (its title and message the commit's), deletes the public branch, records the new public `main` as merged into twin `main` (a merge commit carrying twin `main`'s own tree, so the next `pull` brings only outside changes; push it), deletes the local branch and closes the row on the words. On `reject: …` it closes the PR unmerged, deletes the branch and closes the row rejected; `revise: …` is not a close.
6. `publish.sh release <tag> --title <t> --notes-file <f> [--check]` scrubs the title and the notes and creates a GitHub Release on the public repo at its default branch; `--check` only scrubs. An existing release of that tag with the same title and notes is reused; one that differs dies. `wrapup.sh run` publishes a milestone's release notes through it.
7. `publish.sh pull` merges the public default branch into twin `main` (outside contributions), where `main` is checked out with a clean tree; on a conflict it aborts the merge, names the conflicted files and leaves `main` unchanged. A twin that has never recorded a publish shares no history with its public repo; it is told to record the baseline once (`git merge -s ours --allow-unrelated-histories public/main`) after checking that twin `main` carries everything public has.

**The overlay.** A file `.publish/<p>` on twin `main` publishes as `<p>` at the public root, replacing the twin's own `<p>`: a twin keeps its own instructions and publishes the public version beside them. The twin's root `CLAUDE.md` never publishes; a public `CLAUDE.md` is `.publish/CLAUDE.md`. `--paths .publish/<p>` and `--paths <p>` name the same public path, and a twin path the overlay shadows is never taken from the twin. One owner, `publish_view` in `publish.sh`, decides which twin file publishes at which path. The scrub gate reads the publish commit, so it runs on overlay files at their public paths. `--commits` refuses a commit that touches the root `CLAUDE.md`, `.publish/` or a shadowed path, and names them: publish those with `--paths`.

**Deleting from the public repo.** `prepare --delete <path>` (repeatable; alone or with `--paths` or `--commits`) removes a path from the publish commit's tree while the twin keeps its own copy: a twin-only file, such as the committed `.claude/skills/beast/SKILL.md` coordination pointer, that the public repo must not carry. One source of truth per path: it is refused when the path overlaps a `--paths` item or is shadowed by a `.publish/` overlay file, and when public `main` does not carry it (nothing to delete). The commit message gains a paragraph `Removed from this repository:` listing the paths, and prepare prints them for the PR body.

## License

The roster's `license` names the license every public repo of the roster's owners carries, and its one canonical source:

```json
"license": {
  "name": "Acme Community License, version 1",
  "file": "LICENSE.md",
  "manifest": "SEE LICENSE IN LICENSE.md",
  "source": {"repo": "acme/legal", "path": "licenses/acme-community-v1.tex", "render": "pandoc -f latex -t markdown_strict --wrap=none", "checkout": "/path/to/a/checkout/of/acme/legal"},
  "vendored": ["site/vendor"]
}
```

`vendored` (optional) lists directories that hold byte-exact copies of upstream packages: their `package.json` and plugin manifests are the upstream's, not ours, so the manifest check skips them. Every other tracked `package.json` and `.claude-plugin/plugin.json` in the tree must carry `manifest`; `node_modules` is never read.

`name` is the display name (one line, no `--`); `file` the path the license lives at in each repo; `manifest` the value of `"license"` in `package.json` and every `.claude-plugin/plugin.json`. `source.render` is optional: a shell command that reads the source on stdin and writes the license text; without it the source is copied as it is. `source.checkout` is optional: an absolute path to a checkout of `source.repo` on the owner's machine, read at its `HEAD`; without it the source is read through the GitHub contents API. `roster_license` in `lib.sh` is the one parser and dies naming a malformed part.

`license.sh` (skill `/daita-beast:license`) is the one owner of license checks; it reads and never writes to GitHub.

- `license.sh render [-o <file>]` writes the expected file: one neutral header line, `<!-- <name>. Rendered from its canonical source; do not edit by hand. -->`, an empty line, then the render. The header names no repo.
- `license.sh check <dir | tree-ish>` checks a directory or a tree-ish of the repo it runs in, item by item, and exits 1 naming each miss: the file is present; what follows its header (the leading HTML comment) and the empty line equals the render byte for byte; the header is the neutral line and the scrub gate (`scrub_patterns`, `scrub_scan`) finds nothing in any line of it; `package.json` and every `.claude-plugin/plugin.json` say `"license": "<manifest>"`. A directory inside a git work tree is read through its tracked files only (`git ls-files`), so untracked and ignored paths, nested worktrees and `node_modules` are never read; a directory outside one is walked (`.git` and `node_modules` pruned), and stderr says so.
- `license.sh audit` runs the same checks over every public repo of every owner the roster names (`roster_repo_owners`: its `repo`, `publishes_to`, `board`, seat repos and tracking refs), at each default branch, through the REST API (a git tree and its blobs; no clone), and prints one table: repo, license file, body matches, header clean, manifests, and the twin seat (the rostered seat whose repo is the private twin that publishes to it, from that repo's roster). It exits 1 when any row misses or cannot be read.

**The license gate.** When the roster has `license`, `publish.sh prepare` and `request` run `license.sh check` on the publish commit and refuse a publish whose public tree misses: prepare creates no branch, request pushes nothing. A twin fixes a miss in itself: `license.sh render -o <file>` and a manifest edit, committed on twin `main`, then `publish.sh prepare <slug> --paths <file> package.json <plugin manifests> --message-file <f>`.

The `license-reviewer` agent runs `audit` and `check` and reports each public repo missing or drifting, with the seat that owns the fix and its publish steps; it never writes, posts or publishes.

## Watching

Seats are told by the machine's relay, a scheduled job (`/daita-beast:relay`, launchd every 120 s): one GitHub search per tick for every roster seat together (`watch.sh --roster --once`), asking only for rows updated since the oldest seat's high-water mark minus an hour (`~/.beast/watch/<login>/<LABEL>.mark`, the start of its last good poll and the query it ran; a seat without one makes the tick a full one: every open row and the closed ones of the last two days), and only when a row labelled `seat:<login>/<LABEL>` changed (a decision, a PR labelled `needs-review`, or the seat's desk: a new ask, answer or message is an UPDATED; a new comment that is only bookkeeping, a `BEAST-ACK`, `BEAST-STATUS` or `BEAST-NOTES` line, a close comment or a publish `Amended at` line, is not), a disposable Haiku session whose only tool is SendMessage sends that seat its event line (`BEAST-EVENT kind=NEW|DECIDED|UPDATED seat=<login>/<LABEL> <title> <url>`, DECIDED carrying the close comment's first line) and nothing else. It runs in the seats' permission mode: a receiver holds a message from a sender in another mode and never tells a one-shot sender, so the relay log says queued, never delivered. No seat holds a monitor; when nothing changed, nothing but the poll runs. A seat whose address is not recorded is not sent and loses nothing: its inbox is computed from the rows' acks. Nothing is pushed by GitHub itself while every seat shares one login; the day collaborators have their own logins, a co-assignee gets GitHub's own notification.

## Reading GitHub

One REST quota (5,000 requests an hour) is shared by every seat, the relay and the board of a login, so the plugin reads GitHub conditionally and never re-reads what has not changed. As built in `lib.sh`:

- Every read is `gh_get` (one page) or `gh_get_all` (every page, 100 a page, a full page followed by the next); `row_read <repo> <N>` is the issue and its comments as one JSON, the read the board, the inbox and the desks derive acks, events and words from. Every write is `gh_send`. No other `gh api` call exists in the plugin.
- A read's ETag (or Last-Modified) and body are kept per gh login in `~/.beast/cache/<login>/` (`BEAST_CACHE_DIR` moves the root), written atomically; the next read of the same URL sends `If-None-Match`, and GitHub's 304 serves the cached body without charging the quota (measured 2026-10-15: `gh api -i` prints `HTTP/2.0 304 Not Modified` and the headers with an empty body, exits 1 with `gh: HTTP 304`, and the core `used` count did not move). Every read asks GitHub; the cache never answers alone, so a write is seen by the next read, and an empty cache (a cloud session, Cowork) only costs more.
- A cache entry that does not parse is named on stderr and the read asks GitHub unconditionally and replaces it. A gh failure names the call (`daita-beast: gh <METHOD> <path> failed (exit N…): <gh's words>`), and a body that is not JSON is named as a truncated response and never used or cached.
- What bumps an issue's `updated_at` (measured 2026-10-15): adding a comment and deleting one do; **editing a comment does not**. So no read is skipped on an unchanged `updated_at` (it would serve an edited answer stale), and comments are not read with `since=` (it shows edits but cannot show a deletion; the per-page ETag already charges only the changed pages).
- Search has no ETag (`Cache-Control: no-cache`) and is never cached; it draws on its own quota (30 a minute). The search index lags a write by seconds to minutes (measured: 10 s for one comment; a decision issue created at 23:29:42Z was absent from an `updated:>=` search at 23:35:48Z); the relay's hour of overlap covers it. The issues list lags a create by seconds too (measured: absent at +0 s, listed at +6 s).
- `BEAST_CALL_LOG=<file>` appends one line per request: time, status, `charged=yes|no`, quota (`core`, `search`, `write`), path. Measured with it on 2026-10-15: `board.sh --assignee <login>` costs 307 core cold and 0 core warm (318 requests answered 304; only its 3 searches are charged), byte-identical output; `decision.sh inbox` for five seats costs 15–145 core cold and 0 warm.

## Surfaces

The protocol is the same everywhere; the transport and what can run differ. The install skill detects the surface from evidence and does only that surface's setup.

| | Claude Code, local | Claude Code, cloud | Cowork / Claude.ai chat |
|---|---|---|---|
| Install | the DAITA marketplace (`/plugin marketplace add DeSciX/DAITA`, `/plugin install daita-beast@daita`), then `/daita-beast:install` | nothing installs; the repo's committed `.claude/skills/beast/SKILL.md` (written by bootstrap) points at a shallow clone of the plugin | Customize › Plugins › marketplace `DeSciX/DAITA` › `daita-beast`; chat loads skills and the connector only |
| GitHub | `gh` as the person, REST helpers in `lib.sh` | the sandbox proxy: REST only (Projects refuse, pinning warns), attached repositories only | the GitHub connector, installed per account (`docs/connector-access.md`); recipes in the `connector` skill |
| Permissions | the plugin's PreToolUse hook allows its own scripts, bare; nothing else changes | the session's own | the connector's consent |
| Hears a decision | the relay (messenger in the seats' permission mode, `relay.permissionMode` in the roster) | pulls: inbox at every wake | pulls: the inbox recipe; the decider uses the board artifact |

## Seat homes

A seat's home is the directory its sessions start in. Claude Code keys auto-memory, the CLAUDE.md it loads and the repo agents it sees off that directory, so two seats never share a home. `seat.sh new <LABEL> --role "<text>" --tracking <owner/repo#N>` (skill `/daita-beast:seat`), run from the repo's main checkout, adds the roster row and creates the home. The row stores only the portable part, `home: {kind, branch}`. The local path is derived from the kind by one function, `seat_home_path` in `lib.sh`:

| Kind | Path | Branch | Chosen when (unless `--kind` is given) |
|---|---|---|---|
| checkout | the repo's main checkout | whatever is checked out (`null`) | no other seat of this login is homed in the checkout |
| worktree | `<repo-parent>/<repo>.seats/<LABEL>` | `seat/<LABEL>` (re-used when it exists) | the checkout is taken and the repo has no submodules or nested git repos |
| wrapper | `~/.beast/homes/<login>/<LABEL>` | `null` | the checkout is taken and the repo has submodules or nested git repos (a worktree would not carry them) |
| subdir | `<checkout>/<dir>` (roster `dir`, no `branch`) | whatever is checked out | never picked: `--kind subdir --dir <dir>`, a directory of the checkout that is not a repo root, is not inside another repo, has its own CLAUDE.md and homes no other seat |

Every home carries `.beast/seat.json` (`{"id", "kind"}`, and for a wrapper `"root"`, the checkout it wraps); everything else about the seat is read from the roster. It is machine-local: checkout and worktree homes ignore it in their `.gitignore`, a subdir home as `<dir>/.beast/seat.json` in the checkout's. A wrapper holds a `CLAUDE.md` that is `@<checkout>/CLAUDE.md`, a blank line and the Beast block, and an executable `claude.sh` that runs `claude --add-dir <checkout>` from the wrapper. The launcher is the way into a wrapper: `--add-dir` loads the repo's agents, skills and the imported CLAUDE.md, while `permissions.additionalDirectories` in settings loads none of them and the import is denied (measured 2026-10-15, twice, with a negative control). `seat.sh new` refuses a home path that exists and is not this seat's, a checkout that already homes another seat, and a `seat/<LABEL>` branch checked out elsewhere (it names the path, and says when that tree has uncommitted changes). `seat.sh where <seat>` prints the home and kind on this machine; `seat.sh retire <seat>` sets the role to `retired: <date>` and removes nothing.

The plugin's SessionStart hook (`seat-hello.sh`) reads `$PWD/.beast/seat.json` for the seat's id and the roster for everything else (its tracking issue included). In a home (the seat's derived home is `$PWD`) it adds context naming the seat, its first act (`join.sh`) and its handoff duty; after a compaction (source `compact`) it leads with "post the handoff now". Anywhere else in a checkout with a roster, it names the homes of the roster's seats of the gh login that work in this checkout's repo, to reopen the session there; with none, and outside a checkout, it prints nothing. A fault (a malformed seat.json, gh without a login) is put into the context, named. There is no PreCompact reminder: Claude Code discards a PreCompact hook's `systemMessage` and `continue` fields, and its only control is blocking the compaction.

## Joining a seat

A seat joins, and rejoins after every reload or compaction, with one command from its home: `join.sh <SEAT>` (skill `/daita-beast:join`). It refuses a session outside the seat's home and names the home (`open the session in <home>`): one seat per directory, so a subdir seat never joins from the checkout root nor a checkout seat from a subdir. It then checks the seat is in the repo's roster with its workstream tracking issue (a new seat is created by `seat.sh new`, never by join), records the session's address, regenerates the Beast block in the CLAUDE.md the home loads (the repo's for a checkout or worktree home, the wrapper's own for a wrapper, the subdir's own for a subdir) from `plugin/templates/claude-block.md` (the only Beast text a seat's repo carries, never hand-edited), lists the home's auto-memory files that duplicate GitHub state, and ends with the seat's handoff, notes and inbox. A roster row without a `home` is read as a checkout home, and join says once to record it with `seat.sh new <SEAT> --kind checkout`. A role change is `join.sh <SEAT> --role "<text>"`; a retirement is `seat.sh retire`.

## Seat memory

Four kinds, four owners. The ROLE (obligations, tools, invariants) is the repo's agent definition and CLAUDE.md, served by the repo and shared by every seat of that role; a session never carries it. The SEAT's working state (what it does, waits on, leaves behind) is its `BEAST-STATUS` comments on its tracking issue: a `handoff` before a compaction, reload or surface switch, `resume.sh <SEAT>` after (the newest handoff, the notes, decisions decided meanwhile, open ones waiting). The seat's durable facts, the things it must not relearn on another surface, are its one `BEAST-NOTES` comment (`notes.sh <SEAT> show|set|append`). Lessons about a repository belong to the auto-memory of the seat's home, a cache on one machine that is never the only copy of anything another surface needs. The `seat-clerk` agent drafts a seat's inbox digest, acks, handoff and memory triage, and posts nothing.


A specialist the seat hires (an agent in the home repo's `.claude/agents`) keeps its own memory by declaring `memory: project`: `.claude/agent-memory/<name>/` in the repo, committed, loaded into that specialist only. Seat working state never goes there; specialist memory holds what the specialist learns about its craft in this repo.
## Workstreams

Opened with `/daita-beast:workstream`: one Project (private by default), one tracking issue, and at least one milestone (`--milestone "<title>|<YYYY-MM-DD>|<what it delivers>"`, created on the coordinating repo before anything else is written; the tracking issue's `## Milestones` section links the repo's milestones page). Work items are the issues and PRs the work produces, added to the Project. Acceptance is stated at opening and measured at closing; the final `done` status carries the evidence. Residue (branches, worktrees, fixtures) is the seat's defect, cleaned before `done`.

## Milestones and dependencies

A seat sets out its own milestones and moves them itself, so it schedules its work rather than waiting to be asked. A milestone is a GitHub milestone on the repo its items live in; a seat's are on its home. The shape has one owner, the `milestone_*` functions in `lib.sh`:

- **Title**: one line, no `"` (the ask header quotes it) and no `|` (`workstream.sh --milestone` splits on it).
- **Due date**: GitHub's `due_on`, the only copy. It is written at 12:00 UTC: measured 2026-10-16, a `due_on` of `T00:00:00Z` is stored as the day before, `T12:00:00Z` keeps the date; every write reads the stored date back and dies when it differs.
- **Description**: fixed lines, written only by `milestone_desc`: `Delivers: <one line>`; `Moved: later|earlier — <why>` (the latest move only, no history); one `Waits on: <ref>` per dependency; `Report: <one line>` (the latest participant report's summary).

`milestone.sh` (skill `/daita-beast:milestone`): `new <title> --due <date> --delivers <text> [--waits-on <ref>]...` (an identical rerun reuses the milestone; one that differs dies naming it), `list`, `move <title> --due <date> --why <line>` (a move carries its why), `close <title> [--carry <next>]`. `close` refuses while open issues or PRs are filed under the milestone, or open desk asks name it in their header, naming each; `--carry` files them under the next open milestone (an ask's header is edited in place and its desk republished) and closes.

**Every row, ask and PR names one.** `decision.sh new` (and so `record`), `desk.sh ask`, `pr.sh request` and `publish.sh request` take `--milestone "<title>"` and refuse an item without one while the repo it is filed in has any open milestone, listing them (`milestone_require`); the milestone is GitHub's own field on the issue or PR, and on a desk ask the header's `milestone="<title>"`. `publish.sh request` files its approval row in the twin under the twin's milestone and checks it before anything is pushed; nothing is set on the public PR.

**Dependencies as data.** `--waits-on <seat | owner/repo#N>` (repeatable) on `decision.sh new`, `desk.sh ask` and `milestone.sh new` writes one line per dependency, `Waits on: <ref>` (`waits_on_line`; `WAITS_ON_RE` is the one shape, read by `waits_on_parse` and `desk_parse`; a `Waits on:` line that is not the shape fails loud). `deps.sh <SEAT>` (skill `/daita-beast:deps`) reads the declarations on the seat's open decision rows in its home, its open desk asks and its home's open milestones (`deps_declared`), and measures each (`dep_state`):

| State | A row (`owner/repo#N`) | A seat |
|---|---|---|
| released | closed completed, not rejected; a PR merged | no open milestone in its home and a closed one (the latest) |
| delayed | open, and its milestone is overdue or was moved later (the why) | its soonest open milestone is overdue or was moved later |
| changed direction | closed not planned or labelled `rejected`; a PR closed unmerged; open with the decider's newest answer `revise:` | — |
| waiting, on time | open and not late | its soonest open milestone is not late |
| waiting, no milestone | — | its home has never set a milestone |

A changed direction carries the row's link, and the first line of the words only when the reader's home is the row's own repo: the words stay in the home where they were said.

**Due flags.** `decision.sh inbox` opens with the seat's home milestones due within 3 days or overdue, one line each (nothing when none is); `board.sh` adds a section `## Milestones due within 3 days or overdue` for the roster's home repos, naming the seats homed in each; the Cowork page flags them on the desk chips (`docs/board-ui.md`), reading them off the rows it fetches, since the GitHub connector has no tool that lists milestones.

## Participant report

At a milestone's close, `report.sh milestone <title> [--repo <owner/repo>] --post --by <SEAT>` (skill `/daita-beast:report`) sends ONE report addressed per participant, so nobody searches the traffic to learn that what they wait on has released, slipped or changed direction. Participants are every seat of the roster plus every outside contributor (a login holding no seat) awarded on the milestone's items. A section says:

- what the participant earned this milestone: the `BEAST-AWARD` comments on the issues and PRs filed under it, read through `ledger.sh` for every month the milestone spans, in the token of the checkout's `.beast/award-policy.md` (a repo without one awards nothing, and the section says so). An award goes to a login; it counts for a seat of that login when the item carries the seat's label, and is named in the summary as unattributed otherwise. A ledger run that drops a comment stops the report: a report with holes is never sent;
- the state of each thing it waits on (`deps_declared` and `dep_state`, the measure `deps.sh` prints).

Where it is kept: each seat's section is a `BEAST-MSG` on its desk (`desk.sh msg`, from `--by`), and the milestone's description keeps the summary as its one `Report:` line (the latest only). Records and dated files are deleted at wrap-up, so no report file is written. Every seat must have a desk; the script checks before its first write and refuses naming the seats without one. An outside contributor has no desk: their section is printed for the seat to deliver (public release notes come with wrap-up). Without `--post` the script prints every section and writes nothing.

## Wrap-up

A decision recorded against a past release can be active drift against the current one, and a board with hundreds of spent comments hides the open ones. At a milestone's end, `wrapup.sh` (skill `/daita-beast:wrapup`) folds what the milestone decided into the docs, publishes release notes, and deletes the milestone's coordination traffic. Run it in a checkout of the repo the milestone is on (default: the roster `repo`). Deleting an issue needs admin rights and cannot be undone. So the plan is approved on a row first, and the run deletes nothing the approved plan does not list.

1. `wrapup.sh plan <M> [--carry <next>]` reads GitHub and writes `.beast/wrapup/<slug>/plan.json` in the checkout, posting nothing. Its cutoff is the plan's own time. It lists three things:
   - **delete:**
     - the closed `decision` rows filed under `M`;
     - the coordination comments of the closed `needs-review` PRs under `M` (`BEAST-` lines and close comments; GitHub cannot delete a PR);
     - on the repo's desks, every ask answered or withdrawn, with its answer, when it is under `M` or under no milestone and answered before the cutoff, and every message older than the cutoff;
     - on the tracking issues of the seats homed in the repo, the `BEAST-STATUS` and `BEAST-ACK` comments older than the cutoff, except each seat's newest handoff;
     - the files under a records directory (`RECORD_PATH_RE`) that a closed row names in its `## Record` or close comment and that exist on the default branch;
     - the plan's own directory.
   - **keep:**
     - the open items under `M` (issues, PRs, open asks naming it), carried to `--carry`, by default the soonest other open milestone; the plan dies when there are open items and nowhere to carry them;
     - closed issues that are not board rows;
     - each seat's newest handoff;
     - every `BEAST-NOTES`.
   - **fold in:** each closed row's url, title, state, words and record, and the milestone's `Report:` line.

   One owner of the shape: `plan_build` and `plan_check` in `wrapup.sh` (`beast-wrapup-plan/1`).
2. `wrapup.sh request <M> --seat <SEAT>` commits the plan file to the default branch through the contents API (that one path), removes the local copy, and files one row, `Decision: Wrap up <M>`, approved with `wrap up <M>`. The row's Decision carries `Plan: <blob url at that commit>` and `Plan digest: sha256:<hex>`. It is filed under the plan's carry milestone (else `M`), so the next wrap-up deletes it.
3. **The fold-in** (the realign skill, scope b): `wrapup.sh brief <M>` prints the rows. The seat writes each into the as-built docs and instruction surfaces, deleting what it supersedes, and commits the doc changes in ONE commit whose message cites the url of every row it folded. A row with nothing to fold is listed in the same commit as `dropped: <url> — <why>` in `.beast/wrapup/<slug>/fold-in.md`. A red-team or investigation record survives only if the fold-in writes its useful content into the docs.
4. `wrapup.sh run <M> --words "<verbatim>" --by <SEAT> --fold-in <sha> [--notes <f>] [--tag <tag>]` checks everything before writing anything. It refuses:
   - when the words do not approve;
   - when the decider's standing answer on the row is not the approve (`row_answer_url`, the reader `publish.sh merge` shares);
   - when the plan at the linked commit does not carry the digest;
   - when the fold-in commit is not on the default branch;
   - when a closed row of the plan is neither cited by its url in the fold-in commit's message nor dropped in its manifest (each such row is named);
   - when rows are cited but the commit changes no file outside the plan's directory;
   - when the release notes fail the scrub gate.

   Then it writes, in order:
   1. the release notes, by default the merged PRs' titles, the approved decisions' titles and `report.sh milestone <M> --outside-notes` (the outside contributors, without private links), as a GitHub Release on `publishes_to` through `publish.sh release` (tag: the milestone's slug), or printed when the roster has no `publishes_to`;
   2. the deletes, each through `wrapup_delete`, the one delete of the plugin, which asserts the target repo is the plan's, re-reads the target and logs one line to stdout and `.git/beast/wrapup-<slug>.log`. Issues go by GraphQL `deleteIssue` (closed ones only, the node id the plan names), comments by REST, and the files (records and the plan's directory) by one commit on the default branch through the git data API. An item already gone is logged and skipped, so a rerun completes an interrupted run;
   3. the desks of the plan republished;
   4. `milestone.sh close <M> [--carry <next>]`, before the row's close, so an interrupted run is rerun on the still-open row (its re-check after a carry re-reads for up to 60 s: the issues list lags a milestone change);
   5. one comment on the `--by` seat's tracking issue, `milestone <M> closed: <release link>, <n> rows folded[, <d> dropped]`, posted once (a rerun finds it);
   6. the row closed on the words, which republishes the board;
   7. the DeSciX KB manifests (`.descix/manifests/*.json`) whose sources cover a file the fold-in or the deletes changed, each with `npx -y -p @descix/cli@3.0.0 descix kb corpus sync -a <app> -k <kb>` (dry run first) for the seat to run after pulling and pushing.

## Realign

The realign skill (`/daita-beast:realign`, scripts in `plugin/scripts/realign/`) is the procedure the fold-in follows, and the same procedure for a person's own agentic system. It anchors to what is built, folds each live rule into its instruction surface or doc, deletes what has drifted (never annotates it), never touches protected paths, and leaves a report as the next window's seed. It has two scopes:

- **(a) personal system:** every `CLAUDE.md`, the agents and skills, `docs/`, memory, the dated records and the KB corpora, after any significant milestone. A record whose rule is live becomes one line on its instruction surface; a spent one is deleted.
- **(b) workstream:** the wrap-up's fold-in above, ending in the fold-in commit and its manifest.

## Contribution ledger (later phase)

A view computed from GitHub's own data, never a second ledger: merged PRs, reviews and closed issues per login per repo, over the repos a community lists. It renders on the daita-beast site and feeds the platform's contribution tracking by reading events, not by asking anyone to report them.
