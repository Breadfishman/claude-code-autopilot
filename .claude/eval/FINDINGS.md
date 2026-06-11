# Eval Findings — Does the multi-agent pipeline beat a lean prompt? (June 2026)

*Recorded on branch `modernize/2026-tooling-refresh`. Reproduce with `.claude/eval/`.*

## Question

Claude Code Autopilot wraps every substantive task in a multi-agent pipeline
(triage → implement → `review-chain` → `closer`). On **Opus 4.8**, does that
orchestration actually produce better results than a lean, single-pass prompt —
or is it overhead the platform's strong models no longer need?

## Method

A mode×task matrix runner (`run-eval.sh`). Each cell runs in an isolated
workdir seeded from a task fixture, with the mode's `CLAUDE.md` overlay applied,
then an objective **hidden** test (`verify.sh`) decides pass/fail. Tokens and
wall-clock are recorded.

- **Modes** (the treatment): `autopilot` (full staged pipeline), `minimal`
  (Karpathy surgical: one clean pass, no orchestra), `native` (lean,
  goal-first).
- **Runner:** real `claude -p` (2.1.168), headless, in the isolated workdir.
- **Fidelity:** `--agents` symlinks the kit's real `.claude/agents/` into each
  workdir so the `autopilot` mode genuinely spawns `review-chain`/`closer`.
- **Variance:** `--reps` repeats each cell.
- **Discrimination:** harder tasks give the agent only a prose spec + broken
  seed; the comprehensive test is **hidden** (never in the workdir). Trap tasks
  were validated to actually catch a plausible-but-wrong fix.

## Results — 87 live sessions, three escalating difficulty tiers

All tiers: **100% pass in every mode.** No correctness difference anywhere.
The only consistent signal is cost (`minimal` always cheapest):

| Tier | Tasks (× modes × reps = cells) | Pass | Tokens (min / nat / auto) | Sec (min / nat / auto) |
|---|---|---|---|---|
| **1 — easy/moderate** | 5 one-function bugs (×3×1 = 15) | 15/15 all modes | 2992 / 3275 / 3058 | 18.8 / 25.2 / 20.4 |
| **2 — hard** *(--agents)* | 3 hidden-test, multi-file, subtle edges (×3×3 = 27) | 27/27 all modes | 3440 / 3691 / **3848** | 23.4 / 24.4 / **27.0** |
| **3 — traps** *(--agents)* | 3 plausible-but-wrong, verification-bait (×3×5 = 45) | 45/45 all modes | 2948 / 3105 / **3329** | 16.7 / 19.7 / **20.8** |

Per-(task × mode) pass-rate in tiers 2 & 3 was **maximal in every cell** (3/3,
5/5) — including the input-mutation, sum-invariant, and shared-state traps
designed specifically to require verification.

**Key observation:** in the two tiers run with real agent fidelity (`--agents`),
`autopilot` is the **most expensive** mode (the orchestration cost is real and
was previously understated), while delivering **identical** correctness to the
lean `minimal` mode (~12–24% cheaper).

## Verdict

**Hypothesis — "the pipeline's mandatory verification catches bugs a lean pass
misses" — is rejected** for the tested task classes. Opus 4.8 catches even
deliberate traps on its own, in the lean mode. For ordinary coding tasks, the
multi-agent orchestration is **pure overhead**: same correctness, more cost.

## Honest boundary (not tested)

- **Large / ambiguous / long-horizon** tasks (where a model can lose the thread
  and decomposition/verification might help) can't be cleanly fixtured and were
  not tested. That is the one regime where the pipeline might still pay off — and
  it is exactly what the complexity-router escalates to `complex`/`opus`.
- The traps are **classic** gotcha patterns (well-represented in training). A
  truly novel trap might behave differently (though it's also less representative
  of real bugs).

## Decision

Make a **lean path the default** and **reserve the full pipeline for `complex`
work** (large/architectural/high-risk). Implemented in
`.claude/agents/autopilot.md`: the `simple` tier now does implement +
self-verify + lifecycle-verify and a brief inline review/close (skipping the
`review-chain` and `closer` subagents); `medium` gets a single
`surgical-reviewer` pass + an inline close; `complex` keeps the full pipeline
(via `autopilot-opus`). The
cheap, valuable checks (re-read changed files, build/test/confirm) stay for all
tiers.

## Validation of the tiered default (A/B)

After shipping the tier-gating, we A/B'd it directly — old always-full pipeline
(`autopilot-full`) vs the new tiered default (`autopilot`) vs `minimal`, on the 3
hard tasks × 3 reps, with real agents:

| Mode | Pass | Avg tokens | vs full | Avg sec |
|---|---|---|---|---|
| `autopilot-full` (old) | 9/9 | 4128 | — | 32.2 |
| **`autopilot` (tiered, new default)** | 9/9 | **3472** | **−16%** | 22.3 |
| `minimal` | 9/9 | 3369 | −18% | 26.7 |

**Result:** the tiered default is ~16% cheaper / ~31% faster than the old full
pipeline at **identical (100%) correctness**, capturing nearly all of the
full→minimal savings. The change does what it claims. *Still untested:* the
complex-escalation path — needs a genuinely `complex` task.

## Complex-tier probe — does it escalate? does the pipeline ever win?

A genuinely multi-module task (`py-complex-orders`: 3 files, 4 interacting
deliverables — discount+clamp, subtotal, tax-rounding, validation), full vs
tiered vs minimal × 5 reps, real agents:

| Mode | Pass | Avg tokens | Avg sec |
|---|---|---|---|
| `autopilot-full` | 5/5 | 6233 | 54.0 |
| `autopilot` (tiered) | 5/5 | 5009 | 57.4 |
| `minimal` | 5/5 | 5090 | 43.8 |

1. **No correctness crossover — again.** minimal solved it 5/5; the forced full
   pipeline cost +22% tokens for nothing. Across FOUR tiers (easy, hidden-test,
   traps, complex multi-module) the pipeline has never beaten lean on correctness.
2. **Escalation did not fire.** Tiered's cost (5009) sits at *minimal* (5090), not
   full (6233): the model judged this 4-function task `medium` and stayed lean —
   correctly (it passed). The "reserve the pipeline for complex" branch is
   un-exercised here.

**Honest limit of the method:** the regime where the pipeline might help (large /
ambiguous / architectural) is exactly the one that resists deterministic fixtures.
Every task we *can* fixture, the lean path wins. **Calibration note:** the model
correctly overrode `autopilot.md`'s literal "3+ deliverables → complex" rule (this
task has 4 and rightly stayed lean) — a future refinement could gate escalation on
architectural/regression risk rather than deliverable count.

## Reproduce / re-test (e.g. when a new model ships)

```bash
cd .claude/eval
bash run-eval.sh --runner claude --agents --reps 5 \
  --tasks "py-topn-nomutate py-split-bill py-fresh-accumulate" --out results/rerun.tsv
```
Deterministic plumbing check (no tokens): `bash test_eval.sh`.
