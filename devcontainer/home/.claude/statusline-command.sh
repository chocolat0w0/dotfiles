#!/usr/bin/env bash
# Claude Code status line script

input=$(cat)

# Directory
cwd=$(echo "$input" | jq -r '.cwd // empty')

# Git branch from cwd
branch=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
fi

# Model and effort
model=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')

# Rate limits
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Format reset time as HH:MM (local time)
format_reset() {
  local epoch="$1"
  if [ -n "$epoch" ]; then
    date -d "@${epoch}" "+%m/%d %H:%M" 2>/dev/null || date -r "$epoch" "+%m/%d %H:%M" 2>/dev/null
  fi
}

five_reset_fmt=$(format_reset "$five_reset")
week_reset_fmt=$(format_reset "$week_reset")

# Build output parts
parts=()

# Directory
[ -n "$cwd" ] && parts+=("$(printf '\033[34m%s\033[0m' "$cwd")")

# Branch
[ -n "$branch" ] && parts+=("$(printf '\033[33m%s\033[0m' "$branch")")

# Model + effort
if [ -n "$model" ]; then
  if [ -n "$effort" ]; then
    parts+=("$(printf '\033[36m%s [%s]\033[0m' "$model" "$effort")")
  else
    parts+=("$(printf '\033[36m%s\033[0m' "$model")")
  fi
fi

# Rate limits
if [ -n "$five_pct" ]; then
  five_str=$(printf '5h: %.0f%%' "$five_pct")
  [ -n "$five_reset_fmt" ] && five_str="$five_str reset:${five_reset_fmt}"
  parts+=("$(printf '\033[35m%s\033[0m' "$five_str")")
fi

if [ -n "$week_pct" ]; then
  week_str=$(printf '7d: %.0f%%' "$week_pct")
  [ -n "$week_reset_fmt" ] && week_str="$week_str reset:${week_reset_fmt}"
  parts+=("$(printf '\033[35m%s\033[0m' "$week_str")")
fi

# Join with separator
result=""
for part in "${parts[@]}"; do
  if [ -z "$result" ]; then
    result="$part"
  else
    result="$result  |  $part"
  fi
done

printf '%s' "$result"
