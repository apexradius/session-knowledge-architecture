#!/bin/bash
# install.sh — Session Knowledge Architecture installer
#
# Copies rules, hooks, and templates to ~/.claude/
# Deep-merges SKA hooks into existing settings.json (preserves all other config)
# Writes .ska-manifest for clean uninstall
#
# Usage: ./install.sh [--dry-run]
# Idempotent: safe to run multiple times

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
RULES_DIR="$CLAUDE_DIR/rules"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SESSIONS_DIR="$CLAUDE_DIR/sessions"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
MANIFEST_FILE="$CLAUDE_DIR/.ska-manifest"
DRY_RUN=false

if [ "$1" = "--dry-run" ]; then
  DRY_RUN=true
  echo "[DRY RUN] No files will be modified."
  echo ""
fi

# --- OS Detection ---
OS=$(uname -s)
case "$OS" in
  Darwin) PLATFORM="macOS" ;;
  Linux)  PLATFORM="Linux" ;;
  *)      echo "WARNING: Unsupported OS ($OS). Proceeding anyway." ; PLATFORM="Unknown" ;;
esac

echo "=== Session Knowledge Architecture — Installer ==="
echo "    Platform: $PLATFORM"
echo "    Target: $CLAUDE_DIR"
echo ""

# Track installed files for manifest
INSTALLED_FILES=()

install_file() {
  local src="$1"
  local dst="$2"
  local mode="${3:-644}"

  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] $src → $dst"
  else
    cp "$src" "$dst"
    chmod "$mode" "$dst"
    echo "  ✓ $(basename "$dst")"
  fi
  INSTALLED_FILES+=("$dst")
}

# --- Create directories ---
echo "--- Creating directories ---"
for dir in "$RULES_DIR" "$HOOKS_DIR" "$SESSIONS_DIR" "$SESSIONS_DIR/archive"; do
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] mkdir -p $dir"
  else
    mkdir -p "$dir"
    echo "  ✓ $dir"
  fi
done
echo ""

# --- Copy rules (non-template .md files) ---
echo "--- Installing rules ---"
for rule in "$SCRIPT_DIR"/rules/*.md; do
  [ -f "$rule" ] || continue
  dst="$RULES_DIR/$(basename "$rule")"
  # Don't overwrite if destination exists and is newer (user may have customized)
  if [ -f "$dst" ] && [ "$dst" -nt "$rule" ]; then
    echo "  ⊘ $(basename "$rule") (local copy is newer, skipping)"
  else
    install_file "$rule" "$dst"
  fi
done
echo ""

# --- Copy templates (preserve .template suffix) ---
echo "--- Installing templates ---"
TEMPLATES_NEEDING_CUSTOMIZATION=()
for tmpl in "$SCRIPT_DIR"/rules/*.template; do
  [ -f "$tmpl" ] || continue
  dst="$RULES_DIR/$(basename "$tmpl")"
  install_file "$tmpl" "$dst"
  TEMPLATES_NEEDING_CUSTOMIZATION+=("$(basename "$tmpl")")
done
echo ""

# --- Copy hooks ---
echo "--- Installing hooks ---"
for hook in "$SCRIPT_DIR"/hooks/*.sh; do
  [ -f "$hook" ] || continue
  dst="$HOOKS_DIR/$(basename "$hook")"
  install_file "$hook" "$dst" "755"
done
echo ""

# --- Deep merge hooks into settings.json ---
echo "--- Merging hooks into settings.json ---"

if [ "$DRY_RUN" = true ]; then
  echo "  [dry-run] Would merge SKA hooks into $SETTINGS_FILE"
else
  # Create settings.json if it doesn't exist
  if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
  fi

  python3 << 'PYEOF'
import json, sys, os

settings_file = os.path.expanduser("~/.claude/settings.json")
hooks_dir = os.path.expanduser("~/.claude/hooks")

# Read existing settings
with open(settings_file) as f:
    settings = json.load(f)

# Ensure hooks dict exists
if "hooks" not in settings:
    settings["hooks"] = {}

# SKA hooks to merge
ska_hooks = {
    "SessionStart": [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hooks_dir}/session-start.sh"
                }
            ]
        }
    ],
    "PreToolUse": [
        {
            "matcher": "Edit|Write",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hooks_dir}/planning-gate.sh"
                }
            ]
        },
        {
            "matcher": "Bash|Edit|Write",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hooks_dir}/read-only-gate.sh"
                }
            ]
        }
    ],
    "Stop": [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hooks_dir}/session-close.sh"
                }
            ]
        }
    ]
}

def is_ska_hook(hook_entry):
    """Check if a hook entry is an SKA-managed hook (by script path)."""
    for h in hook_entry.get("hooks", []):
        cmd = h.get("command", "")
        ska_scripts = [
            "session-start.sh", "session-close.sh",
            "planning-gate.sh", "read-only-gate.sh"
        ]
        if any(cmd.endswith(s) for s in ska_scripts):
            return True
    return False

# Merge: for each event type, remove existing SKA hooks, then append new ones
for event, new_entries in ska_hooks.items():
    existing = settings["hooks"].get(event, [])
    # Remove any existing SKA hooks (de-duplicate)
    filtered = [e for e in existing if not is_ska_hook(e)]
    # Append SKA hooks
    filtered.extend(new_entries)
    settings["hooks"][event] = filtered

# Write back
with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("  ✓ settings.json updated (SKA hooks merged)")
PYEOF
fi
echo ""

# --- Write manifest ---
echo "--- Writing manifest ---"
if [ "$DRY_RUN" = true ]; then
  echo "  [dry-run] Would write manifest with ${#INSTALLED_FILES[@]} entries"
else
  printf '%s\n' "${INSTALLED_FILES[@]}" > "$MANIFEST_FILE"
  echo "  ✓ .ska-manifest (${#INSTALLED_FILES[@]} files tracked)"
fi
echo ""

# --- Run rule validation ---
echo "--- Validating rules ---"
if [ "$DRY_RUN" = true ]; then
  echo "  [dry-run] Would validate rules in $RULES_DIR"
elif [ -f "$SCRIPT_DIR/tests/test-rules-loaded.sh" ]; then
  bash "$SCRIPT_DIR/tests/test-rules-loaded.sh" "$RULES_DIR" 2>&1 | tail -5
fi
echo ""

# --- Summary ---
echo "==========================================="
echo "=== Installation Complete ==="
echo "==========================================="
echo ""
echo "  Rules:     $RULES_DIR"
echo "  Hooks:     $HOOKS_DIR"
echo "  Sessions:  $SESSIONS_DIR"
echo "  Manifest:  $MANIFEST_FILE"
echo ""

if [ ${#TEMPLATES_NEEDING_CUSTOMIZATION[@]} -gt 0 ]; then
  echo "  Templates needing customization:"
  for tmpl in "${TEMPLATES_NEEDING_CUSTOMIZATION[@]}"; do
    echo "    → $RULES_DIR/$tmpl"
  done
  echo ""
  echo "  Copy each .template to .md (remove .template suffix),"
  echo "  then replace all <!-- REPLACE --> markers with your values."
  echo ""
fi

echo "  Next steps:"
echo "  1. Customize templates listed above"
echo "  2. Start a new Claude Code session to activate enforcement"
echo "  3. Run: ./tests/test-hooks.sh to verify hooks"
echo ""
