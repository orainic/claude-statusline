# Claude Code Statusline

Custom statusline configurations for Claude Code CLI.

## Contents

### `setup-statusline.sh` (Basic)

A simple bash-based statusline showing:
- Model name, project folder, git branch/status
- Session cost, context usage bar
- 5-hour and 7-day rate limit bars (Pro/Max subscribers)

**Usage:**
```bash
bash setup-statusline.sh
```
Then restart Claude Code.

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
