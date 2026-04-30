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
      winget install jqlang.jq --accept-package-agreements --accept-source-agreements
    elif command -v choco &>/dev/null; then
      choco install jq -y
    else
      echo "  ERROR: No package manager found. Install jq manually: https://jqlang.github.io/jq/download/"
      exit 1
    fi
  else
    echo "  ERROR: Unsupported OS. Install jq manually: https://jqlang.github.io/jq/download/"
    exit 1
  fi
  echo "  jq installed."
fi

# Step 2: Create ~/.claude directory if needed
echo "[2/4] Ensuring ~/.claude directory exists..."
mkdir -p ~/.claude

# Step 3: Create the statusline script
echo "[3/4] Creating ~/.claude/statusline.sh..."
cat > ~/.claude/statusline.sh << 'SCRIPT'
#!/bin/bash
input=$(cat)
MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
SESSION_NAME=$(echo "$input" | jq -r '.session_name // empty')
VIM_MODE=$(echo "$input" | jq -r '.vim.mode // empty')
WORKTREE_BRANCH=$(echo "$input" | jq -r '.worktree.branch // empty')
EFFORT=$(echo "$input" | jq -r '.effort.level // empty')

# Context: null before first API call, so default to 0
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
BOLD=$'\033[1m'
RESET=$'\033[0m'

# Convert a future Unix epoch timestamp to a compact "Xh Ym" / "Xd Yh" string.
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
    echo "${days}d ${hours}h"
  elif [ "$hours" -gt 0 ]; then
    echo "${hours}h ${mins}m"
  else
    echo "${mins}m"
  fi
}

# Build a 10-segment bar from a percentage
make_bar() {
  local pct=$1
  local filled=$((pct / 10))
  local empty=$((10 - filled))
  local bar=""
  [ "$filled" -gt 0 ] && bar=$(printf "%${filled}s" | tr ' ' '#')
  [ "$empty" -gt 0 ] && bar="${bar}$(printf "%${empty}s" | tr ' ' '-')"
  echo "$bar"
}

# Pick color based on percentage
pick_color() {
  local pct=$1
  if [ "$pct" -ge 90 ]; then echo "$RED"
  elif [ "$pct" -ge 70 ]; then echo "$YELLOW"
  else echo "$GREEN"
  fi
}

# Context bar
CTX_COLOR=$(pick_color "$CTX")
CTX_BAR=$(make_bar "$CTX")

# Rate limit bars + reset countdowns
LIMITS=""
if [ -n "$Q5H" ]; then
  Q5H_COLOR=$(pick_color "$Q5H")
  Q5H_BAR=$(make_bar "$Q5H")
  Q5H_ETA=$(reset_eta "$Q5H_RESET")
  Q5H_ETA_STR=""
  [ -n "$Q5H_ETA" ] && Q5H_ETA_STR=" rst:${Q5H_ETA}"
  LIMITS=" | 5h:${Q5H_COLOR}[${Q5H_BAR}]${RESET}${Q5H}%${Q5H_ETA_STR}"
fi
if [ -n "$Q7D" ]; then
  Q7D_COLOR=$(pick_color "$Q7D")
  Q7D_BAR=$(make_bar "$Q7D")
  Q7D_ETA=$(reset_eta "$Q7D_RESET")
  Q7D_ETA_STR=""
  [ -n "$Q7D_ETA" ] && Q7D_ETA_STR=" rst:${Q7D_ETA}"
  LIMITS="${LIMITS} 7d:${Q7D_COLOR}[${Q7D_BAR}]${RESET}${Q7D}%${Q7D_ETA_STR}"
fi

# Git info — prefer worktree branch from JSON, then live git query
GIT_INFO=""
GIT_DIR="$DIR"
if [ -n "$WORKTREE_BRANCH" ]; then
  GIT_INFO=" | ${WORKTREE_BRANCH}"
  if git -C "$GIT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    STAGED=$(git -C "$GIT_DIR" diff --cached --numstat --no-lock-index 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git -C "$GIT_DIR" diff --numstat --no-lock-index 2>/dev/null | wc -l | tr -d ' ')
    GIT_ST=""
    [ "$STAGED" -gt 0 ] && GIT_ST="${GREEN}+${STAGED}${RESET}"
    [ "$MODIFIED" -gt 0 ] && GIT_ST="${GIT_ST}${YELLOW}~${MODIFIED}${RESET}"
    [ -n "$GIT_ST" ] && GIT_INFO="${GIT_INFO} ${GIT_ST}"
  fi
elif git -C "$GIT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
  BRANCH=$(git -C "$GIT_DIR" branch --show-current --no-lock-index 2>/dev/null)
  STAGED=$(git -C "$GIT_DIR" diff --cached --numstat --no-lock-index 2>/dev/null | wc -l | tr -d ' ')
  MODIFIED=$(git -C "$GIT_DIR" diff --numstat --no-lock-index 2>/dev/null | wc -l | tr -d ' ')
  GIT_ST=""
  [ "$STAGED" -gt 0 ] && GIT_ST="${GREEN}+${STAGED}${RESET}"
  [ "$MODIFIED" -gt 0 ] && GIT_ST="${GIT_ST}${YELLOW}~${MODIFIED}${RESET}"
  GIT_INFO=" | ${BRANCH}${GIT_ST:+ $GIT_ST}"
fi

# Session name label
SESSION_LABEL=""
[ -n "$SESSION_NAME" ] && SESSION_LABEL=" ${MAGENTA}(${SESSION_NAME})${RESET}"

# Vim mode indicator
VIM_LABEL=""
if [ -n "$VIM_MODE" ]; then
  case "$VIM_MODE" in
    INSERT)        VIM_LABEL=" ${GREEN}[I]${RESET}" ;;
    NORMAL)        VIM_LABEL=" [N]" ;;
    VISUAL)        VIM_LABEL=" ${YELLOW}[V]${RESET}" ;;
    "VISUAL LINE") VIM_LABEL=" ${YELLOW}[VL]${RESET}" ;;
    *)             VIM_LABEL=" [${VIM_MODE}]" ;;
  esac
fi

# Effort indicator
EFFORT_LABEL=""
[ -n "$EFFORT" ] && EFFORT_LABEL=" effort:${EFFORT}"

printf "${BOLD}${CYAN}%s${RESET}%s %s%s%s | ctx:%s[%s]${RESET}%s%%%s%s\n" \
  "$MODEL" \
  "$EFFORT_LABEL" \
  "${DIR##*/}" \
  "$GIT_INFO" \
  "$SESSION_LABEL" \
  "$CTX_COLOR" \
  "$CTX_BAR" \
  "$CTX" \
  "$LIMITS" \
  "$VIM_LABEL"
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
echo "Status line shows:"
echo "  Model + effort | Project folder | Git branch +staged ~modified | Session"
echo "  ctx:[bar]% | 5h:[bar]% rst:Xh Ym | 7d:[bar]% rst:Xd Yh | Vim mode"
echo ""
echo "Bar colors: green (<70%) | yellow (70-89%) | red (90%+)"
echo "Quota bars + reset countdowns only appear for Pro/Max subscribers."
