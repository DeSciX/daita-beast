# Claude surfaces

What Beast relies on in Claude Code, the Claude desktop app (Cowork) and claude.ai, as those products behave today. None of it is Beast's own contract: each fact is an observation of a product Beast does not control, so each states how it was measured and against which version. A fact that could not be measured here is listed under [Not measured here](#not-measured-here) with the run that would measure it, and nothing is built on it.

Measured on 2026-10-21 on macOS, against Claude Code 2.1.304 (the binary the editor extension runs, `$CLAUDE_CODE_EXECPATH`, which every live session's file reports as its `version`) and 2.1.269 (the `claude` on the shell's `PATH`). The two differ: a `claude plugin …` command typed in a terminal runs the `PATH` binary, not the one the sessions run.

## Session files

- Claude Code writes one file per running session, `~/.claude/sessions/<pid>.json`. It is an undocumented internal. Its keys: `pid`, `sessionId`, `name`, `nameSource`, `nameSince`, `cwd`, `status`, `statusUpdatedAt`, `updatedAt`, `startedAt`, `procStart`, `version`, `kind`, `entrypoint`, `pidDomain`, `peerProtocol`, `peerFeatures`, `messagingSocketPath`. Beast reads `pid`, `sessionId`, `name`, `cwd` and `status`, through one reader that shape-checks every field it uses and dies naming the file and the field when the shape differs (`lib.sh::claude_sessions_read`, `claude_session_of`, `claude_sessions_live`). Liveness is `kill -0` on `pid`.
- `status` was one of `busy`, `idle` and `waiting` across eight live sessions.
- `name` is the name `ListAgents` prints and `SendMessage` takes. It is minted when the process starts: on every live session `nameSince` equalled `startedAt` and `nameSource` was `derived` (the launch folder's base name in lower case, a hyphen and two hex characters). A restarted or resumed session therefore carries a new name, and an address recorded before the restart names nobody. Beast re-reads the name at every join and the watchdog re-stamps a renamed seat (`seats.sh record`, `seats.sh touch`).
- `messagingSocketPath` is `/tmp/cc-socks/<pid>.sock`, keyed by the pid, so a restarted session listens on a different socket.
- Beside each file sits `<pid>.<hex>.key` (mode 0600). Beast never reads it.

## Names, refs and SendMessage

- `ListAgents` prints a session as `name [ref]`. The ref is not in the session file and is not derivable from it: for six live sessions whose ref Beast had recorded, no prefix or substring of an md5, sha1, sha256, sha512 or blake2b digest of the session id (with and without hyphens), pid, name, socket path, start time, cwd or process start matched it. Beast records the ref only when it is given one (`lib.sh::ADDRESS_RE` makes it optional).
- `SendMessage` takes a bare name when exactly one live session carries it (measured by Beast; its relay sends to the bare name). Beast counts the live holders of a name before it treats a name as sendable (`lib.sh::claude_name_holders`; `seats.sh record` prints `ambiguous: …` for two).
- A resumed session keeps its `sessionId`: sessions whose processes started that day carried transcripts (`~/.claude/projects/<project>/<sessionId>.jsonl`) whose first entry was days older, under the same id. `claude --resume` takes the id; `--fork-session` is the flag that makes a new one (`claude --help`). A seat's session claim therefore names the session id, and a resume or a compaction keeps the claim (`lib.sh::sessions_claim`, `seat-hello.sh`).
- `SessionStart` fires with source `startup`, `resume` and `compact`; all three were found in recent transcripts as `SessionStart:<source>` hook entries. Beast's hook rejoins a seated session on each (`seat-hello.sh`).
- `ListAgents` is not a tool inside a sub-agent: this document's measuring sub-agent had neither it nor a deferred copy of it.

## The plugin cache

- An installed plugin lives at `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`; a plugin whose manifest has no version gets a 12-hex directory name instead. Every version ever installed stays on disk (eleven versions of `daita-beast` sat side by side under `cache/daita/daita-beast/`).
- `~/.claude/plugins/installed_plugins.json` (`"version": 2`) maps `<plugin>@<marketplace>` to a list of installs, each with `scope`, `installPath`, `version`, `installedAt`, `lastUpdated` and `gitCommitSha`. For a plugin whose marketplace entry is a `git-subdir` source, `gitCommitSha` is the commit of the source repository's ref, not of the marketplace clone (`~/.claude/plugins/marketplaces/<marketplace>/`).
- `~/.claude/settings.json` holds `enabledPlugins`, keyed `<plugin>@<marketplace>`, `true` or `false`, and `extraKnownMarketplaces`, one key per added marketplace.
- `claude plugin update` reports "restart required to apply" (its help text). A session binds to the version installed when its process starts and keeps it: every live session's `SessionStart` hook ran from the version directory that was the installed one at its start (sessions started before an update ran the older version's scripts; one started between two updates ran the middle one), and those sessions stayed on it while `installed_plugins.json` moved on. Old directories stay on disk, so an open session's paths keep resolving. Beast's watchdog compares the scripts path a live seat's `SessionStart` output printed with the installed version and reports a seat on an old one (`watchdog.sh`, check `old-plugin`); `~/.beast/plugin.json` is re-recorded after every update (`lib.sh::plugin_root_record`).
- A plugin's skills and agents appear in a session as `<plugin>:<name>`. A plugin's MCP server appears as `plugin:<plugin>:<server>` (the keys of `~/.claude/mcp-needs-auth-cache.json`).

