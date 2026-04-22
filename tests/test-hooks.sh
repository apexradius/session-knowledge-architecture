#!/bin/bash
# test-hooks.sh — Unit tests for SKA hooks
#
# Tests planning-gate.sh, read-only-gate.sh, and session-start.sh
# with mock JSON input and temp session directories.
#
# Usage: ./tests/test-hooks.sh
# Exit code: number of failures (0 = all passed)

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$REPO_DIR/hooks"

# Use a temp directory for all test state — clean isolation
TEST_HOME=$(mktemp -d)
TEST_SESSION_DIR="$TEST_HOME/.claude/sessions"
TEST_ARCHIVE_DIR="$TEST_SESSION_DIR/archive"
mkdir -p "$TEST_SESSION_DIR" "$TEST_ARCHIVE_DIR" "$TEST_HOME/.claude/rules" "$TEST_HOME/.claude/hooks"

PASS=0
FAIL=0
TOTAL=0

# --- Test helpers ---
assert_exit() {
  local test_name="$1"
  local expected_exit="$2"
  local actual_exit="$3"
  local output="$4"
  TOTAL=$((TOTAL + 1))

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    printf "  \033[32mPASS\033[0m %s\n" "$test_name"
    PASS=$((PASS + 1))
  else
    printf "  \033[31mFAIL\033[0m %s (expected exit %d, got %d)\n" "$test_name" "$expected_exit" "$actual_exit"
    if [ -n "$output" ]; then
      printf "       Output: %s\n" "$(echo "$output" | head -3)"
    fi
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local test_name="$1"
  local expected_text="$2"
  local actual_output="$3"
  TOTAL=$((TOTAL + 1))

  if echo "$actual_output" | grep -qi "$expected_text"; then
    printf "  \033[32mPASS\033[0m %s\n" "$test_name"
    PASS=$((PASS + 1))
  else
    printf "  \033[31mFAIL\033[0m %s (output missing: '%s')\n" "$test_name" "$expected_text"
    printf "       Got: %s\n" "$(echo "$actual_output" | head -3)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
echo ""
echo "=== SKA Hook Tests ==="
echo "    $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ============================================================================
echo "--- planning-gate.sh ---"

# Test 1: Blocks when no pointer file exists
rm -f "$TEST_SESSION_DIR/.current-session"
OUTPUT=$(echo '{}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/planning-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "blocks when no .current-session pointer" 2 "$EXIT_CODE" "$OUTPUT"
assert_contains "error mentions no active session" "422" "$OUTPUT"

# Test 2: Blocks when pointer file exists but session file missing
echo "SESSION-nonexistent.md" > "$TEST_SESSION_DIR/.current-session"
OUTPUT=$(echo '{}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/planning-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "blocks when session file missing" 2 "$EXIT_CODE" "$OUTPUT"

# Test 3: Blocks when session file exists but has no planning block
echo "SESSION-test.md" > "$TEST_SESSION_DIR/.current-session"
cat > "$TEST_SESSION_DIR/SESSION-test.md" << 'EOF'
# Session: 2026-04-16T14:30:00
## Planning Blocks
<!-- empty -->
## Corrections
## Decisions
EOF
OUTPUT=$(echo '{}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/planning-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "blocks when session has no planning block" 2 "$EXIT_CODE" "$OUTPUT"
assert_contains "error mentions ASSUMPTIONS" "ASSUMPTIONS" "$OUTPUT"

# Test 4: Blocks when session has only 2 assumptions (need 3)
cat > "$TEST_SESSION_DIR/SESSION-test.md" << 'EOF'
# Session: 2026-04-16T14:30:00
## Planning Blocks
### Task: Test
ASSUMPTIONS:
- The file exists at the expected path
- The JSON structure matches the schema

UNKNOWNS:
- Whether concurrent access is possible

VERIFICATION_PLAN:
- Run the test suite after changes
EOF
OUTPUT=$(echo '{}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/planning-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "blocks when only 2 assumptions (need 3)" 2 "$EXIT_CODE" "$OUTPUT"

# Test 5: Passes when all requirements met (3 assumptions, unknowns, verification)
cat > "$TEST_SESSION_DIR/SESSION-test.md" << 'EOF'
# Session: 2026-04-16T14:30:00
## Planning Blocks
### Task: Add error handling to API endpoint
ASSUMPTIONS:
- The /api/v1/users endpoint returns JSON with a "data" key
- The database connection pool is configured for max 10 connections
- Error responses should use HTTP 422 for validation failures

UNKNOWNS:
- Whether the rate limiter middleware runs before or after auth

VERIFICATION_PLAN:
- Run existing test suite to confirm no regressions
- Manually test the endpoint with invalid input
- Check error response format matches OpenAPI spec
EOF
OUTPUT=$(echo '{}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/planning-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "passes with valid planning block (3 assumptions + unknowns + verification)" 0 "$EXIT_CODE" "$OUTPUT"

# ============================================================================
echo ""
echo "--- read-only-gate.sh ---"

# Test 6: Passes when discovery mode is NOT active
rm -f "$TEST_HOME/.claude/.discovery-mode"
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"}}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/read-only-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "passes Edit when discovery mode inactive" 0 "$EXIT_CODE" "$OUTPUT"

# Test 7: Blocks Edit when discovery mode IS active
touch "$TEST_HOME/.claude/.discovery-mode"
OUTPUT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"}}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/read-only-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "blocks Edit when discovery mode active" 2 "$EXIT_CODE" "$OUTPUT"
assert_contains "error mentions discovery mode" "DISCOVERY" "$OUTPUT"

# Test 8: Allows Edit to sessions directory even in discovery mode
OUTPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/SESSION-test.md"}}' "$TEST_SESSION_DIR" | HOME="$TEST_HOME" bash "$HOOKS_DIR/read-only-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "allows Edit to sessions dir in discovery mode" 0 "$EXIT_CODE" "$OUTPUT"

# Test 9: Allows read-only Bash commands in discovery mode
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la /tmp"}}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/read-only-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "allows 'ls' in discovery mode" 0 "$EXIT_CODE" "$OUTPUT"

# Test 10: Blocks write Bash commands in discovery mode
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/foo"}}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/read-only-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "blocks 'rm -rf' in discovery mode" 2 "$EXIT_CODE" "$OUTPUT"

# Test 11: Allows piped read-only commands
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cat /tmp/foo | grep bar"}}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/read-only-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "allows piped read-only commands in discovery mode" 0 "$EXIT_CODE" "$OUTPUT"

# Test 12: Allows git status/log/diff
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git log --oneline -5"}}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/read-only-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "allows 'git log' in discovery mode" 0 "$EXIT_CODE" "$OUTPUT"

# Test: Blocks semicolon-chained destructive commands
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"cat /tmp/foo; rm -rf /"}}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/read-only-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "blocks 'cat; rm -rf' semicolon bypass" 2 "$EXIT_CODE" "$OUTPUT"

# Test: Blocks && chained destructive commands
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls /tmp && rm -rf /"}}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/read-only-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "blocks 'ls && rm -rf' chain bypass" 2 "$EXIT_CODE" "$OUTPUT"

# Test: Blocks command substitution
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo $(rm -rf /)"}}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/read-only-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "blocks command substitution $()" 2 "$EXIT_CODE" "$OUTPUT"

# Test: Blocks output redirection
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo foo > /tmp/evil.sh"}}' | HOME="$TEST_HOME" bash "$HOOKS_DIR/read-only-gate.sh" 2>&1)
EXIT_CODE=$?
assert_exit "blocks output redirection >" 2 "$EXIT_CODE" "$OUTPUT"

# Clean up discovery mode flag
rm -f "$TEST_HOME/.claude/.discovery-mode"

# ============================================================================
echo ""
echo "--- session-start.sh ---"

# Test 13: Creates session file and pointer
rm -rf "$TEST_SESSION_DIR"/*
OUTPUT=$(HOME="$TEST_HOME" CLAUDE_SESSION_ID="test-session-001" bash "$HOOKS_DIR/session-start.sh" 2>&1)
EXIT_CODE=$?
assert_exit "session-start exits 0" 0 "$EXIT_CODE" "$OUTPUT"

# Test 14: Pointer file created
TOTAL=$((TOTAL + 1))
if [ -f "$TEST_SESSION_DIR/.current-session" ]; then
  POINTER_CONTENT=$(cat "$TEST_SESSION_DIR/.current-session")
  if [ "$POINTER_CONTENT" = "SESSION-test-session-001.md" ]; then
    printf "  \033[32mPASS\033[0m pointer file created with correct content\n"
    PASS=$((PASS + 1))
  else
    printf "  \033[31mFAIL\033[0m pointer file has wrong content: %s\n" "$POINTER_CONTENT"
    FAIL=$((FAIL + 1))
  fi
else
  printf "  \033[31mFAIL\033[0m pointer file not created\n"
  FAIL=$((FAIL + 1))
fi

# Test 15: Session file created with expected structure
SESSION_FILE="$TEST_SESSION_DIR/SESSION-test-session-001.md"
TOTAL=$((TOTAL + 1))
if [ -f "$SESSION_FILE" ]; then
  if grep -q "Planning Blocks" "$SESSION_FILE" && grep -q "Corrections" "$SESSION_FILE" && grep -q "Decisions" "$SESSION_FILE"; then
    printf "  \033[32mPASS\033[0m session file has correct structure\n"
    PASS=$((PASS + 1))
  else
    printf "  \033[31mFAIL\033[0m session file missing expected sections\n"
    FAIL=$((FAIL + 1))
  fi
else
  printf "  \033[31mFAIL\033[0m session file not created\n"
  FAIL=$((FAIL + 1))
fi

# Test 16: Output contains enforcement context
assert_contains "output mentions enforcement mode" "ENFORCEMENT" "$OUTPUT"

# Test 17: Second start archives the first session
OUTPUT2=$(HOME="$TEST_HOME" CLAUDE_SESSION_ID="test-session-002" bash "$HOOKS_DIR/session-start.sh" 2>&1)
TOTAL=$((TOTAL + 1))
ARCHIVED=$(find "$TEST_ARCHIVE_DIR" -name "SESSION-test-session-001*" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$ARCHIVED" -ge 1 ]; then
  printf "  \033[32mPASS\033[0m previous session archived on new start\n"
  PASS=$((PASS + 1))
else
  printf "  \033[31mFAIL\033[0m previous session not archived (found %s files)\n" "$ARCHIVED"
  FAIL=$((FAIL + 1))
fi

# Test: Re-fire with same session ID does NOT wipe existing session
# Add planning content to session-002
cat >> "$TEST_SESSION_DIR/SESSION-test-session-002.md" << 'EOF'
### Task: Test re-fire protection
ASSUMPTIONS:
- Re-firing session-start should not wipe this content
- The pointer file should remain unchanged
- The session file should keep its planning blocks

UNKNOWNS:
- None for test

VERIFICATION_PLAN:
- Check content survives
EOF

OUTPUT3=$(HOME="$TEST_HOME" CLAUDE_SESSION_ID="test-session-002" bash "$HOOKS_DIR/session-start.sh" 2>&1)
EXIT_CODE=$?
assert_exit "re-fire with same session ID exits 0" 0 "$EXIT_CODE" "$OUTPUT3"

# Verify planning blocks survived
TOTAL=$((TOTAL + 1))
if grep -q "Re-firing session-start should not wipe" "$TEST_SESSION_DIR/SESSION-test-session-002.md" 2>/dev/null; then
  printf "  \033[32mPASS\033[0m re-fire preserves existing planning blocks\n"
  PASS=$((PASS + 1))
else
  printf "  \033[31mFAIL\033[0m re-fire wiped existing planning blocks\n"
  FAIL=$((FAIL + 1))
fi

# Test: Re-fire without CLAUDE_SESSION_ID uses stable fallback, doesn't wipe
OUTPUT4=$(HOME="$TEST_HOME" bash "$HOOKS_DIR/session-start.sh" 2>&1)
# The fallback ID is date-based, so it creates a different session file
# but should NOT archive session-002 since session-002 pointer is still valid
# Actually with the fix, since a valid session exists, it skips entirely
TOTAL=$((TOTAL + 1))
if [ -f "$TEST_SESSION_DIR/SESSION-test-session-002.md" ]; then
  if grep -q "Re-firing session-start should not wipe" "$TEST_SESSION_DIR/SESSION-test-session-002.md" 2>/dev/null; then
    printf "  \033[32mPASS\033[0m no-ID re-fire preserves existing session\n"
    PASS=$((PASS + 1))
  else
    printf "  \033[31mFAIL\033[0m no-ID re-fire wiped session content\n"
    FAIL=$((FAIL + 1))
  fi
else
  printf "  \033[31mFAIL\033[0m no-ID re-fire deleted session file\n"
  FAIL=$((FAIL + 1))
fi

# ============================================================================
echo ""
echo "--- session-close.sh ---"

# Test 18: Archives session with content on close
cat > "$TEST_SESSION_DIR/SESSION-test-session-002.md" << 'EOF'
# Session: 2026-04-16T15:00:00
## Planning Blocks
### Task: Test close
ASSUMPTIONS:
- This is a test
- Testing close behavior
- Third assumption

UNKNOWNS:
- None for test

VERIFICATION_PLAN:
- Check archive dir
EOF
echo "SESSION-test-session-002.md" > "$TEST_SESSION_DIR/.current-session"

OUTPUT=$(HOME="$TEST_HOME" bash "$HOOKS_DIR/session-close.sh" 2>&1)
EXIT_CODE=$?
assert_exit "session-close exits 0" 0 "$EXIT_CODE" "$OUTPUT"

TOTAL=$((TOTAL + 1))
ARCHIVED_CLOSE=$(find "$TEST_ARCHIVE_DIR" -name "SESSION-test-session-002*" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$ARCHIVED_CLOSE" -ge 1 ]; then
  printf "  \033[32mPASS\033[0m session with content archived on close\n"
  PASS=$((PASS + 1))
else
  printf "  \033[31mFAIL\033[0m session not archived on close\n"
  FAIL=$((FAIL + 1))
fi

# Test 19: Pointer file removed after close
TOTAL=$((TOTAL + 1))
if [ ! -f "$TEST_SESSION_DIR/.current-session" ]; then
  printf "  \033[32mPASS\033[0m pointer file removed after close\n"
  PASS=$((PASS + 1))
else
  printf "  \033[31mFAIL\033[0m pointer file still exists after close\n"
  FAIL=$((FAIL + 1))
fi

# Test 20: Discovery mode flag cleaned up
touch "$TEST_HOME/.claude/.discovery-mode"
echo "SESSION-cleanup-test.md" > "$TEST_SESSION_DIR/.current-session"
cat > "$TEST_SESSION_DIR/SESSION-cleanup-test.md" << 'EOF'
# Session: 2026-04-16T16:00:00
## Planning Blocks
## Corrections
## Decisions
EOF
HOME="$TEST_HOME" bash "$HOOKS_DIR/session-close.sh" 2>/dev/null
TOTAL=$((TOTAL + 1))
if [ ! -f "$TEST_HOME/.claude/.discovery-mode" ]; then
  printf "  \033[32mPASS\033[0m discovery mode flag cleaned up on close\n"
  PASS=$((PASS + 1))
else
  printf "  \033[31mFAIL\033[0m discovery mode flag still exists after close\n"
  FAIL=$((FAIL + 1))
fi

# ============================================================================
# --- Cleanup ---
rm -rf "$TEST_HOME"

# --- Summary ---
echo ""
echo "==========================================="
echo "=== SKA Hook Test Results ==="
echo "==========================================="
echo ""
if [ "$FAIL" -eq 0 ]; then
  printf "  \033[32m=== %d/%d passed ===\033[0m\n" "$PASS" "$TOTAL"
else
  printf "  \033[31m=== %d/%d passed, %d failed ===\033[0m\n" "$PASS" "$TOTAL" "$FAIL"
fi
echo ""

exit "$FAIL"
