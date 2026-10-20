#!/usr/bin/env bash
# ask-guard.sh — Stop hook: a seated session that ends its turn asking the decider something new in session, with no
# decision row or desk ask filed during the turn, is blocked ONCE and told to file it and reply with only the link. A
# message that only points at a row already filed and open is not blocked: it is a pointer, and a new row would be a twin.
# Input (measured 2026-10-19 with a probe hook under `claude -p`): {"session_id", "transcript_path", "cwd",
# "prompt_id", "permission_mode", "hook_event_name": "Stop", "stop_hook_active", "last_assistant_message", …};
# stop_hook_active is true on the stop that follows a block, so the hook never blocks twice in a row.
#   seated     the transcript carries join.sh's "SEATED <login>/<LABEL> at <home>" in a tool result (the latest wins)
#   asking     a line of last_assistant_message (code blocks set aside) that asks the person, of one of two kinds:
#              a question: a sentence ending in "?" in the second person or opening as a request (shall, should, can,
#                may, do, does, would, will, which, ok, proceed, approve, go), or a phrase such as "shall I", "should I",
#                "do you want", "let me know", "please confirm"; it is new unless the same line names an open row
#              a pointer: "waiting on/for you(r)", "your call|word|approval|go-ahead|decision", "approve with"; it points
#                at a row and passes when the message names any open row
#   rows       the refs the message names: issue or pull request URLs, owner/repo#N, and #N resolved through
#              seat_repo (run from the seat's home); each distinct one is read with one GET (row_refs_state, lib.sh),
#              at most MAX_REFS per run; open means an open decision issue, PR labelled needs-review or desk
#   filed      a Bash call of this turn (the transcript from the turn's prompt_id) ran decision.sh new|record|revise,
#              desk.sh ask, or publish.sh|pr.sh request (each files or revises a row), however the script is reached
#              (a relative path, an absolute plugin-cache path, a `cd … &&` prefix, quoted, or across a backslash line
#              continuation), and its result is not an error
# Block: {"decision": "block", "reason": …}. A hook fault (a GitHub read that fails, not a 404) never blocks: it is
# named on stderr and the hook exits 0.
set -u
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
input="$(cat)"
errf="$(mktemp)"; trap 'rm -f "$errf"' EXIT
out="$(printf '%s' "$input" | python3 -I -c '
import json, re, subprocess, sys
scripts = sys.argv[1]
MAX_REFS = 8
I = json.load(sys.stdin)
if I.get("stop_hook_active"): sys.exit(0)
tp = I.get("transcript_path") or ""
rows = []
try:
    with open(tp, encoding="utf-8") as f:
        for l in f:
            l = l.strip()
            if not l: continue
            try: rows.append(json.loads(l))
            except ValueError: pass
except OSError:
    sys.exit(0)   # no transcript: nothing to read a seat from
def blocks(d):
    m = d.get("message") if isinstance(d.get("message"), dict) else {}
    c = m.get("content")
    if isinstance(c, str): return [{"type": "text", "text": c}]
    return [b for b in (c or []) if isinstance(b, dict)]
def result_text(b):
    c = b.get("content")
    if isinstance(c, str): return c
    return "\n".join(x.get("text", "") for x in (c or []) if isinstance(x, dict))
SEATED = re.compile(r"^SEATED ([A-Za-z0-9-]+/[A-Z0-9_-]+) at (/[^\n]*?)\s*$", re.M)
seat = home = None
for d in rows:
    if d.get("type") != "user": continue
    for b in blocks(d):
        if b.get("type") == "tool_result":
            for m in SEATED.finditer(result_text(b)): seat, home = m.group(1), m.group(2)
if not seat: sys.exit(0)
msg = I.get("last_assistant_message")
if not isinstance(msg, str):
    msg = ""
    for d in reversed(rows):
        if d.get("type") == "assistant":
            t = "\n".join(b.get("text", "") for b in blocks(d) if b.get("type") == "text")
            if t.strip(): msg = t; break
# the asking lines, each a question (new unless its own line names an open row) or a pointer (at a filed row)
text = re.sub(r"```.*?```", " ", msg, flags=re.S)
POINTER = re.compile(r"\b(waiting (on|for) (you|your)|your (call|word|approval|go-ahead|decision)|approve with)\b", re.I)
PHRASES = re.compile(r"\b(shall i|should i|do you want|would you like|want me to|let me know|please confirm|can you confirm|okay to proceed|ok to proceed)\b", re.I)
REQ = re.compile(r"^\W*(shall|should|can|could|may|do|does|would|will|which|ok|okay|proceed|approve|go)\b", re.I)
YOU = re.compile(r"\b(you|your)\b", re.I)
URL_REF = re.compile(r"https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/(?:issues|pull)/(\d+)")
REPO_REF = re.compile(r"(?<![\w./-])([A-Za-z0-9-]+/[A-Za-z0-9_.-]+)#(\d+)\b")
BARE_REF = re.compile(r"(?<![\w/#])#(\d+)\b")
def refs_of(line):
    out = ["%s#%s" % m.groups() for m in URL_REF.finditer(line)]
    rest = URL_REF.sub(" ", line)
    out += ["%s#%s" % m.groups() for m in REPO_REF.finditer(rest)]
    out += ["#" + m.group(1) for m in BARE_REF.finditer(REPO_REF.sub(" ", rest))]
    return out