## Manifest validation and the claude.ai sync limits

- `claude plugin validate` rejects `"agents": "./agents/"` with `agents: Invalid input` (both versions; exit 1). It accepts an array of `.md` paths and a single string ending in `.md`, and it accepts a manifest with no `agents` field; Beast's manifest has none and its agents load as `daita-beast:<name>`.
- `claude plugin validate --strict` (both versions, exit 0) passes a plugin description of 600 characters and skill and agent descriptions containing `<` and `>`, whether pointed at the plugin or at its `skills/` or `agents/` directory.
- claude.ai's marketplace sync enforces both: a plugin description of at most 500 characters, and no angle brackets in skill descriptions (measured by Beast, whose manifest was brought within both). Since the CLI does not check them, Beast's own test does: `plugin/tests/manifest-limits.test.mjs` holds the plugin description to 500 characters and every skill and agent description free of angle brackets.

## Inside a Bash tool call and a sub-agent

- `CLAUDE_PLUGIN_ROOT` is unset in a Bash tool call (measured in a sub-agent's shell). Hook commands get it: Beast's `hooks.json` runs `${CLAUDE_PLUGIN_ROOT}/scripts/…` and those hooks run. A script started from a Bash call therefore gets the plugin root from `~/.beast/plugin.json` (`lib.sh::plugin_root`), never from the environment.
- In a sub-agent's shell, `CLAUDE_CODE_SESSION_ID` and `CLAUDE_PID` are the parent session's. A `seats.sh record` run from a sub-agent records the parent session's name, which is the seat's.
- A sub-agent had `Agent`, `Bash`, `SendMessage`, `Monitor` and `TaskStop`, and had no `ListAgents`, `ScheduleWakeup`, `CronCreate` or `TaskOutput`.
- A sub-agent's transcript is `~/.claude/projects/<project>/<session>/subagents/agent-<id>.jsonl`, beside `agent-<id>.meta.json` (`agentType`, `description`, `model`, `spawnDepth`, `requestShape`, `finished`). The session's `tasks/<id>.output`, under the session's temporary directory (`<tmp>/claude-<uid>/<project>/<session>/tasks/`), is a symlink to it. `ls -l` and `stat` report the link's own mtime (minutes behind on a running agent); `stat -L`, `readlink -f` or Python's `os.path.getmtime` follow it to the transcript.

## Hooks

- The hook events the 2.1.304 binary names: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`, `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, `SessionEnd`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact`, `PreModelSwitch`, `PostModelSwitch`, `PermissionRequest`, `PermissionDenied`, `Setup`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `Elicitation`, `ElicitationResult`, `ConfigChange`, `WorktreeCreate`, `WorktreeRemove`, `InstructionsLoaded`, `CwdChanged`, `FileChanged`, `DirectoryAdded`, `MessageDisplay` (read from the binary's event list, not from a run of each). There is no `SessionIdle`.
- Beast uses three: `PreToolUse` on `Bash` (`permit.sh`), `SessionStart` (`seat-hello.sh`) and `SessionEnd` (`seat-bye.sh`), all from `plugin/hooks/hooks.json`.

## The desktop app's plugins

- The Claude desktop app keeps its own plugin payloads, apart from the CLI cache: on macOS under `~/Library/Application Support/Claude/local-agent-mode-sessions/<a>/<b>/rpm/`, one `plugin_<id>/` directory per plugin (the server-side plugin id) and a `manifest.json` listing each with its marketplace. Copies also sit under `~/.claude/plugins/synced/<b>_<a>/<plugin>/`, with a `.meta.json` naming the `server_plugin_id`. Each `<a>/<b>` pair is a separate set, and the sets differ in which plugins they hold.

## Not measured here

Each of these is a claim about a surface Beast runs on that was not re-measured on this machine; nothing in Beast is built on it.

| Claim | What would measure it |
|---|---|
| A Claude Code cloud session installs no plugins, while hooks committed in the repo's own `.claude/settings.json` run there (Beast's cloud surface therefore uses a committed pointer skill). | In a cloud session of a repo whose `.claude/settings.json` has a `SessionStart` hook that echoes a marker: `ls ~/.claude/plugins`, `find / -name plugin.json`, and the marker in the session. |
| Cowork fires `UserPromptSubmit` and `PreToolUse` hooks; whether it fires `SessionStart` is open. | A Cowork session with a plugin whose hooks each append their event name to a file the session can read. |
| On claude.ai and Cowork only a skill's name and description are in context at start; the body loads when the skill is run. | A claude.ai session asked to quote a sentence that exists only in a skill's body, before and after `/plugin:skill` is run. |
| A plugin's agents are listed on claude.ai but cannot be run there. | A claude.ai session asked to run a plugin agent, with its tool list printed. |
| A sub-agent's id survives the parent's compaction and reload, and `SendMessage` to it resumes it. | Spawn a sub-agent, compact (then reload) the parent, `SendMessage` the id and check that the reply quotes the sub-agent's earlier context. |
