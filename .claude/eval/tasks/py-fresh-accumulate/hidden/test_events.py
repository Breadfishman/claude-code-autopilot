from events import add_event

assert add_event("a") == ["a"], "first omitted-log call"
assert add_event("b") == ["b"], "calls must be independent when log is omitted"

existing = ["x"]
assert add_event("y", existing) == ["x", "y"], "explicit log is appended to"
assert existing == ["x", "y"], "explicit log is mutated in place"

print("OK")
