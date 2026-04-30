# Claude Code Statusline

Custom statusline configurations for Claude Code CLI.

## Contents

### `setup-statusline.sh` (Basic)

A bash-based statusline showing, left to right:

- **Model name** (bold cyan), e.g. `Claude Opus 4.7 (1M context)`
- **Effort level** (when set), e.g. `effort:high`
- **Project folder** — basename of the working directory
- **Git branch + status** — `master +2 ~3` (green for staged, yellow for modified). Worktree-aware: uses the worktree branch from the harness JSON when available.
- **Session name** — magenta `(my-session)` when set via `/rename`
- **Context bar** — 10-char `[####------]` with color: green <70%, yellow 70-89%, red 90%+
- **5-hour quota bar** + `rst:2h 36m` countdown until reset *(Pro/Max only)*
- **7-day quota bar** + `rst:3d 4h` countdown until reset *(Pro/Max only)*
- **Vim mode indicator** — `[I]` / `[N]` / `[V]` / `[VL]` when vim mode is active

**Usage:**
```bash
bash setup-statusline.sh
```
Then restart Claude Code.

The script installs `jq` if missing, writes `~/.claude/statusline.sh`, and wires it up in `~/.claude/settings.json`.

#### Implementation notes

- ANSI color variables use bash ANSI-C quoting (`$'\033[..m'`) so they hold real ESC bytes and render correctly when interpolated into `printf %s` arguments.
- Reset countdowns are computed from `rate_limits.five_hour.resets_at` and `rate_limits.seven_day.resets_at` (Unix epoch seconds in the harness input). They auto-hide when the field is absent or already in the past.
- Git commands use `--no-lock-index` to avoid contending with concurrent Claude Code operations.
- Context percentage is rounded to an integer and defaults to 0 before the first API response.

### claude-hud (Recommended)

A much richer statusline plugin by [jarrodwatts/claude-hud](https://github.com/jarrodwatts/claude-hud) featuring:
- Unicode block character progress bars
- Multi-line layout with live activity tracking
- Tool calls, subagent, and todo progress
- Git status with ahead/behind and file-level detail
- CLAUDE.md count, rules, MCPs, hooks display
- Configurable presets (Full / Essential / Minimal)

**Install inside Claude Code:**
```
/plugin marketplace add jarrodwatts/claude-hud
/plugin install claude-hud
/reload-plugins
/claude-hud:setup
```
Then restart Claude Code. Requires Node.js 18+.

## References

- [claude-hud GitHub](https://github.com/jarrodwatts/claude-hud)
