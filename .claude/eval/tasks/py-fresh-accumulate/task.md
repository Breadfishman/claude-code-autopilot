Fix `add_event(name, log=None)` in `events.py`.

It appends `name` to a list of events and returns the list.

Requirements:
- When `log` is omitted, each call starts from a **fresh empty list** — calls
  are independent of one another.
- When a `log` is passed in, append to that list and return it.
