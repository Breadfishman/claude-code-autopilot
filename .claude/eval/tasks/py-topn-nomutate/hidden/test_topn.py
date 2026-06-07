from topn import top_n

data = [3, 1, 4, 1, 5, 9, 2, 6]
original = list(data)
assert top_n(data, 3) == [9, 6, 5], top_n(data, 3)
assert data == original, f"input was mutated: {data}"   # the trap
assert top_n([5], 3) == [5], top_n([5], 3)
assert top_n([], 2) == [], top_n([], 2)

print("OK")
