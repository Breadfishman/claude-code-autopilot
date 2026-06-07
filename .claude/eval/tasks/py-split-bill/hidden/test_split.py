from split import split_bill

assert sum(split_bill(100, 3)) == 100, split_bill(100, 3)      # invariant: no cents lost
assert split_bill(100, 3) == [34, 33, 33], split_bill(100, 3)
assert split_bill(10, 5) == [2, 2, 2, 2, 2], split_bill(10, 5)
assert sum(split_bill(7, 4)) == 7, split_bill(7, 4)
assert split_bill(7, 4) == [2, 2, 2, 1], split_bill(7, 4)
assert split_bill(0, 3) == [0, 0, 0], split_bill(0, 3)

print("OK")
