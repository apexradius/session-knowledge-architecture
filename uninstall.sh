#!/bin/bash
# uninstall.sh — Session Knowledge Architecture uninstaller
#
# Removes SKA-managed files tracked in .ska-manifest
# Removes SKA hooks from settings.json (preserves all other config)
# Optionally purges session archives with --purge
#
# Usage: ./uninstall.sh [--purge]

set -eo pipefail

CLAUDE_DIR="$HOME/.claude"
MANIFEST_FILE="$CLAUDE_DIR/.ska-manifest"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SESSIONS_DIR="$CLAUDE_DIR/sessions"
PURGE=false

if [ "$1" = "--purge" ]; then
  PURGE=true
fi

echo "=== Session Knowledge Architecture — Uninstaller ==="
echo ""

# --- Remove files from manifest ---
echo "--- Removing SKA-managed files ---"
if [ -f "$MANIFEST_FILE" ]; then
  REMOVED=0
  while IFS= read -r filepath; do
    if [ -f "$filepath" ]; then
      rm -f "$filepath"
      echo "  ✓ removed $(basename "$filepath")"
      REMOVED=$((REMOVED + 1))
    fi
  done < "$MANIFEST_FILE"
  rm -f "$MANIFEST_FILE"
  echo "  Total: $REMOVED files removed"
else
  echo "  No .ska-manifest found. Removing known SKA files manually..."
  SKA_HOOKS="session-start.sh session-close.sh planning-gate.sh read-only-gate.sh"
  for hook in $SKA_HOOKS; do
    if [ -f "$CLAUDE_DIR/hooks/$hook" ]; then
      rm -f "$CLAUDE_DIR/hooks/$hook"
      echo "  ✓ removed $hook"
    fi
  done
fi
echo ""

# --- Remove SKA hooks from settings.json ---
echo "--- Cleaning settings.json ---"
if [ -f "$SETTINGS_FILE" ]; then
  python3 << 'PYEOF'
import json, os

settings_file = os.path.expanduser("~/.claude/settings.json")

with open(settings_file) as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})

ska_scripts = [
    "session-start.sh", "session-close.sh",
    "planning-gate.sh", "read-only-gate.sh"
]

def is_ska_hook(hook_entry):
    for h in hook_entry.get("hooks", []):
        cmd = h.get("command", "")
        if any(cmd.endswith(s) for s in ska_scripts):
            return True
    return False

changed = False
for event in list(hooks.keys()):
    original_len = len(hooks[event])
    hooks[event] = [e for e in hooks[event] if not is_ska_hook(e)]
    if len(hooks[event]) != original_len:
        changed = True
    # Remove empty event arrays
    if not hooks[event]:
        del hooks[event]
        changed = True

if changed:
    settings["hooks"] = hooks
    with open(settings_file, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print("  ✓ SKA hooks removed from settings.json")
else:
    print("  ⊘ No SKA hooks found in settings.json")
PYEOF
else
  echo "  ⊘ No settings.json found"
fi
echo ""

# --- Clean up session state ---
echo "--- Cleaning session state ---"
rm -f "$SESSIONS_DIR/.current-session"
rm -f "$CLAUDE_DIR/.discovery-mode"
rm -f /tmp/.claude-discovery-* 2>/dev/null

# Remove active session files (not archives)
ACTIVE_REMOVED=0
for f in "$SESSIONS_DIR"/SESSION-*.md; do
  [ -f "$f" ] || continue
  rm -f "$f"
  ACTIVE_REMOVED=$((ACTIVE_REMOVED + 1))
done
echo "  ✓ Removed $ACTIVE_REMOVED active session files"

if [ "$PURGE" = true ]; then
  echo ""
  echo "--- Purging session archives ---"
  if [ -d "$SESSIONS_DIR/archive" ]; then
    ARCHIVE_COUNT=$(find "$SESSIONS_DIR/archive" -type f 2>/dev/null | wc -l | tr -d ' ')
    rm -rf "$SESSIONS_DIR/archive"
    echo "  ✓ Purged $ARCHIVE_COUNT archived sessions"
  else
    echo "  ⊘ No archive directory found"
  fi
  # Remove sessions dir if empty
  rmdir "$SESSIONS_DIR" 2>/dev/null && echo "  ✓ Removed empty sessions directory" || true
fi
echo ""

# --- Summary ---
echo "==========================================="
echo "=== Uninstall Complete ==="
echo "==========================================="
echo ""
echo "  SKA hooks and rules have been removed."
echo "  Your other settings, hooks, and permissions are preserved."
if [ "$PURGE" = false ]; then
  echo ""
  echo "  Session archives preserved at: $SESSIONS_DIR/archive/"
  echo "  To also remove archives: ./uninstall.sh --purge"
fi
echo ""
