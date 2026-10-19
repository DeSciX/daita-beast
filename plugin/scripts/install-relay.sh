#!/usr/bin/env bash
# install-relay.sh — schedule relay.sh on this machine for one coordinating checkout.
#   install-relay.sh --repo <checkout> [--scheduler launchd|systemd|cron] [--interval 120] [--model haiku|sonnet] [--permission-mode bypassPermissions]
# The messenger must run in the SEATS' permission mode (a receiver holds a message from a sender in another mode).
#   install-relay.sh --uninstall [--scheduler …]
#   install-relay.sh --status [--scheduler …]
# The scheduler defaults by host: Darwin → launchd; Linux with a user systemd → systemd; else cron.
# One job per machine (net.descix.daita-beast.relay); it runs as the logged-in user, whose gh and claude
# credentials it uses, and runs relay.sh from the installed plugin (lib.sh plugin_root; the status line names it). Logs: ~/.beast/relay.log (every tick), ~/.beast/relay.launchd.log or
# ~/.beast/relay.sched.log (the scheduler's own stdout/stderr).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
label="net.descix.daita-beast.relay"
repo=""; interval=120; model="haiku"; pmode=""; action="install"; scheduler=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --interval) interval="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --permission-mode) pmode="$2"; shift 2 ;;
    --scheduler) scheduler="$2"; shift 2 ;;
    --uninstall) action="uninstall"; shift ;;
    --status) action="status"; shift ;;
    *) echo "install-relay.sh: unknown argument $1" >&2; exit 1 ;;
  esac
done
if [[ -z "$scheduler" ]]; then
  case "$(uname -s)" in
    Darwin) scheduler=launchd ;;
    Linux) if systemctl --user show-environment >/dev/null 2>&1; then scheduler=systemd; else scheduler=cron; fi ;;
    *) scheduler=cron ;;
  esac
fi
case "$scheduler" in launchd|systemd|cron) ;; *) echo "scheduler must be launchd, systemd or cron" >&2; exit 1 ;; esac
# The job runs the plugin this machine is installed with (lib.sh plugin_root: $CLAUDE_PLUGIN_ROOT, else the root
# ~/.beast/plugin.json records), never a path derived from where this script was invoked.
relay=""
if [[ "$action" == install ]]; then relay="$(plugin_root)/scripts/relay.sh"; [[ -x "$relay" ]] || die "install-relay.sh: $relay is not an executable script"; fi
mkdir -p "$HOME/.beast"
plist="$HOME/Library/LaunchAgents/$label.plist"
unit_dir="$HOME/.config/systemd/user"
cron_tag="# $label"

need_tools() { for t in gh jq claude; do command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }; done; }
path_for_job() { echo "$(dirname "$(command -v claude)"):$(dirname "$(command -v gh)"):$(dirname "$(command -v jq)"):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"; }

status_common() { echo "last log lines:"; tail -n 5 "$HOME/.beast/relay.log" 2>/dev/null || echo "  (no log yet)"; }

case "$scheduler:$action" in
  launchd:status)
    if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
      echo "installed (launchd): $plist"; launchctl print "gui/$(id -u)/$label" | grep -E 'state =|run interval =|last exit code =' || true
    else echo "not installed (launchd)"; fi; status_common ;;
  launchd:uninstall)
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true; rm -f "$plist"; echo "uninstalled $label (launchd)" ;;
  launchd:install)
    [[ -n "$repo" ]] || { echo "--repo must be a git checkout" >&2; exit 1; }; checkout_require_root "$repo"
    # The messenger's permission mode must equal the seats' (a receiver holds a message from a sender in
# another mode): --permission-mode, else the roster's relay.permissionMode, else fail loud.
if [[ "$action" == "install" && -z "$pmode" ]]; then
  pmode="$(jq -r '.relay.permissionMode // empty' "$repo/.beast/roster.json" 2>/dev/null || true)"
  [[ -n "$pmode" ]] || { echo "install-relay.sh: no --permission-mode and no relay.permissionMode in $repo/.beast/roster.json — set it to the mode the seat sessions run in (default|acceptEdits|auto|bypassPermissions)" >&2; exit 1; }
