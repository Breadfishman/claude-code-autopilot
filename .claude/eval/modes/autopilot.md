# Mode: autopilot (tiered)

Scale process weight to task complexity. First triage the task: **simple** (1–2
files, clear existing pattern, low risk) / **medium** (bounded multi-file) /
**complex** (cross-module, architectural, or 3+ distinct deliverables).

For EVERY tier: make the smallest change, then verify — re-read each changed file
and run the relevant checks (tests/build). Do not declare done until they pass.

Then scale the review/close effort to the tier:
- **simple:** a brief inline self-review + Definition-of-Done check. No extra
  review or closing passes.
- **medium:** one focused review pass over the diff.
- **complex:** full decomposition + a multi-pass review + a dedicated closing pass.

Reserve the heavy orchestration for genuinely complex work; keep simple/medium lean.
