from paginate import paginate

data = list(range(1, 11))  # 1..10
assert paginate(data, 1, 3) == [1, 2, 3], paginate(data, 1, 3)
assert paginate(data, 2, 3) == [4, 5, 6], paginate(data, 2, 3)
assert paginate(data, 4, 3) == [10], paginate(data, 4, 3)
assert paginate(data, 5, 3) == [], paginate(data, 5, 3)

print("OK")
