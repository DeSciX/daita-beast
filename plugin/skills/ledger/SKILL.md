---
name: ledger
description: Regenerate a community's monthly award ledger from GitHub (every BEAST-AWARD comment by a repo admin or maintainer on an `awarded` issue or PR) as awards/YYYY-MM.jsonl and .md in the community repo, and emit it as the CSV sheet the DeSciX Offers import reads. Use for "make the offers sheet", "build the October ledger", "how much has @login been awarded", "publish the awards".
---

# ledger — the generated roll-up, never hand-edited

```
${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh --community ACME --repos acme/ACME,acme/acme-widgets --month 2026-10 --out <path to the community checkout>/awards
```
Rows are kept only when the comment parses, its token is the community's, it was made in the month, and its author is an admin or maintainer of that repo (checked live). Every dropped comment is named on stderr with the reason and the script exits 2, so a roll-up with holes is never published by accident: fix the cause (a wrong token, a malformed comment, an author without the role) and rerun. A role that cannot be read (a 403: your gh login lacks push access to the repo) stops the run with exit 1 before anything is written, naming the repo, the login and the 403: rerun with a login that has push access.

A ledger bound for a public repo lists only public repos: when `--out` is in a checkout of a public or public-intended repo, a private repo in `--repos` is refused before anything is read, naming it. Its awards stay in a private ledger (an `--out` in the private repo's own checkout). A public ledger is the community repo's, so every repo in `--repos` must be listed in that repo's `.beast/awarders.json` for the token; an unlisted one is refused before anything is read, naming the file and the entry (`/daita-beast:award`, Token authority).

Publishing is the community owner's commit of `awards/<month>.jsonl` (repo, item, to, token, amount, for, ref, by, at) and `awards/<month>.md` (per-login totals and the award list) to the community repo.

Every row's `ref` is the award's own `ref=`, or the awarded item's URL when the comment has none: no row has an empty `ref`. A `ref=` present but empty or not an https URL stops the run with exit 1 before anything is written, naming the item, the author and the value: edit the comment to a full `ref=<https url>`, or remove `ref=`, and rerun.

## The offers sheet: awards to DeSciX offers

```
${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh --community ACME --repos acme/ACME,acme/acme-widgets --month 2026-10 --out <community checkout>/awards \
  --sheet ~/descix-offers/acme-2026-10.csv --emails ~/descix-offers/emails.csv [--batch <name>]
```
Writes the same award rows as the CSV the DeSciX platform's Offers import reads: header `contactemail,token,new_amount,batch,wallet_address`, one row per award, `new_amount` the award's plain decimal (no separator, no symbol), `batch` `awards-<month>` unless `--batch`, `wallet_address` always blank (the wallet binds when the recipient accepts the offer in Powch). RFC 4180 quoting, LF line ends. Upload it to the platform's Offers import; the recipient accepts in Powch and the airdrop settles.

`--emails` is the login→email map, the platform's data in a file you own: a CSV with the header `login,email` and one `<login>,<email>` per line, no quoting, logins case-insensitive. A missing header, a bad line, a malformed email, a login listed twice or a header-only file dies naming the line, before GitHub is read. An awarded login with no email refuses the whole run, naming every unmapped login, and nothing is written (no sheet, no `.jsonl`, no `.md`): add the lines and rerun.

The sheet carries email addresses: `--sheet` must be outside every git checkout, gitignored or not, else the run is refused before anything is read. Keep the map file out of every repo too. A run that drops a comment still writes the sheet (dropped comments are not awards) and exits 2.
