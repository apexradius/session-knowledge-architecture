#!/bin/bash
# post-install-verify.sh — PostToolUse hook for Bash commands
#
# Detects when an apex MCP package is globally installed via npm.
# Runs the smoke test for that specific package.
# If the tool count dropped, warns Claude to revert.
#
# This is structural — it fires automatically after every Bash command.
# No one needs to remember to run it. No one can skip it.

INPUT=$(cat)

# Extract the command that was run
COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except:
    print('')
" 2>/dev/null)

# Only trigger on npm install -g that involves apex packages
case "$COMMAND" in
  *"npm install -g"*|*"npm i -g"*)
    # Check if it's an apex package (either in an apex project dir or explicit @apexradius)
    if echo "$COMMAND" | grep -qiE "apex|@apexradius"; then
      : # Continue to verification
    else
      exit 0  # Not an apex package, skip
    fi
    ;;
  *)
    exit 0  # Not a global install command, skip
    ;;
esac

# Check if the install succeeded
EXIT_CODE=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    r = d.get('tool_response', {})
    # tool_response might be a string or dict
    if isinstance(r, dict):
        print(r.get('exit_code', r.get('exitCode', 0)))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null)

if [ "$EXIT_CODE" != "0" ]; then
  exit 0  # Install failed, nothing to verify
fi

# Run the smoke test
RESULT=$(/Users/Ayo/projects/test-mcp-suite.sh 2>/dev/null)
FAILURES=$(echo "$RESULT" | grep -c "FAIL" || true)

if [ "$FAILURES" -gt 0 ]; then
  FAIL_DETAILS=$(echo "$RESULT" | grep "FAIL" | sed 's/\x1b\[[0-9;]*m//g' | tr '\n' '; ')

  python3 -c "
import json
msg = '''MCP REGRESSION DETECTED after npm install -g.
${FAIL_DETAILS}
Run: /Users/Ayo/projects/test-mcp-suite.sh
Revert the install before continuing. Do NOT report this as successful.'''
print(json.dumps({'additionalContext': msg}))
"
fi

exit 0