questions, pointers, line_refs = [], [], []
for line in text.split("\n"):
    refs = refs_of(line)
    line_refs.append(refs)
    l = re.sub(r"`[^`]*`", " ", line)
    l = re.sub(r"https?://\S+", " ", l)
    ask = bool(PHRASES.search(l))
    if not ask:
        for q in re.findall(r"[^.!?]*\?", l):
            if YOU.search(q) or REQ.search(q): ask = True; break
    if ask: questions.append((line.strip(), refs))
    elif POINTER.search(l): pointers.append((line.strip(), refs))
if not questions and not pointers: sys.exit(0)
# this turn: from the first entry carrying the turn prompt_id; else from the last prompt the person typed
pid, start = I.get("prompt_id"), None
if pid:
    for i, d in enumerate(rows):
        if d.get("promptId") == pid: start = i; break
if start is None:
    start = 0
    for i, d in enumerate(rows):
        if d.get("type") == "user" and not d.get("isMeta") and any(b.get("type") == "text" for b in blocks(d)): start = i
FILE = re.compile(r"decision\.sh[\x27\"]?(?:\s|\\\n)+(new|record|revise)\b|desk\.sh[\x27\"]?(?:\s|\\\n)+ask\b|(publish|pr)\.sh[\x27\"]?(?:\s|\\\n)+request\b")
calls, ok = {}, set()
for d in rows[start:]:
    for b in blocks(d):
        if b.get("type") == "tool_use" and b.get("name") == "Bash" and FILE.search(str((b.get("input") or {}).get("command", ""))):
            calls[b.get("id")] = True
        elif b.get("type") == "tool_result" and b.get("tool_use_id") in calls and not b.get("is_error"):
            ok.add(b.get("tool_use_id"))
if ok: sys.exit(0)
# the rows the message names: one GET per distinct ref (row_refs_state), at most MAX_REFS, from the seat home
distinct = []
for refs in line_refs:
    for r in refs:
        if r not in distinct: distinct.append(r)
state = {}
if distinct:
    if len(distinct) > MAX_REFS:
        print("daita-beast: ask-guard.sh: the message names %d refs; only the first %d are read (%s unread)" % (len(distinct), MAX_REFS, " ".join(distinct[MAX_REFS:])), file=sys.stderr)
    p = subprocess.run(["bash", "-c", "source \"$1/lib.sh\" || exit 1; cd \"$2\" || exit 1; r=; "
                        "if [[ \" ${*:4} \" == *\" #\"* ]]; then r=\"$(seat_repo \"$3\")\" || r=; fi; shift 3; row_refs_state \"$r\" \"$@\"",
                        "ask-guard", scripts, home or "/", seat] + distinct[:MAX_REFS], capture_output=True, text=True)
    if p.returncode != 0:
        print("daita-beast: ask-guard.sh: the hook failed and blocks nothing: cannot read the rows the message names: " + p.stderr.strip(), file=sys.stderr)
        sys.exit(0)
    if p.stderr.strip(): print(p.stderr.strip(), file=sys.stderr)
    for l in p.stdout.splitlines():
        f = l.split("\t")
        if len(f) == 3: state[f[0]] = f[2]
open_row = lambda refs: any(state.get(r) == "open" for r in refs)
asking = [l for l, refs in questions if not open_row(refs)]
if not any(state.get(r) == "open" for r in distinct):
    asking += [l for l, refs in pointers]
if not asking: sys.exit(0)
label = seat.split("/", 1)[1]
reason = ("Beast (%s): your last message asks the decider in session (\"%s\"), and no decision row or desk ask was filed this turn, "
          "so the board misses it. File it now from your home: an act that needs approval (deploy, release, spend, scope, a design) "
          "is a decision row, %s/decision.sh new --assignee <decider> --by %s --seat %s --title \"…\" … (six sections); a question across the desk "
          "(a name, which option, a clarification) is %s/desk.sh ask %s --text \"…\" [--options \"a | b\"] [--default a]. "
          "Put the substance inline or link a file or diff at a commit, never \"see session\" or a local path. Then reply with only the link. "
          "A message that only points at a row already filed names it (its URL, owner/repo#N or #N) and asks nothing new.") % (
          seat, asking[0][:200], scripts, label, label, scripts, label)
print(json.dumps({"decision": "block", "reason": reason}))
' "$scripts" 2>"$errf")" || { echo "daita-beast: ask-guard.sh: the hook failed and blocks nothing: $out $(cat "$errf")" >&2; exit 0; }
[[ ! -s "$errf" ]] || cat "$errf" >&2
[[ -z "$out" ]] || { [[ "$out" == '{"decision": "block"'* ]] && printf '%s\n' "$out" || echo "daita-beast: ask-guard.sh: $out" >&2; }
exit 0
