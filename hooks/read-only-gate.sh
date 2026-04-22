#!/bin/bash
# read-only-gate.sh — PreToolUse hook for Bash|Edit|Write
#
# When discovery mode is active (~/.claude/.discovery-mode flag file exists),
# blocks all write operations. Only allows read-only Bash commands.
#
# CRITICAL: Always allows writes to ~/.claude/sessions/ so the model can
# create its planning block in SESSION.md (avoids discovery/planning deadlock).
#
# Event: PreToolUse
# Matcher: Bash|Edit|Write
# Input: JSON on stdin with tool_name and tool_input

INPUT=$(cat)
DISCOVERY_FLAG="$HOME/.claude/.discovery-mode"

# --- If discovery mode is NOT active, pass through ---
if [ ! -f "$DISCOVERY_FLAG" ]; then
  exit 0
fi

# --- Discovery mode IS active — evaluate the tool call ---
# Pass INPUT via env var since stdin was consumed by cat above
SKA_INPUT="$INPUT" python3 << 'PYEOF'
import json, sys, re, os

try:
    data = json.loads(os.environ.get("SKA_INPUT", "{}"))
except json.JSONDecodeError:
    data = {}

tool_name = data.get("tool_name", "")
tool_input = data.get("tool_input", {})

sessions_dir = os.path.expanduser("~/.claude/sessions")

# --- Edit/Write tools ---
if tool_name in ("Edit", "Write"):
    file_path = tool_input.get("file_path", "")
    # Allow writes to sessions directory (planning blocks)
    if file_path.startswith(sessions_dir):
        sys.exit(0)
    msg = (
        "422 DISCOVERY MODE: Write operations are blocked during exploration phase. "
        "You are in read-only mode. Use Read, Grep, Glob, and read-only Bash commands "
        "to explore the codebase first.\n\n"
        "To exit discovery mode, the user must remove ~/.claude/.discovery-mode\n"
        "Exception: writes to ~/.claude/sessions/ (planning blocks) are always allowed."
    )
    print(json.dumps({"error": msg}))
    sys.exit(2)

# --- Bash tool ---
if tool_name == "Bash":
    command = tool_input.get("command", "")

    # Read-only command whitelist (prefix match)
    readonly_prefixes = [
        "ls", "cat", "head", "tail", "grep", "rg", "find",
        "git status", "git log", "git diff", "git show", "git branch",
        "wc", "file", "which", "echo", "pwd", "hostname", "whoami",
        "env", "printenv", "npm view", "npm list", "npm ls",
        "node -e", "node -p", "python3 -c",
        "tree", "stat", "du", "df", "uname", "date", "id",
        "test ", "[ ", "[[ ",
    ]

    # Normalize: strip leading whitespace
    cmd_stripped = command.strip()

    # Allow writes to sessions directory via Bash
    if sessions_dir in cmd_stripped:
        sys.exit(0)

    # Split command by ALL shell chaining operators (;, &&, ||, |)
    # This prevents "cat foo; rm -rf /" from bypassing the whitelist
    segments = re.split(r'\s*(?:;|&&|\|\||(?<!\|)\|(?!\|))\s*', cmd_stripped)
    segments = [s.strip() for s in segments if s.strip()]

    # Check each segment against whitelist
    all_readonly = True
    for seg in segments:
        # Block command substitution, subshells, and redirects
        if re.search(r'\$\(|`|>\s|>>|>\|', seg):
            all_readonly = False
            break
        seg_ok = False
        for prefix in readonly_prefixes:
            if seg.startswith(prefix):
                seg_ok = True
                break
        if not seg_ok:
            all_readonly = False
            break

    if all_readonly:
        sys.exit(0)

    msg = (
        f"422 DISCOVERY MODE: Command blocked: '{cmd_stripped[:80]}...'\n"
        "Only read-only commands are allowed during exploration phase.\n"
        "Allowed: ls, cat, head, tail, grep, rg, find, git status/log/diff/show, "
        "wc, file, which, echo, pwd, hostname, whoami, env, printenv, "
        "npm view/list, node -e, python3 -c, tree, stat, du, df\n\n"
        "To exit discovery mode, the user must remove ~/.claude/.discovery-mode"
    )
    print(json.dumps({"error": msg}))
    sys.exit(2)

# Unknown tool — pass through
sys.exit(0)
PYEOF
