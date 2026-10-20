#!/usr/bin/env bash
# ask-guard.sh — Stop hook: a seated session that ends its turn asking the decider something in session, with no
# decision row or desk ask filed during the turn, is blocked ONCE and told to file it and reply with only the link.
# Input (measured 2026-10-19 with a probe hook under `claude -p`): {"session_id", "transcript_path", "cwd",
# "prompt_id", "permission_mode", "hook_event_name": "Stop", "stop_hook_active", "last_assistant_message", …};
# stop_hook_active is true on the stop that follows a block, so the hook never blocks twice in a row.
#   seated     the transcript carries join.sh's "SEATED <login>/<LABEL> at <home>" in a tool result (the latest wins)
#   asking     a line of last_assistant_message (code and URLs set aside) that asks the person: a question ending in
#              "?" in the second person or opening as a request (shall, should, can, may, do, does, would, will, which,
#              ok, proceed, approve, go), or a phrase such as "waiting on you", "your call", "approve with", "shall I",
#              "do you want"; a line that carries a GitHub issue or pull request link points at a row and does not count
#   filed      a Bash call of this turn (the transcript from the turn's prompt_id) ran decision.sh new|record|revise,
#              desk.sh ask, or publish.sh|pr.sh request (each files or revises a row), and its result is not an error
# Block: {"decision": "block", "reason": …}. A hook fault never blocks: it is named on stderr and the hook exits 0.
set -u
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
input="$(cat)"
out="$(printf '%s' "$input" | python3 -I -c '
import json, re, sys
scripts = sys.argv[1]
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
SEATED = re.compile(r"^SEATED ([A-Za-z0-9-]+/[A-Z0-9_-]+) at /", re.M)
seat = None
for d in rows:
    if d.get("type") != "user": continue
    for b in blocks(d):
        if b.get("type") == "tool_result":
            for m in SEATED.finditer(result_text(b)): seat = m.group(1)
if not seat: sys.exit(0)
msg = I.get("last_assistant_message")
if not isinstance(msg, str):
    msg = ""
    for d in reversed(rows):
        if d.get("type") == "assistant":
            t = "\n".join(b.get("text", "") for b in blocks(d) if b.get("type") == "text")
            if t.strip(): msg = t; break
# the asking lines
text = re.sub(r"```.*?```", " ", msg, flags=re.S)
ROW = re.compile(r"https://github\.com/[^/\s]+/[^/\s]+/(issues|pull)/\d+")
PHRASES = re.compile(r"\b(waiting (on|for) (you|your)|your (call|word|approval|go-ahead|decision)|approve with|shall i|should i|do you want|would you like|want me to|let me know|please confirm|can you confirm|okay to proceed|ok to proceed)\b", re.I)
REQ = re.compile(r"^\W*(shall|should|can|could|may|do|does|would|will|which|ok|okay|proceed|approve|go)\b", re.I)
YOU = re.compile(r"\b(you|your)\b", re.I)
asking = []
for line in text.split("\n"):
    if ROW.search(line): continue
    l = re.sub(r"`[^`]*`", " ", line)
    l = re.sub(r"https?://\S+", " ", l)
    hit = bool(PHRASES.search(l))
    if not hit:
        for q in re.findall(r"[^.!?]*\?", l):
            if YOU.search(q) or REQ.search(q): hit = True; break
    if hit: asking.append(line.strip())
if not asking: sys.exit(0)
# this turn: from the first entry carrying the turn prompt_id; else from the last prompt the person typed
pid, start = I.get("prompt_id"), None
if pid:
    for i, d in enumerate(rows):
        if d.get("promptId") == pid: start = i; break
if start is None:
    start = 0
    for i, d in enumerate(rows):
        if d.get("type") == "user" and not d.get("isMeta") and any(b.get("type") == "text" for b in blocks(d)): start = i
FILE = re.compile(r"decision\.sh[\x27\"]?\s+(new|record|revise)\b|desk\.sh[\x27\"]?\s+ask\b|(publish|pr)\.sh[\x27\"]?\s+request\b")
calls, ok = {}, set()
for d in rows[start:]:
    for b in blocks(d):
        if b.get("type") == "tool_use" and b.get("name") == "Bash" and FILE.search(str((b.get("input") or {}).get("command", ""))):
            calls[b.get("id")] = True
        elif b.get("type") == "tool_result" and b.get("tool_use_id") in calls and not b.get("is_error"):
            ok.add(b.get("tool_use_id"))
if ok: sys.exit(0)
label = seat.split("/", 1)[1]
reason = ("Beast (%s): your last message asks the decider in session (\"%s\"), and no decision row or desk ask was filed this turn, "
          "so the board misses it. File it now from your home: an act that needs approval (deploy, release, spend, scope, a design) "
          "is a decision row, %s/decision.sh new --assignee <decider> --seat %s --title \"…\" … (six sections); a question across the desk "
          "(a name, which option, a clarification) is %s/desk.sh ask %s --text \"…\" [--options \"a | b\"] [--default a]. "
          "Put the substance inline or link a file or diff at a commit, never \"see session\" or a local path. Then reply with only the link.") % (
          seat, asking[0][:200], scripts, label, scripts, label)
print(json.dumps({"decision": "block", "reason": reason}))
' "$scripts" 2>&1)" || { echo "daita-beast: ask-guard.sh: the hook failed and blocks nothing: $out" >&2; exit 0; }
[[ -z "$out" ]] || { [[ "$out" == '{"decision": "block"'* ]] && printf '%s\n' "$out" || echo "daita-beast: ask-guard.sh: $out" >&2; }
exit 0
