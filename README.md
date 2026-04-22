# Session Knowledge Architecture (SKA)

Enforcement layer for Claude Code that transforms "state your assumptions" from a rule the model can skip into a protocol the CLI enforces.

## The Problem

Claude Code is a probabilistic engine optimized for confident, fast token generation. When it lacks context, it generates plausible-sounding answers instead of stopping. No amount of documentation fixes this — the tendency is in the weights.

The solution is not to make the AI better. It's to build enforcement that catches failures before they reach production.

## Quick Start

```bash
git clone https://github.com/apexradius/session-knowledge-architecture.git
cd session-knowledge-architecture
./install.sh
```

This copies rules, hooks, and templates to `~/.claude/` and merges SKA hooks into your existing `settings.json` (non-destructively). Run `./install.sh --dry-run` to preview.

To remove: `./uninstall.sh` (preserves session archives) or `./uninstall.sh --purge` (removes everything).

## Architecture: Four Layers

```
┌─────────────────────────────────────────┐
│            SESSION STATE                │
│  SESSION.md — assumptions, unknowns,    │
│  corrections across turns               │
└──────────────────┬──────────────────────┘
                   │ reads/writes
┌──────────────────┼──────────────────────┐
│           ENFORCEMENT (Hooks)            │
│  SessionStart → session-start.sh        │
│  PreToolUse  → planning-gate.sh [422]   │
│  PreToolUse  → read-only-gate.sh        │
│  PostToolUse → post-install-verify.sh   │
│  Stop        → session-close.sh         │
│  Stop        → mcp-cleanup.sh           │
└──────────────────┼──────────────────────┘
                   │ constrained by
┌──────────────────┼──────────────────────┐
│          KNOWLEDGE (Rules)               │
│  9 always-loaded + N path-scoped rules  │
└──────────────────┼──────────────────────┘
                   │ validated by
┌──────────────────┼──────────────────────┐
│        VERIFICATION (Tests)              │
│  test-hooks.sh, test-rules-loaded.sh,   │
│  test-mcp-suite.sh                      │
└─────────────────────────────────────────┘
```

## The 422 Pattern: Planning Gate

The critical enforcement mechanism. `planning-gate.sh` is a `PreToolUse` hook that **blocks all Edit/Write calls** unless a planning block exists in the session's `SESSION.md` file.

### How it works

1. Model attempts to edit a file
2. `planning-gate.sh` reads `SESSION.md` for the current session
3. If no planning block with **ASSUMPTIONS** (3+), **UNKNOWNS** (1+), and **VERIFICATION_PLAN** (1+) → **exit 2** (tool call rejected)
4. If planning block exists → exit 0 (tool call proceeds)

The model physically cannot write code until it has:
- Listed its assumptions (3 minimum, must be task-specific)
- Identified what it hasn't checked
- Described how it will verify the change

### Why this works

The planning block is written to a file, not just stated in chat. This creates a verifiable artifact that hooks can check mechanically. The act of pausing to write anything is itself a circuit breaker against confident sprinting.

## Hooks Reference

| Hook | Event | Matcher | Behavior |
|------|-------|---------|----------|
| `session-start.sh` | SessionStart | — | Creates `SESSION.md`, verifies rules loaded, injects enforcement context |
| `planning-gate.sh` | PreToolUse | `Edit\|Write` | **422 blocks** edits without planning block in SESSION.md |
| `read-only-gate.sh` | PreToolUse | `Bash\|Edit\|Write` | Blocks writes when `~/.claude/.discovery-mode` flag exists |
| `post-install-verify.sh` | PostToolUse | `Bash` | Runs smoke tests after `npm install -g` of apex packages |
| `session-close.sh` | Stop | — | Archives SESSION.md, cleans up flags, chains to mcp-cleanup |
| `mcp-cleanup.sh` | Stop | — | Kills orphan MCP servers and recursive claude fork chains |

## SESSION.md

Each session gets a `SESSION.md` that accumulates state across turns.

