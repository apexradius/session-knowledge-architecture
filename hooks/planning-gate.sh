#!/bin/bash
# planning-gate.sh — PreToolUse hook for Edit|Write [422 PATTERN]
#
# Returns non-zero (exit 2) if no planning block exists in the active SESSION.md.
# The model must write a planning block to SESSION.md (with ASSUMPTIONS, UNKNOWNS,
# and VERIFICATION_PLAN) before any file edit is allowed.
#
# This is not a suggestion. This is a hard gate. The CLI rejects the tool call
# if this hook exits non-zero.
#
# Event: PreToolUse
# Matcher: Edit|Write
# Input: JSON on stdin with tool_input details
# Output: JSON with "error" key on rejection, empty on pass

INPUT=$(cat)
SESSION_DIR="$HOME/.claude/sessions"
POINTER_FILE="$SESSION_DIR/.current-session"

# --- Resolve the active session file ---
# No symlinks (policy). A .current-session pointer file contains the filename.
if [ ! -f "$POINTER_FILE" ]; then
  python3 -c "
import json
print(json.dumps({'error': '422: No active session found. session-start.sh must run first to create SESSION.md.'}))
"
  exit 2
fi

SESSION_FILENAME=$(cat "$POINTER_FILE" 2>/dev/null | tr -d '[:space:]')
SESSION_FILE="$SESSION_DIR/$SESSION_FILENAME"

if [ ! -f "$SESSION_FILE" ]; then
  python3 -c "
import json
print(json.dumps({'error': '422: SESSION.md (${SESSION_FILENAME}) not found. session-start.sh must run first.'}))
"
  exit 2
fi

# --- Check for planning block with required sections ---
# Requires ASSUMPTIONS (3+ items), UNKNOWNS, and VERIFICATION_PLAN
SKA_SESSION_FILE="$SESSION_FILE" python3 << 'PYEOF'
import re, sys, json, os

session_file = os.environ.get("SKA_SESSION_FILE", "")

try:
    with open(session_file) as f:
        content = f.read()
except (FileNotFoundError, PermissionError) as e:
    print(json.dumps({"error": f"422: Cannot read SESSION.md: {e}"}))
    sys.exit(2)

# Check for ASSUMPTIONS section with at least 3 items
assumptions_match = re.search(
    r'ASSUMPTIONS:\s*\n((?:\s*[-*]\s+.+\n?){3,})',
    content,
    re.IGNORECASE | re.MULTILINE
)

# Check for UNKNOWNS section with at least 1 item
unknowns_match = re.search(
    r'UNKNOWNS:\s*\n((?:\s*[-*]\s+.+\n?)+)',
    content,
    re.IGNORECASE | re.MULTILINE
)

# Check for VERIFICATION_PLAN section
verification_match = re.search(
    r'VERIFICATION[_ ]?PLAN:\s*\n((?:\s*[-*]\s+.+\n?)+)',
    content,
    re.IGNORECASE | re.MULTILINE
)

missing = []
if not assumptions_match:
    missing.append("ASSUMPTIONS (need 3+ specific items)")
if not unknowns_match:
    missing.append("UNKNOWNS (need 1+ items)")
if not verification_match:
    missing.append("VERIFICATION_PLAN (need 1+ items)")

if missing:
    msg = (
        "422 PLANNING REQUIRED: Before editing any file, write a planning block "
        "to SESSION.md with:\n"
        + "\n".join(f"  - {m}" for m in missing)
        + "\n\nWrite to SESSION.md first (Bash: cat >> or Write tool targeting "
        + session_file + "), then retry the edit.\n\n"
        "Forbidden fluff assumptions (these will not satisfy the gate):\n"
        "  - 'The code exists'\n"
        "  - 'I have permission'\n"
        "  - 'The environment is set up'\n"
        "  - 'The file is correctly formatted'\n"
        "  - 'The dependencies are installed'\n"
        "Assumptions must be specific to the internal logic of the current task."
    )
    print(json.dumps({"error": msg}))
    sys.exit(2)

# All checks passed
sys.exit(0)
PYEOF
