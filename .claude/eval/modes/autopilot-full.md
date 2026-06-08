# Mode: autopilot-full (pre-tiering baseline)

Use the kit's full staged pipeline on EVERY task regardless of size: triage →
plan → implement → self-verify → review → close. Verification is mandatory —
build/run the relevant checks and do not declare the task done until they pass.
Run a dedicated review pass and a dedicated closing pass. On failure, triage and
apply the smallest fix, then re-verify.

(This is the old always-full behaviour, kept as an A/B baseline against the
tiered `autopilot` mode.)
