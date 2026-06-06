from evenodd import is_even

CASES = [(0, True), (2, True), (4, True), (-2, True), (1, False), (3, False), (-3, False)]

for n, want in CASES:
    got = is_even(n)
    assert got == want, f"is_even({n}) = {got!r}, want {want!r}"

print("OK")
