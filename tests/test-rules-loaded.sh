#!/bin/bash
# test-rules-loaded.sh — Validates rule files in the SKA repo
#
# Checks:
# 1. Proper YAML frontmatter (description, globs)
# 2. No uncustomized <!-- REPLACE --> markers in non-template files
# 3. No rule file exceeds 50 lines of content (excluding frontmatter)
#
# Usage: ./tests/test-rules-loaded.sh [rules-dir]
# Default rules-dir: ../rules (relative to this script)
# Exit code: number of failures (0 = all passed)

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULES_DIR="${1:-$(dirname "$SCRIPT_DIR")/rules}"

PASS=0
FAIL=0
TOTAL=0

assert() {
  local test_name="$1"
  local condition="$2"  # "pass" or "fail"
  local detail="$3"
  TOTAL=$((TOTAL + 1))

  if [ "$condition" = "pass" ]; then
    printf "  \033[32mPASS\033[0m %s\n" "$test_name"
    PASS=$((PASS + 1))
  else
    printf "  \033[31mFAIL\033[0m %s\n" "$test_name"
    [ -n "$detail" ] && printf "       %s\n" "$detail"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== SKA Rule Validation ==="
echo "    $(date '+%Y-%m-%d %H:%M:%S')"
echo "    Rules dir: $RULES_DIR"
echo ""

if [ ! -d "$RULES_DIR" ]; then
  echo "ERROR: Rules directory not found: $RULES_DIR"
  exit 1
fi

# --- Check each .md file (not templates) ---
for rule_file in "$RULES_DIR"/*.md; do
  [ -f "$rule_file" ] || continue
  basename_rule=$(basename "$rule_file")

  # Skip template files — they're expected to have REPLACE markers
  case "$basename_rule" in
    *.template) continue ;;
  esac

  echo "--- $basename_rule ---"

  # Test: Has YAML frontmatter delimiters
  FIRST_LINE=$(head -1 "$rule_file")
  TOTAL=$((TOTAL + 1))
  if [ "$FIRST_LINE" = "---" ]; then
    # Find closing delimiter
    CLOSE_LINE=$(tail -n +2 "$rule_file" | grep -n '^---$' | head -1 | cut -d: -f1)
    if [ -n "$CLOSE_LINE" ]; then
      printf "  \033[32mPASS\033[0m has YAML frontmatter\n"
      PASS=$((PASS + 1))
    else
      printf "  \033[31mFAIL\033[0m has opening --- but no closing ---\n"
      FAIL=$((FAIL + 1))
    fi
  else
    printf "  \033[31mFAIL\033[0m missing YAML frontmatter (first line: '%s')\n" "$FIRST_LINE"
    FAIL=$((FAIL + 1))
  fi

  # Test: Has description field
  HAS_DESC=$(grep -c '^description:' "$rule_file" 2>/dev/null)
  HAS_DESC=${HAS_DESC:-0}
  if [ "$HAS_DESC" -ge 1 ]; then
    assert "$basename_rule has description" "pass"
  else
    assert "$basename_rule has description" "fail" "missing 'description:' in frontmatter"
  fi

  # Test: Has globs field
  HAS_GLOBS=$(grep -c '^globs:' "$rule_file" 2>/dev/null)
  HAS_GLOBS=${HAS_GLOBS:-0}
  if [ "$HAS_GLOBS" -ge 1 ]; then
    assert "$basename_rule has globs" "pass"
  else
    assert "$basename_rule has globs" "fail" "missing 'globs:' in frontmatter"
  fi

  # Test: No uncustomized REPLACE markers
  REPLACE_COUNT=$(grep -c '<!-- REPLACE' "$rule_file" 2>/dev/null)
  REPLACE_COUNT=${REPLACE_COUNT:-0}
  if [ "$REPLACE_COUNT" -eq 0 ]; then
    assert "$basename_rule has no REPLACE markers" "pass"
  else
    assert "$basename_rule has no REPLACE markers" "fail" "found $REPLACE_COUNT uncustomized <!-- REPLACE --> markers"
  fi

  # Test: Content does not exceed 50 lines (after frontmatter)
  if [ -n "$CLOSE_LINE" ]; then
    FRONTMATTER_END=$((CLOSE_LINE + 1))
    CONTENT_LINES=$(tail -n +"$FRONTMATTER_END" "$rule_file" | wc -l | tr -d ' ')
  else
    CONTENT_LINES=$(wc -l < "$rule_file" | tr -d ' ')
  fi
  if [ "$CONTENT_LINES" -le 50 ]; then
    assert "$basename_rule under 50 content lines ($CONTENT_LINES)" "pass"
  else
    assert "$basename_rule under 50 content lines ($CONTENT_LINES)" "fail" "$CONTENT_LINES lines of content (max 50)"
  fi

  echo ""
done

# --- Check template files have REPLACE markers ---
echo "--- Template files ---"
for tmpl_file in "$RULES_DIR"/*.template; do
  [ -f "$tmpl_file" ] || continue
  basename_tmpl=$(basename "$tmpl_file")

  REPLACE_COUNT=$(grep -c '<!-- REPLACE' "$tmpl_file" 2>/dev/null)
  REPLACE_COUNT=${REPLACE_COUNT:-0}
  if [ "$REPLACE_COUNT" -ge 1 ]; then
    assert "$basename_tmpl has REPLACE markers ($REPLACE_COUNT)" "pass"
  else
    assert "$basename_tmpl has REPLACE markers" "fail" "template should have <!-- REPLACE --> markers"
  fi
done

# --- Summary ---
echo ""
echo "==========================================="
echo "=== SKA Rule Validation Results ==="
echo "==========================================="
echo ""
if [ "$FAIL" -eq 0 ]; then
  printf "  \033[32m=== %d/%d passed ===\033[0m\n" "$PASS" "$TOTAL"
else
  printf "  \033[31m=== %d/%d passed, %d failed ===\033[0m\n" "$PASS" "$TOTAL" "$FAIL"
fi
echo ""

exit "$FAIL"
