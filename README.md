# Claude Code Statusline

Custom statusline configurations for Claude Code CLI.

## Contents

### `setup-statusline.sh` (Basic)

A bash-based **two-line HUD**. Line 1 is identity (stable, rarely changes); line 2 is
the meters you actually watch:

```
● Opus 5 1M · xhigh   claude-statusline   master ~2   (statusline-fix)   [I]
  ctx ████░░░░░░ 43%    5h ███████░░░ 73% ↻ 2h35m    7d █▌░░░░░░░░ 18% ↻ 3d3h
```

**Line 1 — identity**

- **Health dot** `●` — colored by the *worst* of context / 5h / 7d, so one glyph
  summarizes pressure before you read any number.
- **Model name** (bold cyan), shortened: `Claude Opus 5 (1M context)` → `Opus 5 1M`
- **Effort level** (dim, when set), e.g. `· xhigh`
- **Project folder** (bold) — basename of the working directory
- **Git branch + status** — `master +2 ~3` (green staged, yellow modified). Worktree-aware:
  uses the worktree branch from the harness JSON when available.
- **Session name** — magenta `(my-session)` when set via `/rename`
- **Vim mode** — `[I]` / `[N]` / `[V]` / `[VL]` when vim mode is active

**Line 2 — meters**

- **Context**, **5-hour quota**, **7-day quota** *(quotas are Pro/Max only)*
- Bars are 10 Unicode cells (`█` `▌` `░`). The half-block gives 5% resolution instead
  of the 10% an all-or-nothing block bar can show.
- Bar color: green <70%, yellow 70-89%, red 90%+. The empty track and labels are dim
  gray so color carries meaning rather than decoration.
- `↻ 2h35m` — countdown until that quota resets. Auto-hides when unknown or past.

**Usage:**
```bash
bash setup-statusline.sh
```
Then restart Claude Code.

The script installs `jq` if missing, writes `~/.claude/statusline.sh`, and wires it up in `~/.claude/settings.json`.

#### Implementation notes

- ANSI color variables use bash ANSI-C quoting (`$'\033[..m'`) so they hold real ESC bytes and render correctly when interpolated into `printf %s` arguments.
- Reset countdowns are computed from `rate_limits.five_hour.resets_at` and `rate_limits.seven_day.resets_at` (Unix epoch seconds in the harness input). They auto-hide when the field is absent or already in the past.
- Git commands use the global `--no-optional-locks` flag, which must appear **before** the subcommand (`git --no-optional-locks -C dir diff …`). There is no `--no-lock-index` option; passing it makes every git call exit 129, silently blanking the branch and status.
- Bars floor to the nearest 5%, so a bar never overstates usage.
- Context percentage is rounded to an integer and defaults to 0 before the first API response.
- On Windows, `winget` only updates `PATH` for *new* shells, so the installer probes the
  WinGet/choco install directories and adds `jq` to `PATH` for the current run, then verifies
  `jq` is callable before touching `settings.json`.

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
