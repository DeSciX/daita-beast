#!/usr/bin/env bash
# install-relay.sh — schedule one of the machine's two Beast jobs for one coordinating checkout.
#   install-relay.sh [--job relay|watchdog] --repo <checkout> [--scheduler launchd|systemd|cron] [--interval <s>] [--model haiku|sonnet] [--permission-mode <mode>]
#   install-relay.sh [--job relay|watchdog] --uninstall [--scheduler …]
#   install-relay.sh [--job relay|watchdog] --status [--scheduler …]
#   install-relay.sh [--job relay|watchdog] --describe [--scheduler …]
# The jobs (one each per machine; --job defaults to relay):
#   relay     net.descix.daita-beast.relay     relay.sh every 120 s (floor 60): one poll, a messenger only on change
#   watchdog  net.descix.daita-beast.watchdog  watchdog.sh every 900 s (floor 300): the checklist, an agent only on a signal
# Both run in the SEATS' permission mode (a receiver holds a message from a sender in another mode): --permission-mode,
# else the roster's relay.permissionMode, else fail loud. The scheduler defaults by host: Darwin → launchd; Linux with a
# user systemd → systemd; else cron. A job runs as the logged-in user, whose gh and claude credentials it uses, and runs
# its script from the installed plugin (lib.sh plugin_root; the installed line names it). Logs: ~/.beast/<job>.log (every
# tick, written by the script), ~/.beast/<job>.launchd.log or ~/.beast/<job>.sched.log (the scheduler's stdout/stderr).
# --describe prints the installed job as one line of key=value fields (job, label, scheduler, installed, loaded,
# program, repo, model, mode, interval), read from the plist, the unit or the crontab line: this script is the one owner
# of the jobs' shape, and the watchdog reads it here.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
job="relay"; repo=""; interval=""; model="haiku"; pmode=""; action="install"; scheduler=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --job) job="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --interval) interval="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --permission-mode) pmode="$2"; shift 2 ;;
    --scheduler) scheduler="$2"; shift 2 ;;
    --uninstall) action="uninstall"; shift ;;
    --status) action="status"; shift ;;
    --describe) action="describe"; shift ;;
    *) echo "install-relay.sh: unknown argument $1" >&2; exit 1 ;;
  esac
done
case "$job" in
  relay) script="relay.sh"; floor=60; default_interval=120; what="decision relay (one poll; a messenger only on change)" ;;
  watchdog) script="watchdog.sh"; floor=300; default_interval=900; what="watchdog (the checklist; an agent only on a signal)" ;;
  *) echo "install-relay.sh: --job is relay or watchdog, not '$job'" >&2; exit 1 ;;
esac
label="net.descix.daita-beast.$job"
interval="${interval:-$default_interval}"
if [[ -z "$scheduler" ]]; then
  case "$(uname -s)" in
    Darwin) scheduler=launchd ;;
    Linux) if systemctl --user show-environment >/dev/null 2>&1; then scheduler=systemd; else scheduler=cron; fi ;;
    *) scheduler=cron ;;
  esac
fi
case "$scheduler" in launchd|systemd|cron) ;; *) echo "scheduler must be launchd, systemd or cron" >&2; exit 1 ;; esac
mkdir -p "$HOME/.beast"
plist="$HOME/Library/LaunchAgents/$label.plist"
unit_dir="$HOME/.config/systemd/user"
cron_tag="# $label"
joblog="$HOME/.beast/$job.log"

