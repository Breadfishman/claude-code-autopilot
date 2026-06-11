---
name: model-router
description: Complexity-based model escalation for OpenClaw agents. Triage tasks into Simple/Medium/Complex and route to the appropriate model (Sonnet vs Opus).
---

# Model Router — Complexity-Based Escalation

Use this skill at the start of every coding task to decide whether to work directly or escalate to a more capable model.

## Triage Template

Before starting work, classify the task:

```
## Triage: <task title>
- Scope: <1-2 sentence summary>
- Files: <estimated count and which modules>
- Pattern: Existing / New / Architectural change
- Risk: Low / Medium / High (regression potential)
- Classification: Simple / Medium / Complex
```

## Classification Rules

### Simple (Stay on current model — typically Sonnet)

Work directly. No escalation needed.

- 1-2 files affected
- Follows an existing pattern in the codebase
- Low regression risk
- Examples: bug fix, config change, docs update, test addition, styling tweak

### Medium (Stay on Sonnet, use full autopilot-workflow)

Work directly with the full `autopilot-workflow` pipeline. Extra care on verification.

- 3-4 files affected
- Bounded scope (clear start and end) — several small deliverables are still Medium when there is no architectural change (deliverable count alone is not complexity; see `.claude/eval/FINDINGS.md`)
- Moderate regression risk
- Examples: new endpoint with tests, refactor within one module, feature following existing patterns

### Complex (Escalate to Opus)

Delegate to the Claude autopilot-opus pipeline for higher reasoning capability.

- 4+ files across different modules/packages
- Requires architectural decisions (new patterns, service boundaries, a new subsystem/abstraction)
- High regression risk (core business logic, auth, data layer)
- Benefits from specialist review (security, performance, type system)

**How to escalate in OpenClaw:**

```
Use the autopilot-opus subagent (Task tool with subagent_type=autopilot-opus) for this task: <description>
```

If the workspace has a Claude Code installation, this invokes the `autopilot-opus` agent via the Claude CLI bridge.

## Decision Matrix

| Signal | Simple | Medium | Complex |
|--------|--------|--------|---------|
| Files changed | 1-2 | 3-4 | 4+ |
| Modules touched | 1 | 1-2 | 3+ |
| Pattern | Existing | Existing | New/Architectural |
| Deliverables | 1 | several (bounded) | any, if architectural |
| Regression risk | Low | Medium | High |
| **Action** | Direct | Direct + full pipeline | Escalate to Opus |

## Common Mistakes

- **Over-escalating:** A 3-file change following an existing pattern is Medium, not Complex. Don't escalate just because the task sounds hard.
- **Under-escalating:** A "simple" task that touches auth + database + API + tests is Complex. Count the distinct modules, not just the files.
- **Skipping triage:** Always write the triage template, even for tasks that seem obvious. It takes 10 seconds and prevents wrong-model execution.

## Cost Awareness

- Opus costs ~5x more tokens than Sonnet
- Most tasks (70-80%) should stay on Sonnet
- Escalation should be the exception, not the default
- When in doubt, start on Sonnet — you can always escalate mid-task if complexity is higher than expected
