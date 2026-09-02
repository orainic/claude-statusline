#!/bin/bash
# Claude Code Statusline Setup Script
#
# Shows: model name + effort, project folder, git branch/status (worktree-aware),
#        session name, vim mode, context usage bar, 5h/7d rate-limit bars with
#        reset countdowns (Pro/Max subscribers).
#
# Usage:
#   bash setup-statusline.sh
#
# Then restart Claude Code to see the status line.

set -e

echo "=== Claude Code Statusline Setup ==="
echo ""

# Step 1: Install jq if not found
echo "[1/4] Checking for jq..."
if command -v jq &>/dev/null; then
  echo "  jq already installed."
else
  echo "  Installing jq..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if command -v brew &>/dev/null; then
      brew install jq
    else
      echo "  ERROR: Homebrew not found. Install it first: https://brew.sh"
      exit 1
    fi
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if command -v apt-get &>/dev/null; then
      sudo apt-get update && sudo apt-get install -y jq
    elif command -v yum &>/dev/null; then
      sudo yum install -y jq
    elif command -v pacman &>/dev/null; then
      sudo pacman -S --noconfirm jq
    else
      echo "  ERROR: No supported package manager found. Install jq manually."
      exit 1
    fi
  elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    if command -v winget &>/dev/null; then
      winget install jqlang.jq --accept-package-agreements --accept-source-agreements || true
    elif command -v choco &>/dev/null; then
      choco install jq -y || true
    else
      echo "  ERROR: No package manager found. Install jq manually: https://jqlang.github.io/jq/download/"
      exit 1
    fi
  else
    echo "  ERROR: Unsupported OS. Install jq manually: https://jqlang.github.io/jq/download/"
    exit 1
  fi
  # winget/choco update PATH for *new* shells only, so jq is still not callable
  # in this one. Locate the freshly installed binary and use it for step 4.
  if ! command -v jq &>/dev/null; then
    for d in "$HOME/AppData/Local/Microsoft/WinGet/Links" \
             "$HOME"/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_* \
             "/c/ProgramData/chocolatey/bin"; do
      if [ -x "$d/jq.exe" ]; then
        PATH="$PATH:$d"
        echo "  Added $d to PATH for this run."
        break
      fi
    done
  fi
  if command -v jq &>/dev/null; then
    echo "  jq installed: $(jq --version)"
  else
    echo "  ERROR: jq installed but not on PATH in this shell. Open a new terminal and re-run."
    exit 1
  fi
fi

# Step 2: Create ~/.claude directory if needed
echo "[2/4] Ensuring ~/.claude directory exists..."
mkdir -p ~/.claude

# Step 3: Create the statusline script
echo "[3/4] Creating ~/.claude/statusline.sh..."
cat > ~/.claude/statusline.sh << 'SCRIPT'
#!/bin/bash
# Two-line HUD statusline for Claude Code.
#   Line 1 — identity: model, effort, project, git, session, vim mode.
#   Line 2 — meters: context and rate-limit bars with reset countdowns.
# Reads the harness JSON payload on stdin.
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
SESSION_NAME=$(echo "$input" | jq -r '.session_name // empty')
VIM_MODE=$(echo "$input" | jq -r '.vim.mode // empty')
WORKTREE_BRANCH=$(echo "$input" | jq -r '.worktree.branch // empty')
EFFORT=$(echo "$input" | jq -r '.effort.level // empty')

# Context is null before the first API response, so default to 0.
CTX_RAW=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
CTX=$(printf '%.0f' "$CTX_RAW" 2>/dev/null || echo 0)

Q5H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
[ -n "$Q5H" ] && Q5H=$(printf '%.0f' "$Q5H")
Q5H_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
Q7D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
[ -n "$Q7D" ] && Q7D=$(printf '%.0f' "$Q7D")
Q7D_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)

