#!/usr/bin/env bash
# permissions.sh <repo root> [--write] — the permissions.allow rules a Beast seat needs in <repo>/.claude/settings.json.
# Prints the exact diff between the file as it is (absent counts as {}) and the file with the missing rules appended to
# permissions.allow by a textual splice: every other key, the key order, the indentation and the formatting of the
# rest of the file are kept byte for byte. Writes only with --write, and never when nothing is missing ("nothing to
# add", the file untouched). The rules are the one list below: gh verbs the scripts and a seat's own reads use, and
# git's read verbs. The plugin's scripts need no rule: the PreToolUse hook permit.sh allows them. Rule shape:
# Bash(<prefix>:*), a trailing wildcard (code.claude.com/docs/en/permissions: "The :* suffix is an equivalent way to
# write a trailing wildcard, so Bash(ls:*) matches the same commands as Bash(ls *)").
# Exit 0 in every case but a fault (a settings.json that is not JSON, a permissions key that is not an object, a
# permissions.allow that is not an array of strings, a splice whose result does not parse to the expected object):
# those die naming the file and write nothing.
set -euo pipefail
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$scripts/lib.sh"
need jq python3

BEAST_PERMISSION_RULES=(
  'Bash(gh issue:*)'
  'Bash(gh api:*)'
  'Bash(gh search:*)'
  'Bash(gh project:*)'
  'Bash(gh label:*)'
  'Bash(gh pr:*)'
  'Bash(gh repo view:*)'
  'Bash(git status:*)'
  'Bash(git log:*)'
  'Bash(git diff:*)'
  'Bash(git show:*)'
  'Bash(git rev-parse:*)'
  'Bash(git ls-files:*)'
  'Bash(git branch:*)'
  'Bash(git worktree list:*)'
)

usage() { echo "usage: permissions.sh <repo root> [--write]" >&2; exit 1; }
root=""; write=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --write) write=1; shift ;;
    --*) echo "permissions.sh: unknown argument $1" >&2; usage ;;
    *) [[ -z "$root" ]] || usage; root="$1"; shift ;;
  esac
done
[[ -n "$root" ]] || usage
root="$(cd "$root" 2>/dev/null && pwd -P)" || die "permissions.sh: '$root' is not a directory"
file="$root/.claude/settings.json"

PERM_FILE="$file" PERM_WRITE="$write" PERM_RULES="$(printf '%s\n' "${BEAST_PERMISSION_RULES[@]}")" python3 - <<'PY'
import copy, difflib, json, os, re, sys
file, write = os.environ["PERM_FILE"], os.environ["PERM_WRITE"] == "1"
rules = [r for r in os.environ["PERM_RULES"].split("\n") if r]
def die(m): sys.stderr.write("daita-beast: permissions.sh: %s\n" % m); sys.exit(1)
J = lambda r: json.dumps(r, ensure_ascii=False)

def spans(src):
    """Byte spans (open index, close index) of the top object, its "permissions" value and that object's "allow"
    value, keyed by path; each with the index of the key token for indentation. A plain JSON walk, strings skipped."""
    out, stack, pending, i, n = {}, [], None, 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            k = j + 1
            while k < n and src[k] in " \t\r\n": k += 1
            if k < n and src[k] == ":": pending = (len(stack), json.loads(src[i:j + 1]), i)
            i = j + 1; continue
        if c in "{[":
            name, kpos = (pending[1], pending[2]) if pending and pending[0] == len(stack) else (None, i)
            pending = None; stack.append((i, name, kpos)); i += 1; continue
        if c in "}]":
            start, name, kpos = stack.pop()
            out[tuple(x[1] for x in stack) + (name,)] = (start, i, kpos)
        i += 1
    return out

def line_indent(src, pos):
    b = src.rfind("\n", 0, pos) + 1
    return re.match(r"[ \t]*", src[b:]).group(0)

if os.path.exists(file):
    old = open(file).read()
    try: data = json.loads(old)
    except Exception as e: die("%s is not JSON (%s): fix it by hand, nothing is written" % (file, e))
    if not isinstance(data, dict): die("%s is not a JSON object" % file)
else:
    old, data = "", {}
perms = data.get("permissions", {})
if not isinstance(perms, dict): die('%s: "permissions" is not an object' % file)
allow = perms.get("allow", [])
if not isinstance(allow, list) or any(not isinstance(x, str) for x in allow): die("%s: permissions.allow is not an array of strings" % file)
missing = [r for r in rules if r not in allow]
if not missing:
    print("nothing to add: %s already allows the %d Beast rules" % (file, len(rules))); sys.exit(0)

want = copy.deepcopy(data); want.setdefault("permissions", {}).setdefault("allow", []).extend(missing)
m = re.search(r"\n([ \t]+)\S", old); unit = m.group(1) if m else "  "
if old:
    sp = spans(old)
    top, pm, al = sp.get((None,)), sp.get((None, "permissions")), sp.get((None, "permissions", "allow"))
    if al:
        start, end, kpos = al
        inner = old[start + 1:end]
        if inner.strip():
            last = start + 1 + len(inner.rstrip())  # index just past the last element
            if "\n" in inner:
                ind = line_indent(old, old.rfind("\n", 0, last) + 1)
                ins = "".join(",\n%s%s" % (ind, J(r)) for r in missing)
            else:
                ins = "".join(", %s" % J(r) for r in missing)
            new = old[:last] + ins + old[last:]
        else:
            kin = line_indent(old, kpos)
            body = ",\n".join(kin + unit + J(r) for r in missing)
            new = old[:start] + "[\n" + body + "\n" + kin + "]" + old[end + 1:]
    elif pm:
        start, end, kpos = pm
        kin = line_indent(old, kpos); inner = old[start + 1:end]
        body = ",\n".join(kin + unit + unit + J(r) for r in missing)
        arr = "\n%s%s\"allow\": [\n%s\n%s%s]" % (kin, unit, body, kin, unit)
        new = old[:start + 1] + arr + ("," if inner.strip() else "\n" + kin) + old[start + 1:end] + old[end:]
    else:
        start, end, _ = top
        inner = old[start + 1:end]
        body = ",\n".join(unit * 3 + J(r) for r in missing)
        block = "%s\"permissions\": {\n%s\"allow\": [\n%s\n%s]\n%s}" % (unit, unit * 2, body, unit * 2, unit)
        if inner.strip():
            last = start + 1 + len(inner.rstrip())
            new = old[:last] + ",\n" + block + old[last:]
        else:
            new = old[:start] + "{\n" + block + "\n}" + old[end + 1:]
else:
    new = json.dumps(want, indent=2, ensure_ascii=False) + "\n"
try: got = json.loads(new)
except Exception as e: die("the splice into %s does not parse (%s); nothing is written, fix the file by hand" % (file, e))
if got != want: die("the splice into %s does not yield the expected object; nothing is written, fix the file by hand" % file)

a = "(absent)" if not old else file
sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), new.splitlines(True), fromfile=a, tofile=file))
if not old.endswith("\n") and old: print()
if write:
    os.makedirs(os.path.dirname(file), exist_ok=True)
    tmp = file + ".tmp"
    open(tmp, "w").write(new); os.replace(tmp, file)
    print("written: %s (+%d rules)" % (file, len(missing)))
else:
    print("not written (%d rules to add): rerun with --write" % len(missing))
PY
