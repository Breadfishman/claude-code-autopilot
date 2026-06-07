from groupsum import sum_by

rows = [
    {"seg": "a", "amt": 10},
    {"seg": "b", "amt": 5},
    {"seg": "a", "amt": 7},
]
assert sum_by(rows, "seg", "amt") == {"a": 17, "b": 5}, sum_by(rows, "seg", "amt")
assert sum_by([], "seg", "amt") == {}, sum_by([], "seg", "amt")

print("OK")
