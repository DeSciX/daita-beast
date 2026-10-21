# Award policy — <owner/repo>

Token: <TOKEN> (awarded amounts reach holders as offers: ledger.sh --sheet, then the platform's offers import).
Community: <COMMUNITY> (the repo that holds the <TOKEN> community: its `.beast/awarders.json` lists the repos that may award <TOKEN>; a repo it does not list awards nothing).

Awards are the owner's word, recorded as a `BEAST-AWARD` comment by a repo admin or maintainer on the pull request or issue, and rolled up monthly into the community repo's `awards/<YYYY-MM>.jsonl`.

| Work | Award | Note |
|---|---|---|
| Bounty submission accepted (PR merged) | the bounty amount, or more at the owner's discretion | the bounty is the floor |
| Bounty submission not accepted, good effort | at the owner's discretion | typically a fraction of the bounty |
| Merged PR without a bounty | at the owner's discretion | per PR |
| Review that led to a change | at the owner's discretion | per review |
| Decision executed by a seat | at the owner's discretion | per decision closed and executed |
| Monthly most-active maintainer (merged PRs, reviews, decisions executed) | at the owner's discretion | one per month |

Who may award: repo admins and maintainers. A comment by anyone else is dropped by the ledger, loudly.
Period: calendar month, UTC. Published: `awards/<YYYY-MM>.md` and `.jsonl` in the community repo.
