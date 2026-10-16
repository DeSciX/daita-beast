#!/usr/bin/env bash
# deps.sh — what a seat waits on, and the state of each, computed from GitHub.
#   deps.sh <LABEL | login/LABEL>
# The seat's declarations are the "Waits on: <seat id | owner/repo#N>" lines (waits_on_line, lib.sh) of its open decision
# rows in its home (labelled decision + seat:<id>), its open desk asks, and its home's open milestones (deps_declared).
# Each ref is measured by dep_state (lib.sh, the one measure, shared with report.sh milestone): released, delayed,
# changed direction, waiting, on time, or waiting, no milestone. One line per declaration:
#   <ref>  <state>  <detail>  (declared on <url>)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

[[ $# -eq 1 ]] || die "usage: deps.sh <LABEL | login/LABEL>"
id="$(seat_rostered "$1")" || exit 1
home="$(seat_repo "$id")" || exit 1
decl="$(deps_declared "$id")" || exit 1
if [[ -z "$decl" ]]; then echo "deps: $id declares no dependency (a \"Waits on:\" line on its open rows, open desk asks or open milestones in $home)"; exit 0; fi
echo "deps: what $id waits on ($(wc -l <<< "$decl" | tr -d ' ') declaration(s)):"
while IFS=$'\t' read -r ref at; do
  st="$(dep_state "$ref" "$home")" || exit 1
  IFS=$'\t' read -r s d <<< "$st"
  printf '  %s  %s  %s  (declared on %s)\n' "$ref" "$s" "$d" "$at"
done <<< "$decl"