# The job runs the plugin this machine is installed with (lib.sh plugin_root: $CLAUDE_PLUGIN_ROOT, else the root
# ~/.beast/plugin.json records), never a path derived from where this script was invoked.
prog=""
if [[ "$action" == install ]]; then
  prog="$(plugin_root)/scripts/$script"; [[ -x "$prog" ]] || die "install-relay.sh: $prog is not an executable script"
  [[ -n "$repo" ]] || { echo "--repo must be a git checkout" >&2; exit 1; }; checkout_require_root "$repo"
  if [[ -z "$pmode" ]]; then
    pmode="$(jq -r '.relay.permissionMode // empty' "$repo/.beast/roster.json" 2>/dev/null || true)"
    [[ -n "$pmode" ]] || { echo "install-relay.sh: no --permission-mode and no relay.permissionMode in $repo/.beast/roster.json — set it to the mode the seat sessions run in (default|acceptEdits|auto|bypassPermissions)" >&2; exit 1; }
  fi
  case "$pmode" in default|acceptEdits|auto|bypassPermissions|dontAsk|plan) ;; *) echo "install-relay.sh: unknown permission mode '$pmode'" >&2; exit 1 ;; esac
  [[ "$interval" =~ ^[0-9]+$ && "$interval" -ge $floor ]] || { echo "interval of the $job job must be $floor s or more (got '$interval')" >&2; exit 1; }
fi

need_tools() { for t in gh jq claude; do command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }; done; }
path_for_job() { echo "$(dirname "$(command -v claude)"):$(dirname "$(command -v gh)"):$(dirname "$(command -v jq)"):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"; }

status_common() { echo "last log lines:"; tail -n 5 "$joblog" 2>/dev/null || echo "  (no log yet)"; }

# describe_args <program> <args...>: the key=value fields of a job's command line (--repo, --model, --permission-mode).
describe_args() {
  local p="$1" r="" m="" pm=""; shift
  while [[ $# -gt 0 ]]; do
    case "$1" in --repo) r="${2:-}"; shift 2 ;; --model) m="${2:-}"; shift 2 ;; --permission-mode) pm="${2:-}"; shift 2 ;; *) shift ;; esac
  done
  printf 'program=%s repo=%s model=%s mode=%s' "$p" "$r" "$m" "$pm"
}

case "$scheduler:$action" in
  launchd:describe)
    loaded=no; launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 && loaded=yes
    if [[ -f "$plist" ]]; then
      args="$(python3 -I -c 'import plistlib, sys; d = plistlib.load(open(sys.argv[1], "rb")); print("\t".join(d.get("ProgramArguments", []))); print(d.get("StartInterval", ""))' "$plist")" || die "the plist $plist cannot be read"
      IFS=$'\t' read -r -a argv <<< "$(head -1 <<< "$args")"
      printf 'job=%s label=%s scheduler=launchd installed=yes loaded=%s %s interval=%s\n' "$job" "$label" "$loaded" "$(describe_args "${argv[@]}")" "$(sed -n 2p <<< "$args")"
    else printf 'job=%s label=%s scheduler=launchd installed=no loaded=%s\n' "$job" "$label" "$loaded"; fi ;;
  launchd:status)
    if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
      echo "installed (launchd): $plist"; launchctl print "gui/$(id -u)/$label" | grep -E 'state =|run interval =|last exit code =' || true
    else echo "not installed (launchd)"; fi; status_common ;;
  launchd:uninstall)
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true; rm -f "$plist"; echo "uninstalled $label (launchd)" ;;
  launchd:install)
    need_tools; mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>$prog</string><string>--repo</string><string>$repo</string><string>--model</string><string>$model</string><string>--permission-mode</string><string>$pmode</string>
  </array>
  <key>StartInterval</key><integer>$interval</integer>
  <key>RunAtLoad</key><true/>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>$(path_for_job)</string>
    <key>HOME</key><string>$HOME</string>
  </dict>
  <key>StandardOutPath</key><string>$HOME/.beast/$job.launchd.log</string>
  <key>StandardErrorPath</key><string>$HOME/.beast/$job.launchd.log</string>
