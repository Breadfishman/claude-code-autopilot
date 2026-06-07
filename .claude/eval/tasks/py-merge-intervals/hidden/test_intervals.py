from intervals import merge

assert merge([]) == []
assert merge([[1, 3], [2, 6], [8, 10]]) == [[1, 6], [8, 10]]
assert merge([[8, 10], [1, 3], [2, 6]]) == [[1, 6], [8, 10]]   # unsorted input
assert merge([[1, 2], [2, 3]]) == [[1, 3]]                     # touching
assert merge([[1, 5], [2, 3]]) == [[1, 5]]                     # nested

print("OK")