**Created by:** `session-start.sh`
**Location:** `~/.claude/sessions/SESSION-{session-id}.md`
**Archived by:** `session-close.sh` → `~/.claude/sessions/archive/`

See `examples/SESSION.md.example` for annotated format.

### Structure

```markdown
# Session: 2026-04-16T14:30:00
## Planning Blocks
### Task: [description]
ASSUMPTIONS:
- [specific assumption about task logic]
- [specific assumption about data/API behavior]
- [specific assumption about system state]

UNKNOWNS:
- [what you haven't checked]

VERIFICATION_PLAN:
- [how you'll prove correctness]

STATUS: in_progress | verified | failed

## Corrections
- [timestamp] [what was wrong] → [what was correct]

## Decisions
- [timestamp] [decision] [rationale]
```

## Discovery Mode

Create `~/.claude/.discovery-mode` to force read-only exploration:

```bash
touch ~/.claude/.discovery-mode    # Enable
rm ~/.claude/.discovery-mode       # Disable
```

While active, `read-only-gate.sh` blocks all writes except to `~/.claude/sessions/` (so planning blocks can still be written). Only whitelisted read-only Bash commands are allowed.

## Rules

| File | Description |
|------|-------------|
| `anthropic-overrides.md` | Suppress unhelpful default behaviors (recaps, hedging, padding) |
| `behavioral.md` | Accumulated corrections from real failures |
| `delegation.md` | Sub-agent protocol with verification gates |
| `unknowns-requirement.md` | Mandatory assumption declaration before any solution |

### Templates (customize after install)

| File | Description |
|------|-------------|
| `identity.md.template` | Company info, revenue targets, priorities |
| `tools.md.template` | MCP servers, tool counts, usage rules |
| `skills.md.template` | Skills trigger routing table |
| `infrastructure.md.template` | Machines, servers, key paths |
| `standing-rules.md.template` | Non-negotiable rules for every session |

Copy each `.template` to `.md` (remove suffix) and replace all `<!-- REPLACE -->` markers.

## Tests

```bash
./tests/test-hooks.sh          # Unit tests for all hooks (24 tests)
./tests/test-rules-loaded.sh   # Validates rule frontmatter + content
./tests/test-mcp-suite.sh      # MCP server smoke tests (if applicable)
```

## What This Does NOT Fix

- **Confident hallucination** — The unknowns requirement reduces but doesn't eliminate wrong facts
- **Subtle reasoning errors** — No hook can catch logical mistakes
- **Novel failure modes** — Hooks catch known error classes; new types need new hooks
- **Speed bias in weights** — Training pushes toward quick responses; the rules fight this but the bias remains

The user must remain the senior engineer. The architecture makes the model less dangerous, not safe.

## File Structure

```
session-knowledge-architecture/
  install.sh                     # Installer (deep-merges into settings.json)
  uninstall.sh                   # Uninstaller (reads .ska-manifest)
  rules/
    anthropic-overrides.md       # Suppress unhelpful defaults
    behavioral.md                # Corrections from real failures
    delegation.md                # Sub-agent protocol
    unknowns-requirement.md      # Mandatory assumption declaration
    identity.md.template         # [customize] Company/identity
    tools.md.template            # [customize] MCP servers
    skills.md.template           # [customize] Skills routing
    infrastructure.md.template   # [customize] Infrastructure
    standing-rules.md.template   # [customize] Hard rules
  hooks/
    session-start.sh             # SessionStart — creates SESSION.md
    session-close.sh             # Stop — archives SESSION.md
    planning-gate.sh             # PreToolUse — 422 planning gate
    read-only-gate.sh            # PreToolUse — discovery mode
    post-install-verify.sh       # PostToolUse — npm install verification
    mcp-cleanup.sh               # Stop — orphan process cleanup
  tests/
    test-hooks.sh                # Hook unit tests
    test-rules-loaded.sh         # Rule validation
    test-mcp-suite.sh            # MCP smoke tests
  examples/
    settings.json                # Example settings with all hooks
    SESSION.md.example           # Annotated session file example
```