</dict></plist>
EOF
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist"
    echo "installed $label (launchd): every ${interval}s, repo $repo, model $model, mode $pmode, $job $prog"; echo "log: $joblog" ;;
  systemd:describe)
    loaded=no; systemctl --user is-active "$label.timer" >/dev/null 2>&1 && loaded=yes
    if [[ -f "$unit_dir/$label.service" ]]; then
      read -r -a argv <<< "$(sed -n 's/^ExecStart=//p' "$unit_dir/$label.service")"
      printf 'job=%s label=%s scheduler=systemd installed=yes loaded=%s %s interval=%s\n' "$job" "$label" "$loaded" "$(describe_args "${argv[@]}")" "$(sed -n 's/^OnUnitActiveSec=\([0-9]*\)s$/\1/p' "$unit_dir/$label.timer" 2>/dev/null)"
    else printf 'job=%s label=%s scheduler=systemd installed=no loaded=%s\n' "$job" "$label" "$loaded"; fi ;;
  systemd:status)
    if systemctl --user is-enabled "$label.timer" >/dev/null 2>&1; then
      echo "installed (systemd): $unit_dir/$label.timer"; systemctl --user list-timers "$label.timer" --no-pager | sed -n '1,2p'
    else echo "not installed (systemd)"; fi; status_common ;;
  systemd:uninstall)
    systemctl --user disable --now "$label.timer" 2>/dev/null || true; rm -f "$unit_dir/$label.timer" "$unit_dir/$label.service"
    systemctl --user daemon-reload 2>/dev/null || true; echo "uninstalled $label (systemd)" ;;
  systemd:install)
    need_tools; mkdir -p "$unit_dir"
    cat > "$unit_dir/$label.service" <<EOF
[Unit]
Description=daita-beast $what
[Service]
Type=oneshot
Environment=PATH=$(path_for_job)
Environment=HOME=$HOME
ExecStart=$prog --repo $repo --model $model --permission-mode $pmode
StandardOutput=append:$HOME/.beast/$job.sched.log
StandardError=append:$HOME/.beast/$job.sched.log
EOF
    cat > "$unit_dir/$label.timer" <<EOF
[Unit]
Description=daita-beast $job, every ${interval}s
[Timer]
OnBootSec=60
OnUnitActiveSec=${interval}s
AccuracySec=10s
[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload && systemctl --user enable --now "$label.timer"
    echo "installed $label (systemd user timer): every ${interval}s, repo $repo, model $model, mode $pmode, $job $prog"; echo "log: $joblog" ;;
  cron:describe)
    line="$(crontab -l 2>/dev/null | grep -F "$cron_tag" | head -1 || true)"
    if [[ -n "$line" ]]; then
      read -r -a argv <<< "$(sed -E 's/^[^ ]+ [^ ]+ [^ ]+ [^ ]+ [^ ]+ PATH=[^ ]+ HOME=[^ ]+ //; s/ >> .*//' <<< "$line")"
      printf 'job=%s label=%s scheduler=cron installed=yes loaded=yes %s interval=%s\n' "$job" "$label" "$(describe_args "${argv[@]}")" "$(( $(sed -E 's#^\*/([0-9]+) .*#\1#' <<< "$line") * 60 ))"
    else printf 'job=%s label=%s scheduler=cron installed=no loaded=no\n' "$job" "$label"; fi ;;
  cron:status)
    if crontab -l 2>/dev/null | grep -qF "$cron_tag"; then echo "installed (cron):"; crontab -l | grep -F "$cron_tag"; else echo "not installed (cron)"; fi; status_common ;;
  cron:uninstall)
    (crontab -l 2>/dev/null | grep -vF "$cron_tag" || true) | crontab -; echo "uninstalled $label (cron)" ;;
  cron:install)
    need_tools
    minutes=$(( (interval + 59) / 60 )); [[ $minutes -ge 1 ]] || minutes=1
    line="*/$minutes * * * * PATH=$(path_for_job) HOME=$HOME $prog --repo $repo --model $model --permission-mode $pmode >> $HOME/.beast/$job.sched.log 2>&1 $cron_tag"
    (crontab -l 2>/dev/null | grep -vF "$cron_tag" || true; echo "$line") | crontab -
    echo "installed $label (cron): every ${minutes} min (cron's floor is one minute), repo $repo, model $model, mode $pmode, $job $prog"; echo "log: $joblog" ;;
esac
