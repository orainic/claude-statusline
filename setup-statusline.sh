#!/bin/bash
# Claude Code Statusline Setup Script
#
# Shows: model name, project folder, git branch/status, session cost,
#        context usage bar, 5-hour and 7-day rate limit bars (Pro/Max subscribers)
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
CTX=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
Q5H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null | cut -d. -f1)
Q7D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null | cut -d. -f1)
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
RESET='\033[0m'

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

# Rate limit bars
LIMITS=""
if [ -n "$Q5H" ]; then
  Q5H_COLOR=$(pick_color "$Q5H")
  Q5H_BAR=$(make_bar "$Q5H")
  LIMITS=" | 5h:${Q5H_COLOR}[${Q5H_BAR}]${RESET}${Q5H}%"
fi
if [ -n "$Q7D" ]; then
  Q7D_COLOR=$(pick_color "$Q7D")
  Q7D_BAR=$(make_bar "$Q7D")
  LIMITS="${LIMITS} 7d:${Q7D_COLOR}[${Q7D_BAR}]${RESET}${Q7D}%"
fi

# Git info
GIT_INFO=""
if git -C "$DIR" rev-parse --git-dir > /dev/null 2>&1; then
  BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
  STAGED=$(git -C "$DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  MODIFIED=$(git -C "$DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
  GIT_STATUS=""
  [ "$STAGED" -gt 0 ] && GIT_STATUS="${GREEN}+${STAGED}${RESET}"
  [ "$MODIFIED" -gt 0 ] && GIT_STATUS="${GIT_STATUS}${YELLOW}~${MODIFIED}${RESET}"
  GIT_INFO=" | ${BRANCH}${GIT_STATUS:+ $GIT_STATUS}"
fi

# Format cost
COST_STR=$(printf '$%.2f' "$COST")

echo -e "${CYAN}${MODEL}${RESET} ${DIR##*/}${GIT_INFO} | ${YELLOW}${COST_STR}${RESET} | ctx:${CTX_COLOR}[${CTX_BAR}]${RESET}${CTX}%${LIMITS}"
SCRIPT
chmod +x ~/.claude/statusline.sh
echo "  statusline.sh created and made executable."

# Step 4: Update settings.json
echo "[4/4] Updating ~/.claude/settings.json..."
SETTINGS_FILE=~/.claude/settings.json

if [ -f "$SETTINGS_FILE" ]; then
  if jq -e '.statusLine' "$SETTINGS_FILE" &>/dev/null; then
    # Update existing statusLine config
    jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh"}' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
    mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    echo "  statusLine updated in existing settings.json."
  else
    # Add statusLine to existing settings
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
echo "  Model name (cyan) | Project folder | Git branch +staged ~modified"
echo "  Session cost (yellow) | Context usage bar | 5-hour quota bar | 7-day quota bar"
echo ""
echo "Bar colors: green (<70%) | yellow (70-89%) | red (90%+)"
echo "Quota bars only appear for Pro/Max subscribers."
