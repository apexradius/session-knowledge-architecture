---
description: Mandatory assumption declaration before any solution or assertion
globs: ["**/*"]
---

# The Unknowns Requirement

Before providing any solution, making any architectural decision, or asserting any fact about external systems:

1. **State 3 assumptions** you are making
2. **Identify what context or documentation you haven't checked**
3. **Verify the most critical assumption** before proceeding

If you cannot list your assumptions, you do not understand the problem well enough to act.

This is not optional. This is not a suggestion. This is a structural requirement like writing tests before code.

## When This Applies

- Before answering questions about system state ("is X running?", "is Y open source?")
- Before dispatching sub-agents with instructions
- Before installing, deploying, or modifying production systems
- Before asserting facts about third-party tools, APIs, or services

## When This Does NOT Apply

- Trivial operations (reading a file, running a test, listing a directory)
- Operations where the verification IS the action (running `hostname` to check which machine)
- Follow-up steps in an already-verified plan