# ANSI-C quoting ($'...') so each variable holds a real ESC byte — required for
# correct rendering when the codes are interpolated into %s arguments later.
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
CYAN=$'\033[36m'
MAGENTA=$'\033[35m'
DIM=$'\033[90m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# Convert a future Unix epoch timestamp to a compact "2h35m" / "3d4h" string.
# Prints nothing when the timestamp is absent or already in the past.
reset_eta() {
  local epoch=$1
  [ -z "$epoch" ] && return
  local now
  now=$(date +%s 2>/dev/null) || return
  local diff=$(( epoch - now ))
  [ "$diff" -le 0 ] && return
  local days=$(( diff / 86400 ))
  local hours=$(( (diff % 86400) / 3600 ))
  local mins=$(( (diff % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then
    echo "${days}d${hours}h"
  elif [ "$hours" -gt 0 ]; then
    echo "${hours}h${mins}m"
  else
    echo "${mins}m"
  fi
}

# Pick a color by percentage: green <70, yellow 70-89, red 90+.
pick_color() {
  local pct=$1
  if [ "$pct" -ge 90 ]; then echo "$RED"
  elif [ "$pct" -ge 70 ]; then echo "$YELLOW"
  else echo "$GREEN"
  fi
}

# Render "label ███▌░░░░░░ 43% ↻ 2h35m" as one colored meter.
# Each cell is 10%; a trailing half-block ▌ marks the remaining 5%, so the bar
# resolves to 5% steps instead of the 10% steps a whole-block bar can show.
render_meter() {
  local label=$1 pct=$2 eta=$3
  local color filled half empty fbar ebar i out
  color=$(pick_color "$pct")
  filled=$(( pct / 10 ))
  half=0
  [ $(( pct % 10 )) -ge 5 ] && half=1
  empty=$(( 10 - filled - half ))
  fbar=""; ebar=""
  for ((i = 0; i < filled; i++)); do fbar="${fbar}█"; done
  [ "$half" -eq 1 ] && fbar="${fbar}▌"
  for ((i = 0; i < empty; i++)); do ebar="${ebar}░"; done
  out="${DIM}${label}${RESET} ${color}${fbar}${DIM}${ebar}${RESET} ${pct}%"
  [ -n "$eta" ] && out="${out} ${DIM}↻ ${eta}${RESET}"
  printf '%s' "$out"
}

# --- Line 1: identity ------------------------------------------------------

# "Claude Opus 5 (1M context)" -> "Opus 5 1M"
MODEL_SHORT=$(echo "$MODEL" | sed -e 's/^Claude //' -e 's/ *(\([0-9]*[MKmk]\) context)/ \1/')

# Health dot: worst of context and the two quotas, so one glyph summarizes pressure.
WORST=$CTX
[ -n "$Q5H" ] && [ "$Q5H" -gt "$WORST" ] && WORST=$Q5H
[ -n "$Q7D" ] && [ "$Q7D" -gt "$WORST" ] && WORST=$Q7D
DOT_COLOR=$(pick_color "$WORST")

EFFORT_LABEL=""
[ -n "$EFFORT" ] && EFFORT_LABEL="${DIM} · ${EFFORT}${RESET}"

# Git info — prefer the worktree branch from the JSON, then a live git query.
GIT_INFO=""
GIT_DIR="$DIR"
git_status_suffix() {
  local staged modified st
  staged=$(git --no-optional-locks -C "$GIT_DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  modified=$(git --no-optional-locks -C "$GIT_DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
  st=""
  [ "${staged:-0}" -gt 0 ] && st="${GREEN}+${staged}${RESET}"
  [ "${modified:-0}" -gt 0 ] && st="${st}${YELLOW}~${modified}${RESET}"
  [ -n "$st" ] && printf ' %s' "$st"
}
if [ -n "$WORKTREE_BRANCH" ]; then
  GIT_INFO="   ${WORKTREE_BRANCH}"
  git -C "$GIT_DIR" rev-parse --git-dir > /dev/null 2>&1 && GIT_INFO="${GIT_INFO}$(git_status_suffix)"
elif git -C "$GIT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
  BRANCH=$(git --no-optional-locks -C "$GIT_DIR" branch --show-current 2>/dev/null)
  [ -n "$BRANCH" ] && GIT_INFO="   ${BRANCH}$(git_status_suffix)"
fi

SESSION_LABEL=""
[ -n "$SESSION_NAME" ] && SESSION_LABEL="   ${MAGENTA}(${SESSION_NAME})${RESET}"

VIM_LABEL=""
if [ -n "$VIM_MODE" ]; then
  case "$VIM_MODE" in
    INSERT)        VIM_LABEL="   ${GREEN}[I]${RESET}" ;;
    NORMAL)        VIM_LABEL="   ${DIM}[N]${RESET}" ;;
    VISUAL)        VIM_LABEL="   ${YELLOW}[V]${RESET}" ;;
    "VISUAL LINE") VIM_LABEL="   ${YELLOW}[VL]${RESET}" ;;
    *)             VIM_LABEL="   [${VIM_MODE}]" ;;
  esac
fi

printf '%s● %s%s%s%s%s   %s%s%s%s%s%s\n' \
  "$DOT_COLOR" "$RESET" \
  "$BOLD$CYAN" "$MODEL_SHORT" "$RESET" "$EFFORT_LABEL" \
  "$BOLD" "${DIR##*/}" "$RESET" \
  "$GIT_INFO" "$SESSION_LABEL" "$VIM_LABEL"

# --- Line 2: meters --------------------------------------------------------

LINE2="  $(render_meter ctx "$CTX" "")"
if [ -n "$Q5H" ]; then
  LINE2="${LINE2}    $(render_meter '5h' "$Q5H" "$(reset_eta "$Q5H_RESET")")"
fi
if [ -n "$Q7D" ]; then
  LINE2="${LINE2}    $(render_meter '7d' "$Q7D" "$(reset_eta "$Q7D_RESET")")"
fi
printf '%s\n' "$LINE2"
SCRIPT
chmod +x ~/.claude/statusline.sh
echo "  statusline.sh created and made executable."

# Step 4: Update settings.json
echo "[4/4] Updating ~/.claude/settings.json..."
SETTINGS_FILE=~/.claude/settings.json

if [ -f "$SETTINGS_FILE" ]; then
  if jq -e '.statusLine' "$SETTINGS_FILE" &>/dev/null; then
    jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh"}' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
    mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    echo "  statusLine updated in existing settings.json."
  else
    jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}}' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
    mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    echo "  statusLine added to existing settings.json."
  fi
else
  cat > "$SETTINGS_FILE" << 'SETTINGS'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
SETTINGS
  echo "  settings.json created."
fi

echo ""
echo "=== Setup complete! ==="
echo "Restart Claude Code to see the status line."
echo ""
echo "Two-line HUD:"
echo "  ● Model · effort   project   branch +staged ~modified   (session)   [vim]"
echo "    ctx ███▌░░░░░░ 43%    5h ███████░░░ 73% ↻ 2h35m    7d █░░░░░░░░░ 18% ↻ 3d3h"
echo ""
echo "The ● dot summarizes the worst of context / 5h / 7d at a glance."
echo "Bar colors: green (<70%) | yellow (70-89%) | red (90%+)"
echo "Quota meters + reset countdowns only appear for Pro/Max subscribers."