fi
case "${pmode:-default}" in default|acceptEdits|auto|bypassPermissions|dontAsk|plan) ;; *) echo "install-relay.sh: unknown permission mode '$pmode'" >&2; exit 1 ;; esac
[[ "$interval" -ge 60 ]] || { echo "interval must be 60 s or more" >&2; exit 1; }
    need_tools; mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>$relay</string><string>--repo</string><string>$repo</string><string>--model</string><string>$model</string><string>--permission-mode</string><string>$pmode</string>
  </array>
  <key>StartInterval</key><integer>$interval</integer>
  <key>RunAtLoad</key><true/>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>$(path_for_job)</string>
    <key>HOME</key><string>$HOME</string>
  </dict>
  <key>StandardOutPath</key><string>$HOME/.beast/relay.launchd.log</string>
  <key>StandardErrorPath</key><string>$HOME/.beast/relay.launchd.log</string>
</dict></plist>
EOF
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist"
    echo "installed $label (launchd): every ${interval}s, repo $repo, model $model, mode $pmode, relay $relay"; echo "log: $HOME/.beast/relay.log" ;;
  systemd:status)
    if systemctl --user is-enabled "$label.timer" >/dev/null 2>&1; then
      echo "installed (systemd): $unit_dir/$label.timer"; systemctl --user list-timers "$label.timer" --no-pager | sed -n '1,2p'
    else echo "not installed (systemd)"; fi; status_common ;;
  systemd:uninstall)
    systemctl --user disable --now "$label.timer" 2>/dev/null || true; rm -f "$unit_dir/$label.timer" "$unit_dir/$label.service"
    systemctl --user daemon-reload 2>/dev/null || true; echo "uninstalled $label (systemd)" ;;
  systemd:install)
    [[ -n "$repo" ]] || { echo "--repo must be a git checkout" >&2; exit 1; }; checkout_require_root "$repo"
    [[ "$interval" -ge 60 ]] || { echo "interval must be 60 s or more" >&2; exit 1; }
    need_tools; mkdir -p "$unit_dir"
    cat > "$unit_dir/$label.service" <<EOF
[Unit]
Description=daita-beast decision relay (one poll; a messenger only on change)
[Service]
Type=oneshot
Environment=PATH=$(path_for_job)
Environment=HOME=$HOME
ExecStart=$relay --repo $repo --model $model --permission-mode $pmode
StandardOutput=append:$HOME/.beast/relay.sched.log
StandardError=append:$HOME/.beast/relay.sched.log
EOF
    cat > "$unit_dir/$label.timer" <<EOF
[Unit]
Description=daita-beast decision relay, every ${interval}s
[Timer]
OnBootSec=60
OnUnitActiveSec=${interval}s
AccuracySec=10s
[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload && systemctl --user enable --now "$label.timer"
    echo "installed $label (systemd user timer): every ${interval}s, repo $repo, model $model, mode $pmode, relay $relay"; echo "log: $HOME/.beast/relay.log" ;;
  cron:status)
    if crontab -l 2>/dev/null | grep -qF "$cron_tag"; then echo "installed (cron):"; crontab -l | grep -F "$cron_tag"; else echo "not installed (cron)"; fi; status_common ;;
  cron:uninstall)
    (crontab -l 2>/dev/null | grep -vF "$cron_tag" || true) | crontab -; echo "uninstalled $label (cron)" ;;
  cron:install)
    [[ -n "$repo" ]] || { echo "--repo must be a git checkout" >&2; exit 1; }; checkout_require_root "$repo"
    [[ "$interval" -ge 60 ]] || { echo "interval must be 60 s or more" >&2; exit 1; }
    need_tools
    minutes=$(( (interval + 59) / 60 )); [[ $minutes -ge 1 ]] || minutes=1
    line="*/$minutes * * * * PATH=$(path_for_job) HOME=$HOME $relay --repo $repo --model $model --permission-mode $pmode >> $HOME/.beast/relay.sched.log 2>&1 $cron_tag"
    (crontab -l 2>/dev/null | grep -vF "$cron_tag" || true; echo "$line") | crontab -
    echo "installed $label (cron): every ${minutes} min (cron's floor is one minute), repo $repo, model $model, mode $pmode, relay $relay"; echo "log: $HOME/.beast/relay.log" ;;
esac
