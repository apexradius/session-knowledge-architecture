#!/bin/bash
# session-close.sh — Stop hook
#
# Archives the current SESSION.md to the archive directory with a timestamp,
# cleans up temp flags (discovery mode), and chains to mcp-cleanup.sh.
#
# Event: Stop
# Matcher: (none — fires on every session stop)

SESSION_DIR="$HOME/.claude/sessions"
ARCHIVE_DIR="$SESSION_DIR/archive"
POINTER_FILE="$SESSION_DIR/.current-session"
DATE_SLUG=$(date '+%Y%m%d-%H%M%S')

# --- Guard: only run on real session close, not sub-agent stops ---
# If our parent process is still alive, this is a sub-agent termination.
# When the main session exits, PPID is gone. When a sub-agent stops, PPID (main session) is alive.
# This is immune to multi-terminal, Claude Desktop, and any "claude" string matches.
if [ "${SKA_FORCE_SESSION_CLOSE:-0}" != "1" ] && kill -0 "$PPID" 2>/dev/null; then
  exit 0  # Parent still alive — sub-agent stop, not real session close
fi

# --- Archive current session ---
if [ -f "$POINTER_FILE" ]; then
  SESSION_FILENAME=$(cat "$POINTER_FILE" 2>/dev/null | tr -d '[:space:]')
  SESSION_FILE="$SESSION_DIR/$SESSION_FILENAME"

  if [ -f "$SESSION_FILE" ]; then
    mkdir -p "$ARCHIVE_DIR"

    # Only archive if the session has content beyond the template
    # (i.e., planning blocks, corrections, or decisions were added)
    HAS_CONTENT=$(python3 -c "
import re, sys
try:
    with open('${SESSION_FILE}') as f:
        content = f.read()
    # Check if any section has actual content (not just HTML comments)
    has_planning = bool(re.search(r'ASSUMPTIONS:', content, re.IGNORECASE))
    has_corrections = bool(re.search(r'^- \[', content, re.MULTILINE))
    has_decisions = bool(re.search(r'^- \[', content, re.MULTILINE))
    if has_planning or has_corrections or has_decisions:
        print('yes')
    else:
        print('no')
except:
    print('no')
" 2>/dev/null)

    if [ "$HAS_CONTENT" = "yes" ]; then
      # Archive with timestamp
      ARCHIVE_NAME="${SESSION_FILENAME%.md}-closed-${DATE_SLUG}.md"
      cp "$SESSION_FILE" "$ARCHIVE_DIR/$ARCHIVE_NAME"
    fi

    # Remove the active session file
    rm -f "$SESSION_FILE"
  fi

  # Remove the pointer
  rm -f "$POINTER_FILE"
fi

# --- Clean up discovery mode flag ---
rm -f "$HOME/.claude/.discovery-mode"

# --- Clean up temp flags ---
rm -f /tmp/.claude-discovery-* 2>/dev/null

# mcp-cleanup.sh runs as a separate Stop hook in settings.json — no chain needed

exit 0
