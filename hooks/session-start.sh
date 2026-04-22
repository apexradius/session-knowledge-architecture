#!/bin/bash
# session-start.sh — SessionStart hook
#
# Creates SESSION.md for the current session, verifies rules are loaded,
# and injects enforcement context so the model knows the 422 gate is active.
#
# IMPORTANT: If a valid session already exists, this hook skips creation
# to prevent mid-session re-fires from wiping planning blocks.
#
# Event: SessionStart
# Matcher: (none — fires on every session start)
# Output: JSON with "additionalContext" key

SESSION_DIR="$HOME/.claude/sessions"
ARCHIVE_DIR="$SESSION_DIR/archive"
RULES_DIR="$HOME/.claude/rules"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')
DATE_SLUG=$(date '+%Y%m%d-%H%M%S')

# --- Determine session ID ---
# Use CLAUDE_SESSION_ID if available (runtime export), fall back to date-based stable ID
if [ -n "$CLAUDE_SESSION_ID" ]; then
  SID="$CLAUDE_SESSION_ID"
else
  # Stable fallback: date-based ID (same value for the entire day)
  # This prevents the PID problem where each hook invocation gets a different ID
  SID="$(date '+%Y%m%d')"
fi

SESSION_FILENAME="SESSION-${SID}.md"
SESSION_FILE="$SESSION_DIR/$SESSION_FILENAME"
POINTER_FILE="$SESSION_DIR/.current-session"

# --- Create directories ---
mkdir -p "$SESSION_DIR" "$ARCHIVE_DIR"

# --- Check if this is a re-fire of the same session ---
# Only skip if the pointer points to a file that matches THIS session's ID.
# A genuinely new session (different CLAUDE_SESSION_ID) should archive and create.
SKIP_CREATION=false
if [ -f "$POINTER_FILE" ]; then
  EXISTING_FILENAME=$(cat "$POINTER_FILE" 2>/dev/null | tr -d '[:space:]')
  EXISTING_FILE="$SESSION_DIR/$EXISTING_FILENAME"
  if [ -f "$EXISTING_FILE" ] && [ "$EXISTING_FILENAME" = "$SESSION_FILENAME" ]; then
    # Same session re-fired — preserve planning blocks, skip creation
    SKIP_CREATION=true
  elif [ -f "$EXISTING_FILE" ] && [ -z "$CLAUDE_SESSION_ID" ]; then
    # No session ID available — assume re-fire, preserve existing session
    SESSION_FILE="$EXISTING_FILE"
    SESSION_FILENAME="$EXISTING_FILENAME"
    SKIP_CREATION=true
  fi
fi

if [ "$SKIP_CREATION" = "false" ]; then
  # --- Archive any stale current session ---
  if [ -f "$POINTER_FILE" ]; then
    OLD_FILENAME=$(cat "$POINTER_FILE" 2>/dev/null | tr -d '[:space:]')
    OLD_FILE="$SESSION_DIR/$OLD_FILENAME"
    if [ -f "$OLD_FILE" ] && [ "$OLD_FILE" != "$SESSION_FILE" ]; then
      mv "$OLD_FILE" "$ARCHIVE_DIR/${OLD_FILENAME%.md}-archived-${DATE_SLUG}.md" 2>/dev/null
    fi
  fi

  # --- Create fresh SESSION.md ---
  cat > "$SESSION_FILE" << EOF
# Session: ${TIMESTAMP}
## Session ID: ${SID}

## Planning Blocks

<!-- Write planning blocks here before editing any file.
     Each block must contain ASSUMPTIONS (3+), UNKNOWNS (1+), and VERIFICATION_PLAN (1+).
     The planning-gate.sh hook will reject Edit/Write calls until this is populated. -->

## Corrections

<!-- Record corrections during this session: what was wrong, what was correct -->

## Decisions

<!-- Record decisions made during this session with rationale -->
EOF

  # --- Write pointer file (no symlinks — policy) ---
  echo "$SESSION_FILENAME" > "$POINTER_FILE"
fi

# --- Verify rules ---
RULES_COUNT=0
MISSING_RULES=""
TEMPLATE_WARNINGS=""

if [ -d "$RULES_DIR" ]; then
  for rule in "$RULES_DIR"/*.md; do
    [ -f "$rule" ] || continue
    RULES_COUNT=$((RULES_COUNT + 1))
  done

  # Check for uncustomized templates (files with <!-- REPLACE markers)
  for rule in "$RULES_DIR"/*.md; do
    [ -f "$rule" ] || continue
    if grep -q '<!-- REPLACE' "$rule" 2>/dev/null; then
      basename_rule=$(basename "$rule")
      TEMPLATE_WARNINGS="${TEMPLATE_WARNINGS}  - ${basename_rule} has uncustomized <!-- REPLACE --> markers\n"
    fi
  done
fi

# Check for core rule files
CORE_RULES="anthropic-overrides.md behavioral.md delegation.md unknowns-requirement.md"
for rule in $CORE_RULES; do
  if [ ! -f "$RULES_DIR/$rule" ]; then
    MISSING_RULES="${MISSING_RULES}  - ${rule}\n"
  fi
done

# --- Count hooks ---
HOOKS_COUNT=0
if [ -d "$HOME/.claude/hooks" ]; then
  HOOKS_COUNT=$(find "$HOME/.claude/hooks" -name "*.sh" -o -name "*.js" 2>/dev/null | wc -l | tr -d ' ')
fi

# --- Build output ---
WARNINGS=""
if [ -n "$MISSING_RULES" ]; then
  WARNINGS="${WARNINGS}\nMISSING CORE RULES:\n${MISSING_RULES}"
fi
if [ -n "$TEMPLATE_WARNINGS" ]; then
  WARNINGS="${WARNINGS}\nUNCUSTOMIZED TEMPLATES:\n${TEMPLATE_WARNINGS}"
fi

CONTEXT="Session Knowledge Architecture — ENFORCEMENT MODE ACTIVE

A 422 Planning Gate monitors ALL Edit/Write tool calls. You CANNOT modify files
without first writing a planning block to SESSION.md containing:
  - ASSUMPTIONS: 3+ specific assumptions about the task (no fluff)
  - UNKNOWNS: what you have NOT checked or verified
  - VERIFICATION_PLAN: how you will prove the change is correct

Session file: ${SESSION_FILE}
Write your planning block there before any edit.

Status: ${RULES_COUNT} rules loaded, ${HOOKS_COUNT} hooks active.${WARNINGS}"

python3 -c "
import json, sys
ctx = sys.stdin.read()
print(json.dumps({'additionalContext': ctx}))
" <<< "$CONTEXT"

exit 0
