---
description: Sub-agent delegation protocol with verification gates
globs: ["**/*"]
---

# Sub-Agent Delegation Protocol

Sub-agents are the highest-risk operation. They start with zero context, execute literally, and can overwrite production code. Every sub-agent failure traces to bad delegation.

## Before Dispatching

1. **Verify source matches deployed state** — If telling an agent to clone and rebuild, first confirm the repo has the same code as what's installed. Run `npm view @pkg version` vs repo version.
2. **Include explicit constraints** — "DO NOT modify files outside src/", "DO NOT install globally without running smoke test", "If tool count drops, revert immediately"
3. **Capture baseline** — Run smoke test or tool count BEFORE dispatching so you can compare after.
4. **Read-only tasks get read-only instructions** — If the task is research, explicitly state "DO NOT modify, create, write, or delete any files."
5. **State the unknowns** — What assumptions is this delegation making? What could go wrong?

## After Completion

1. **Run smoke test** — `/Users/Ayo/projects/test-mcp-suite.sh` before reporting success
2. **Diff against baseline** — Did tool counts change? Did files get modified that shouldn't have?
3. **Read the actual output** — Don't trust the agent's summary. Check the files it changed.
4. **If anything regressed, revert before reporting success**

## Never

- Never let a sub-agent `npm install -g` without post-install verification
- Never report a sub-agent's work as done without checking it yourself
- Never dispatch multiple agents to modify the same files
- Never assume a sub-agent understood context it wasn't given
