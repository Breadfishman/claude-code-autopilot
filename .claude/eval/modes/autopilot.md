# Mode: autopilot

Use the kit's full staged pipeline: triage → plan → implement → self-verify →
review → close. Verification is mandatory — build/run the relevant checks and do
not declare the task done until they pass. On failure, triage and apply the
smallest fix, then re-verify.
