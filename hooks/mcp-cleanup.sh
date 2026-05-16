#!/bin/bash
# mcp-cleanup.sh — Kill orphan MCP processes
# Called by: Claude Stop hook + LaunchAgent safety net (every 5 min)
#
# Handles two failure modes:
# 1. Orphan MCP servers (ppid=1) left behind by dead Claude sessions
# 2. Duplicate MCP children left behind by editor reloads

MCP_PATTERNS="apex-core-mcp|apex-commerce-mcp|apex-automation-mcp|apex-social-mcp|apex-data-mcp|apex-tools-mcp|apex-browser-mcp|apex-github-mcp"

KILLED=0

# --- Phase 1: Kill stray `npm exec @apexradius/*-mcp` wrappers ---
# .mcp.json uses direct /opt/homebrew/bin/ paths, so these wrappers are always leaks.
# They hold MCP children as live descendants (ppid != 1), hiding zombies from phase 2.
for pid in $(pgrep -f "npm exec @apexradius/.*-mcp" 2>/dev/null); do
  kill "$pid" 2>/dev/null && KILLED=$((KILLED + 1))
done

# --- Phase 2: Dedup MCP processes (keep newest per binary) ---
# VS Code extension reloads can spawn new MCP children without killing old ones.
# Old duplicates still have a live parent (so phase 2 misses them). Keep newest, kill rest.
# Skip duplicates < 60s old to avoid racing a legitimate respawn.
for bin in apex-core-mcp apex-commerce-mcp apex-automation-mcp apex-social-mcp apex-data-mcp apex-tools-mcp apex-browser-mcp apex-github-mcp; do
  pids=$(pgrep -f "/opt/homebrew/bin/$bin\$" 2>/dev/null)
  count=$(echo "$pids" | wc -w | tr -d ' ')
  [ "$count" -le 1 ] && continue
  # Find newest PID by start time (lstart)
  newest=$(ps -o pid=,lstart= -p $pids 2>/dev/null | awk '{pid=$1; $1=""; print $0 "|" pid}' | sort | tail -1 | awk -F'|' '{print $2}')
  for pid in $pids; do
    [ "$pid" = "$newest" ] && continue
    # Skip very young duplicates (respawn race)
    etime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')
    if echo "$etime" | grep -qE '^[0-9]{1,2}$'; then
      continue
    fi
    kill "$pid" 2>/dev/null && KILLED=$((KILLED + 1))
  done
done

# --- Phase 3: Kill orphan MCP servers (ppid=1) ---
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

# --- Phase 4: Kill old orphan node processes (ppid=1, running > 1 hour) ---
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
