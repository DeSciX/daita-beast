#!/usr/bin/env bash
# license.sh — the one owner of license checks. The roster's "license" (parsed by roster_license, lib.sh) names the
# license every public repo of the roster's owners carries: its display name, the file it lives in, the manifest value
# that points at it, and its canonical source. Reads only; never writes to GitHub.
#
#   license.sh render [-o <file>]
#       the expected license file: the source (from source.checkout's HEAD when the roster names a checkout, else
#       through the GitHub contents API), rendered with source.render (a shell command, source on stdin,
#       BEAST_SCRIPTS set to this directory so it can name a filter the plugin ships: pandoc/latex-crossrefs.lua; without
#       it the source as-is), under ONE neutral header line naming no repo:
#         <!-- <name>. Rendered from its canonical source; do not edit by hand. -->
#       then an empty line. Stdout, or the file.
#   license.sh check <dir | tree-ish>
#       a directory, or a tree-ish of the repo you stand in (a commit, a branch, a publish commit), checked item by item:
#         license file  the roster's "file" is present
#         body          what follows its header line and the empty line equals the render's, byte for byte
#         header        the leading HTML comment is the neutral header line, and the scrub gate (scrub_patterns,
#                       scrub_scan: lib.sh) finds nothing in it, every line of it (a private repo, a local path, …)
#         manifests     every package.json and every .claude-plugin/plugin.json say "license": "<manifest>" (a directory in a
#                       git work tree is read through its tracked files only; another directory is walked, node_modules
#                       and .git pruned)
#       Each item prints ok or MISS; exit 1 on any miss, naming it. publish.sh prepare and request run it on the publish commit.
#   license.sh audit
#       every public repo of every owner the roster names, public_intended owners included (roster_public_owners, lib.sh),
#       at its default branch, read through the
#       REST API (git trees and blobs; no clone), with the same checks. Prints one table: repo | license file | body
#       matches | header clean | manifests | twin seat (the rostered seat whose repo is the private twin publishing to
#       it). A repo the roster's license "exempt" lists (under its own license: a fork of an upstream project) is read no
#       further and listed as "exempt", never a miss; an archived repo (read-only on GitHub, no license can be placed) is
#       listed as "archived", never a miss. Exit 1 when any row misses or cannot be read, or an exempt entry
#       names no public repo of the owners (a stale exemption).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq git python3

