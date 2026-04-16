# Session Knowledge Architecture — Final Plan
**Updated:** 2026-04-16
**Context:** Full session of failures, corrections, research, and honest assessment of AI limitations

---

## The Core Problem

Claude Code is a probabilistic engine optimized for confident, fast token generation. It does not feel doubt. It does not experience consequences. When it lacks context, it generates plausible-sounding answers instead of stopping. No amount of documentation fixes this — the tendency is in the weights.

The solution is not to make the AI better. It's to build the CI/CD pipeline, verification loops, and execution constraints that catch its inevitable failures before they reach production.

---

## Architecture: Three Layers

### Layer 1: .claude/rules/ (Knowledge — What to Know)

Modular, path-scoped, auto-loaded. Replaces monolithic CLAUDE.md + Brain.md startup.

```
.claude/rules/
  identity.md              — Who, companies, Q2 targets, revenue priorities
  behavioral.md            — All accumulated corrections (excellence over speed,
                             verify before reporting, check memory before asking)
  anthropic-overrides.md   — Default behaviors to suppress (no recaps, no hedging,
                             no unrequested features, be decisive not deferential)
  unknowns-requirement.md  — MANDATORY: before any solution, list 3 assumptions
                             and identify missing context. Simulate doubt.
  tools.md                 — 8 MCPs with tool counts + when to use each
  skills.md                — 125 skills trigger table
  infrastructure.md        — Machines, VPS, NAS, key paths
  standing-rules.md        — Non-negotiable rules from Brain.md
  delegation.md            — Sub-agent protocol with verification gates
```

Path-scoped (load only when working in matching dirs):
```
  shopify.md               — paths: ["**/apex-commerce-mcp/**", "**/shopify/**"]
  vps.md                   — paths: ["**/keystone/**"]
```

**Total always-loaded: ~250 lines across 9 files**
Replaces: 554 lines across 3 files — smaller AND more complete.

### Layer 2: Structural Enforcement (Hooks — What to Enforce)

Hooks are the guardrails around the unreliable dependency. They execute regardless of what the model decides to do.

| Hook | Event | What It Enforces |
|------|-------|-----------------|
| prompt-enhancer.js | UserPromptSubmit | Rewrites prompts via haiku. Recursion guard prevents fork bomb. |
| post-install-verify.sh | PostToolUse (Bash) | After any `npm install -g` for apex packages, runs smoke test. Warns on regression. |
| mcp-cleanup.sh | Stop | Kills orphan MCPs, recursive chains, stale node processes. |
| LaunchAgent (cleanup) | Every 5 min | Safety net for crashes/force-quits. |
| LaunchAgent (upstream) | 1st of month | Checks upstream repos for updates worth porting. |

**Proposed new hooks:**

| Hook | Event | What It Enforces |
|------|-------|-----------------|
| read-only-gate.sh | PreToolUse (Bash/Edit/Write) | When in discovery phase (first N minutes or explicit flag), blocks write operations. Forces read-only exploration before modification. |
| unknowns-check.js | PreToolUse (Edit/Write) | Before first code edit in a session, checks if assumptions were stated. If not, injects reminder. |

### Layer 3: Verification Loops (Tests — What to Prove)

The test is the substitute for doubt.

| Test | When | What It Proves |
|------|------|----------------|
| test-mcp-suite.sh | After any MCP build/install | All 8 servers start, correct tool counts |
| Smoke test in PostToolUse | After npm install -g | No tool count regression |
| Unit tests per package | Before any PR/publish | Individual package correctness |

**Test-Driven AI Rule:** For any new tool or feature:
1. Write the test first (what does "correct" look like?)
2. Run it (it should fail — the feature doesn't exist yet)
3. Build the feature
4. Run the test again (it should pass)
5. If it doesn't pass, fix before reporting success

---

## The Unknowns Requirement

This is the single most important behavioral change. Add to `.claude/rules/unknowns-requirement.md`:

Before providing any solution, making any architectural decision, or asserting any fact about external systems:

1. **State 3 assumptions** you are making
2. **Identify what context or documentation you haven't checked**
3. **Verify the most critical assumption** before proceeding

If you cannot list your assumptions, you do not understand the problem well enough to act.

This is not optional. This is not a suggestion. This is a structural requirement like writing tests before code.

---

## What This Does NOT Fix

Being honest:

- **Confident hallucination** — I may still state wrong facts. The unknowns requirement reduces this but doesn't eliminate it.
- **Subtle reasoning errors** — I may make logical mistakes that no hook can catch.
- **Novel failure modes** — The hooks catch known error classes. New types of errors need new hooks.
- **Speed bias in weights** — My training pushes me toward quick responses. The rules fight this but the bias remains.

The user must remain the senior engineer. I am the fast, dangerously confident junior developer. The architecture makes me less dangerous, not safe.

---

## Implementation Phases

### Phase 1: Create .claude/rules/ directory (~1 hour)
1. Create each rules file from existing CLAUDE.md + Brain.md + feedback memories
2. Create unknowns-requirement.md (the critical new piece)
3. Create anthropic-overrides.md
4. Slim down CLAUDE.md to session start protocol + pointer to rules
5. Test in a new session — verify rules load, verify path-scoping works

### Phase 2: Build verification hooks (~1 hour)
1. read-only-gate.sh — PreToolUse hook that blocks writes during discovery
2. unknowns-check.js — PreToolUse hook that reminds about assumptions before first edit
3. Wire both into settings.json
4. Test each hook manually

### Phase 3: Evaluate claude-mem (~30 min)
1. Install: `npx claude-mem install`
2. Run a test session — verify capture
3. Start new session — verify injection
4. Decide: keep, replace, or supplement

### Phase 4: Cross-machine deployment (~30 min)
1. .claude/rules/ synced via Syncthing
2. Hooks synced via Syncthing
3. LaunchAgents created on both machines
4. Verify identical behavior on Mac Mini and MacBook

### Phase 5: Test-driven workflow enforcement (~1 hour)
1. Create test templates for each MCP package
2. Add pre-publish test requirement to each package.json
3. Document the test-first workflow in rules/delegation.md
4. Test with a real feature addition (add a tool, write test first)

---

## Sources

- [Claude Code Memory Docs](https://code.claude.com/docs/en/memory)
- [How Claude Code Rules Work](https://joseparreogarcia.substack.com/p/how-claude-code-rules-actually-work)
- [Claude-Mem Plugin (46K stars)](https://github.com/thedotmack/claude-mem)
- [Recursive Self-Improvement with Claude Code](https://medium.com/@davidroliver/recursive-self-improvement-building-a-self-improving-agent-with-claude-code-d2d2ae941282)
- [singularity-claude: Self-Evolving Skills](https://github.com/Shmayro/singularity-claude)
- [6 Best AI Agent Memory Frameworks 2026](https://machinelearningmastery.com/the-6-best-ai-agent-memory-frameworks-you-should-try-in-2026/)
- [Claude Code Hooks: All 12 Events](https://www.pixelmojo.io/blogs/claude-code-hooks-production-quality-ci-cd-patterns)
- [Building Persistent AI Agent Memory](https://dev.to/iniyarajan86/building-persistent-ai-agent-memory-systems-that-actually-work-463o)
- [Architecture of Memory Systems in AI Agents](https://www.analyticsvidhya.com/blog/2026/04/memory-systems-in-ai-agents/)
- User's own analysis of CLI self-modification mechanics and James 1:19 methodology
