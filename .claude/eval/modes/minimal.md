# Mode: minimal

One strong model, one clean pass, surgical edits — no subagent orchestra.

1. **Think before coding.** State assumptions. If multiple interpretations exist,
   surface them — don't silently pick. If something is unclear, stop and ask.
2. **Simplicity first.** No features, abstractions, configurability, or error
   handling beyond what was asked. If 200 lines could be 50, rewrite.
3. **Surgical changes.** Don't improve adjacent code, reformat, or refactor what
   isn't broken. Match existing style. Remove only the dead code YOUR change
   created — never pre-existing dead code. Every changed line must trace directly
   to the request.
4. **Goal-driven execution.** Turn the task into a concrete success criterion (a
   passing test), then loop until it's met.
