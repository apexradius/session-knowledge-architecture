#!/bin/bash
# mcp-cleanup.sh — Kill orphan MCP processes + detect recursive claude fork bombs
# Called by: Claude Stop hook + LaunchAgent safety net (every 5 min)
#
# Handles two failure modes:
# 1. Orphan MCP servers (ppid=1) left behind by dead Claude sessions
# 2. Recursive claude process chains from hooks that spawn claude subprocesses

MCP_PATTERNS="apex-core-mcp|apex-commerce-mcp|apex-automation-mcp|apex-social-mcp|apex-data-mcp|apex-tools-mcp|apex-browser-mcp|apex-github-mcp"

KILLED=0

# --- Phase 1: Kill recursive claude chains ---
# A healthy system has at most 1-2 claude processes (main session + maybe one --print call).
# More than 3 means a hook is forking recursively.
CLAUDE_COUNT=$(pgrep -x claude 2>/dev/null | wc -l | tr -d ' ')
if [ "$CLAUDE_COUNT" -gt 3 ]; then
  # Find the oldest claude process (the real session) — keep it, kill the rest
  OLDEST_CLAUDE=$(pgrep -x claude 2>/dev/null | head -1)
  for pid in $(pgrep -x claude 2>/dev/null); do
    if [ "$pid" != "$OLDEST_CLAUDE" ]; then
      kill -9 "$pid" 2>/dev/null && KILLED=$((KILLED + 1))
    fi
  done
  # Also kill any prompt-enhancer.js processes that started the chain
  pkill -9 -f "prompt-enhancer.js" 2>/dev/null
  logger -t mcp-cleanup "Killed recursive claude chain ($CLAUDE_COUNT processes, kept PID $OLDEST_CLAUDE)"
  sleep 1
fi

# --- Phase 2: Kill orphan MCP servers (ppid=1) ---
for pid in $(pgrep -f "$MCP_PATTERNS" 2>/dev/null); do
  ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  if [ "$ppid" = "1" ]; then
    kill "$pid" 2>/dev/null && KILLED=$((KILLED + 1))
  fi
done

# Force kill stubborn orphans after 2 seconds
if [ "$KILLED" -gt 0 ]; then
  sleep 2
  for pid in $(pgrep -f "$MCP_PATTERNS" 2>/dev/null); do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ "$ppid" = "1" ]; then
      kill -9 "$pid" 2>/dev/null
    fi
  done
fi

# --- Phase 3: Kill old orphan node processes (ppid=1, running > 1 hour) ---
for pid in $(pgrep -x node 2>/dev/null); do
  ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  if [ "$ppid" = "1" ]; then
    etime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')
    if echo "$etime" | grep -q '-'; then
      # Days-old — definitely stale
      kill "$pid" 2>/dev/null && KILLED=$((KILLED + 1))
    elif echo "$etime" | grep -qE '^[0-9]+:[0-9]+:[0-9]+$'; then
      # HH:MM:SS — at least 1 hour old
      kill "$pid" 2>/dev/null && KILLED=$((KILLED + 1))
    fi
  fi
done

[ "$KILLED" -gt 0 ] && logger -t mcp-cleanup "Total cleaned: $KILLED processes"

exit 0