LIC="$(roster_license)" || exit 1
[[ -n "$LIC" ]] || die "the roster $(roster_path) has no \"license\": nothing to render or check (docs/protocol.md, License)"
L_NAME="$(jq -r .name <<< "$LIC")"; L_FILE="$(jq -r .file <<< "$LIC")"; L_MAN="$(jq -r .manifest <<< "$LIC")"
# Manifests under a roster "vendored" directory (roster_vendored, lib.sh) belong to an upstream package copied in byte for
# byte: not ours, not held.
L_VENDORED="$(roster_vendored)" || exit 1; L_VENDORED="$(jq -r '.[]' <<< "$L_VENDORED")"; export L_VENDORED
L_EXEMPT="$(jq -r '.exempt[]' <<< "$LIC")"
is_vendored() { local v; while IFS= read -r v; do [[ -n "$v" && ( "$1" == "$v"/* ) ]] && return 0; done <<< "$L_VENDORED"; return 1; }
S_REPO="$(jq -r .source.repo <<< "$LIC")"; S_PATH="$(jq -r .source.path <<< "$LIC")"
S_RENDER="$(jq -r '.source.render // empty' <<< "$LIC")"; S_CO="$(jq -r '.source.checkout // empty' <<< "$LIC")"

TMP="$(mktemp -d)"
on_exit 'rm -rf "$TMP"'

license_header() { printf '<!-- %s. Rendered from its canonical source; do not edit by hand. -->\n' "$L_NAME"; }

# b64_file: the JSON of a contents or blob read on stdin, its base64 "content" decoded to stdout; dies on another encoding.
b64_file() {
  python3 -I -c '
import base64, json, sys
d = json.load(sys.stdin)
if d.get("encoding") != "base64": sys.exit("daita-beast: %s: GitHub served it with encoding %r, not base64 (a file over 1 MB through contents)" % (sys.argv[1], d.get("encoding")))
sys.stdout.buffer.write(base64.b64decode(d.get("content") or ""))' "$1"
}

# license_source: the canonical source text on stdout.
license_source() {
  if [[ -n "$S_CO" ]]; then
    [[ -d "$S_CO" ]] || die "license.source.checkout $S_CO is not a directory on this machine"
    local have; have="$(repo_slug "$S_CO")" || exit 1
    [[ "$(tr 'A-Z' 'a-z' <<< "$have")" == "$(tr 'A-Z' 'a-z' <<< "$S_REPO")" ]] || die "license.source.checkout $S_CO is a checkout of $have, not $S_REPO (license.source.repo)"
    git -C "$S_CO" show "HEAD:$S_PATH" || die "$S_CO has no $S_PATH at HEAD (license.source.path)"
  else
    gh_get "repos/$S_REPO/contents/$(jq -rn --arg p "$S_PATH" '$p | split("/") | map(@uri) | join("/")')" | b64_file "$S_REPO:$S_PATH" \
      || die "cannot read $S_PATH of $S_REPO (named above)"
  fi
}

# license_render <out file>: the expected license file.
license_render() {
  local src="$TMP/source" body="$TMP/body"
  license_source > "$src" || exit 1
  [[ -s "$src" ]] || die "the license source $S_REPO:$S_PATH is empty"
  if [[ -n "$S_RENDER" ]]; then
    BEAST_SCRIPTS="$BEAST_SCRIPTS" bash -c "$S_RENDER" < "$src" > "$body" || die "the render command \`$S_RENDER\` (license.source.render) failed on $S_REPO:$S_PATH (named above)"
  else
    cp "$src" "$body"
  fi
  [[ -s "$body" ]] || die "the render of $S_REPO:$S_PATH is empty"
  { license_header; echo; cat "$body"; } > "$1"
}

# is_wanted <path>: whether a repo path is one the checks read (the license file, package.json, a plugin manifest).
is_wanted() { [[ "$1" == "$L_FILE" ]] && return 0; [[ "$1" != node_modules/* && "$1" != */node_modules/* ]] && ! is_vendored "$1" && [[ "$1" =~ (^|/)package\.json$ || "$1" =~ (^|/)\.claude-plugin/plugin\.json$ ]]; }

# PAT: the scrub patterns, derived once per run in the main shell (scrub_pat), before any license_eval.
PAT=""
scrub_pat() { [[ -n "$PAT" ]] && return 0; PAT="$TMP/scrub.json"; scrub_patterns > "$PAT" || die "cannot derive the scrub patterns (named above)"; }

# license_eval <files dir> <expected file>: the checks over a directory holding the wanted files at their repo paths.
# Prints JSON {present, body, header, header_line, header_hits, manifests: [{path, license, ok}]}.
license_eval() {
  local dir="$1" exp="$2" res hl hits="" rc=0
  res="$(python3 -I - "$dir" "$exp" "$L_FILE" "$L_MAN" <<'PY'
import json, os, sys
d, exp, lf, man = sys.argv[1:5]
E = open(exp, "rb").read()
eh, _, rest = E.partition(b"\n")
eb = rest[1:]
out = {"present": False, "body": None, "header": None, "header_line": "", "manifests": []}
p = os.path.join(d, lf)
if os.path.isfile(p):
    F = open(p, "rb").read()
    out["present"] = True
    # the header: the leading HTML comment, through the line that closes it (one line when rendered here)
    end = F.find(b"-->") if F.startswith(b"<!--") else -1
    if end >= 0:
        nl = F.find(b"\n", end)
        h, rest = (F[:nl], F[nl + 1:]) if nl >= 0 else (F, b"")
        out["header_line"] = h.decode("utf-8", "replace")
        out["header"] = "ok" if h == eh else "differs"
        body = rest[1:] if rest.startswith(b"\n") else rest
    else:
        out["header"] = "none"
        body = F
    out["body"] = body == eb
for root, dirs, files in os.walk(d):
    dirs[:] = sorted(x for x in dirs if x not in ("node_modules", ".git"))
    for f in sorted(files):
        rel = os.path.relpath(os.path.join(root, f), d)
        if any(rel.startswith(v + "/") for v in os.environ.get("L_VENDORED", "").split("\n") if v): continue
        if f == "package.json" or (f == "plugin.json" and os.path.basename(root) == ".claude-plugin"):
            try:
                lic = json.load(open(os.path.join(root, f), encoding="utf-8")).get("license")
            except Exception as x:
                lic = "unreadable JSON: %s" % x
            out["manifests"].append({"path": rel, "license": lic, "ok": lic == man})
print(json.dumps(out))
PY
)" || die "cannot evaluate the license checks over $dir"
  hl="$(jq -r .header_line <<< "$res")"
  if [[ -n "$hl" ]]; then
    [[ -n "$PAT" ]] || die "license_eval: the scrub patterns are not derived (scrub_pat first)"
    printf '%s\n' "$hl" > "$TMP/header.txt"
    hits="$(scrub_scan "$(repo_root)" "$PAT" "" "" "$TMP/header.txt")" || rc=$?
    # the scanner's two answers, by shape: a pass line (exit 0), or hit lines (exit 1); anything else is a failure
    if [[ $rc -eq 0 ]]; then
      [[ "$hits" == "scrub: clean "* ]] || die "the scrub scanner exited 0 on the header without its pass line: $hits"
      hits=""
    elif [[ $rc -ne 1 || "$hits" != *$'\n  '* ]]; then
      die "the scrub scanner failed on the header (exit $rc, named above): ${hits:-no output}"
    fi
  fi
  jq -c --arg h "$hits" '.header_hits = ($h | split("\n") | map(select(startswith("  ")) | ltrimstr("  ")))' <<< "$res"
}

# collect_dir <dir> <files dir>; collect_tree <tree-ish> <files dir>: the wanted files copied into <files dir>. A <dir> inside
# a git work tree is read through its TRACKED files only (git ls-files), so untracked and ignored paths, nested worktrees
# and node_modules are never read; a <dir> outside one is walked (.git and node_modules pruned), said on stderr.
collect_dir() {
  local src="$1" dst="$2" p
  if [[ "$(git -C "$src" rev-parse --is-inside-work-tree 2>/dev/null)" == true ]]; then
    while IFS= read -r -d '' p; do
      is_wanted "$p" || continue
      [[ -f "$src/$p" ]] || continue   # tracked but deleted in the working tree: not in the directory
      mkdir -p "$dst/$(dirname "$p")"; cp "$src/$p" "$dst/$p"
    done < <(git -C "$src" ls-files -z)
  else
    echo "license.sh: $src is not in a git work tree: every file under it is read (.git and node_modules pruned)" >&2
    while IFS= read -r -d '' p; do
      p="${p#"$src"/}"
      is_wanted "$p" || continue
      mkdir -p "$dst/$(dirname "$p")"; cp "$src/$p" "$dst/$p"
    done < <(find "$src" \( -name node_modules -o -name .git \) -prune -o -type f -print0)
  fi
}
collect_tree() {
  local t="$1" dst="$2" p
  while IFS= read -r -d '' p; do
    is_wanted "$p" || continue
    mkdir -p "$dst/$(dirname "$p")"
    git -C "$(repo_root)" cat-file blob "$t:$p" > "$dst/$p" || die "cannot read $p of $t"
  done < <(git -C "$(repo_root)" ls-tree -r -z --name-only --full-tree "$t")
}

# report <result json> <what>: one line per item; returns 1 on any miss.
report() {
  python3 -I - "$1" "$L_FILE" "$L_MAN" "$2" <<'PY'
import json, sys
R, lf, man, what = json.loads(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
miss = 0
def line(ok, item, text):
    global miss
    if not ok: miss += 1
    print("  %-4s  %-12s  %s" % ("ok" if ok else "MISS", item, text))
line(R["present"], "license file", "%s is present" % lf if R["present"] else "%s is absent" % lf)
if R["present"]:
    line(R["body"], "body", "equals the render, byte for byte" if R["body"] else "differs from the render (license.sh render -o %s, then commit it)" % lf)
    h = R["header"]
    if R["header_hits"]:
        for x in R["header_hits"]: line(False, "header", "the scrub gate: %s" % x)
    if h == "ok": line(not R["header_hits"], "header", "the neutral header line" if not R["header_hits"] else "the neutral header line, but it names what may not leave the twin (above)")
    elif h == "none": line(False, "header", "no header line (the first line is not an HTML comment)")
    else: line(False, "header", "not the neutral header line: %s" % R["header_line"].split("\n")[0][:160])
if not R["manifests"]:
    print("  ok    manifests     none (no package.json or .claude-plugin/plugin.json anywhere in the tree)")
for m in R["manifests"]:
    line(m["ok"], "manifest", "%s says \"license\": %s%s" % (m["path"], json.dumps(m["license"]), "" if m["ok"] else ", not %s" % json.dumps(man)))
if miss:
    print("license check: %d miss(es) on %s" % (miss, what)); sys.exit(1)
print("license check: %s carries %s" % (what, lf))
PY
}

cmd="${1:-}"; shift || true
case "$cmd" in
  render)
    out=""
    while [[ $# -gt 0 ]]; do case "$1" in -o) [[ -n "${2:-}" ]] || die "-o takes a file"; out="$2"; shift 2 ;; *) die "unknown argument $1" ;; esac; done
    license_render "$TMP/expected"
    if [[ -n "$out" ]]; then cp "$TMP/expected" "$out"; echo "rendered $L_NAME into $out ($(wc -c < "$out" | tr -d ' ') bytes)"; else cat "$TMP/expected"; fi
    ;;
  check)
    [[ $# -eq 1 ]] || die "usage: license.sh check <dir | tree-ish>"
    t="$1"; files="$TMP/files"; mkdir -p "$files"
    if [[ -d "$t" ]]; then
      collect_dir "$(cd "$t" && pwd)" "$files"
    elif git -C "$(repo_root)" rev-parse --verify -q "$t^{tree}" >/dev/null; then
      collect_tree "$t" "$files"
    else
      die "'$t' is neither a directory nor a tree-ish of $(repo_root)"
    fi
    license_render "$TMP/expected"; scrub_pat
    res="$(license_eval "$files" "$TMP/expected")" || exit 1
    echo "license.sh check $t: $L_NAME"
    report "$res" "$t" || exit 1
    ;;
  audit)
    [[ $# -eq 0 ]] || die "audit takes no arguments"
    license_render "$TMP/expected"; scrub_pat
    roster="$(roster_path)"; me="$(gh_login)" || exit 1
    # the twin seats: each rostered repo (this roster's own repo and every seat's), with its roster's publishes_to (this
    # roster read locally, another repo's .beast/roster.json read through the contents API; none there is no twin)
    twins='{}'
    while IFS= read -r r; do
      [[ -n "$r" ]] || continue
      if [[ "$(tr 'A-Z' 'a-z' <<< "$r")" == "$(tr 'A-Z' 'a-z' <<< "$(roster_repo)")" ]]; then
        p="$(jq -r '.publishes_to // empty' "$roster")"
      elif got="$(gh_get "repos/$r/contents/.beast/roster.json" 2>"$TMP/err")"; then
        p="$(b64_file "$r:.beast/roster.json" <<< "$got" | jq -r '.publishes_to // empty')" || die "the roster of $r is not JSON"
      else
        grep -q 'HTTP 404' "$TMP/err" || { cat "$TMP/err" >&2; die "cannot read the roster of $r (named above)"; }
        p=""
      fi
      [[ -n "$p" ]] || continue
      seats="$(jq -r --arg r "$r" '[.seats[]? | select((.repo // "" | ascii_downcase) == ($r | ascii_downcase)) | .label] | join(",")' "$roster")"
      twins="$(jq -c --arg p "$(tr 'A-Z' 'a-z' <<< "$p")" --arg s "${seats:-no seat}" '.[$p] = $s' <<< "$twins")"
    done < <(jq -r '[.repo, (.seats[]?.repo)] | map(select(. != null)) | unique_by(ascii_downcase) | .[]' "$roster")
    rows="$TMP/rows"; : > "$rows"; bad=0; seen_exempt=""
    while IFS= read -r o; do
      [[ -n "$o" ]] || continue
      type="$(gh_get "users/$o" | jq -r .type)" || die "cannot read the GitHub account $o (named above)"
      if [[ "$type" == Organization ]]; then lst="$(gh_get_all "orgs/$o/repos?type=public")" || die "cannot list the public repos of $o (named above)"
      else lst="$(gh_get_all "users/$o/repos?type=owner")" || die "cannot list the public repos of $o (named above)"; fi
      while IFS=$'\t' read -r r db fork arch size; do
        [[ -n "$r" ]] || continue
        tag="$r"; [[ "$fork" != true ]] || tag+=" (fork)"; [[ "$arch" != true ]] || tag+=" (archived)"
        seat="$(jq -r --arg r "$(tr 'A-Z' 'a-z' <<< "$r")" '.[$r] // "-"' <<< "$twins")"
        if grep -qixF -- "$r" <<< "$L_EXEMPT"; then
          printf '%s\t%s\t-\t-\t-\t%s\n' "$tag" "exempt (its own license)" "$seat" >> "$rows"; seen_exempt+="$r"$'\n'; continue
        fi
        if [[ "$arch" == true ]]; then
          # GitHub makes an archived repo read-only: no license can be placed on it; named, never a miss
          printf '%s\t%s\t-\t-\t-\t%s\n' "$tag" "archived (read-only on GitHub)" "$seat" >> "$rows"; continue
        fi
        if ! tree="$(gh_get "repos/$r/git/trees/$(uri "$db")?recursive=1" 2>"$TMP/err")"; then
          # an empty repo has no default branch to read (GitHub answers 404 or 409 and lists it with size 0)
          if [[ "$size" == 0 ]] && grep -Eq 'HTTP (404|409)' "$TMP/err"; then printf '%s\t%s\t-\t-\t-\t%s\n' "$tag" "no (an empty repo)" "$seat" >> "$rows"; bad=1; continue; fi
          printf '%s\t%s\t-\t-\t-\t%s\n' "$tag" "UNREAD ($(tr '\n' ' ' < "$TMP/err" | sed 's/^daita-beast: //' | cut -c1-140))" "$seat" >> "$rows"; bad=1; continue
        fi
        if [[ "$(jq -r .truncated <<< "$tree")" == true ]]; then
          printf '%s\t%s\t-\t-\t-\t%s\n' "$tag" "UNREAD (the tree is truncated)" "$seat" >> "$rows"; bad=1; continue
        fi
        files="$TMP/repo"; rm -rf "$files"; mkdir -p "$files"
        while IFS=$'\t' read -r p sha; do
          is_wanted "$p" || continue
          mkdir -p "$files/$(dirname "$p")"
          gh_get "repos/$r/git/blobs/$sha" | b64_file "$r:$p" > "$files/$p" || die "cannot read $p of $r (named above)"
        done < <(jq -r '.tree[] | select(.type == "blob") | [.path, .sha] | @tsv' <<< "$tree")
        res="$(license_eval "$files" "$TMP/expected")" || exit 1
        jq -r --arg tag "$tag" --arg seat "$seat" --arg man "$L_MAN" '
          [ $tag,
            (if .present then "yes" else "no" end),
            (if .present then (if .body then "yes" else "no" end) else "-" end),
            (if .present | not then "-"
             elif (.header_hits | length) > 0 then "no: " + (.header_hits | join("; ") | .[0:120])
             elif .header == "ok" then "yes"
             elif .header == "none" then "no: no header line"
             else "no: not the neutral line" end),
            (if (.manifests | length) == 0 then "none"
             else (.manifests | map(.path + (if .ok then " ok" else ": " + (.license | tostring) end)) | join("; ")) end),
            $seat ] | @tsv' <<< "$res" >> "$rows"
        jq -e --arg man "$L_MAN" '.present and .body and .header == "ok" and (.header_hits | length) == 0 and all(.manifests[]; .ok)' <<< "$res" >/dev/null || bad=1
      done < <(jq -r '.[] | select(.private == false) | [.full_name, (.default_branch // ""), .fork, .archived, .size] | @tsv' <<< "$lst")
    done < <(roster_public_owners "$roster")
    echo "license.sh audit: $L_NAME in $L_FILE; manifests \"$L_MAN\"; read-only, at each public repo's default branch"
    echo
    echo "| repo | license file | body matches | header clean | manifests | twin seat |"
    echo "|---|---|---|---|---|---|"
    sort -f "$rows" | awk -F'\t' '{ for (i = 1; i <= NF; i++) gsub(/\|/, "\\|", $i); printf "| %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6 }'
    while IFS= read -r x; do
      [[ -n "$x" ]] || continue
      grep -qixF -- "$x" <<< "$seen_exempt" && continue
      echo; echo "license audit: the roster's license \"exempt\" lists $x, which is not a public repo of the roster's owners (a stale exemption: remove it)"; bad=1
    done <<< "$L_EXEMPT"
    [[ $bad -eq 0 ]] || { echo; echo "license audit: some public repos miss or drift (above)"; exit 1; }
    ;;
  *) die "usage: license.sh render [-o <file>] | check <dir | tree-ish> | audit (see the header of $0)" ;;
esac
