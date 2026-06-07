from discount import apply_discount

assert apply_discount(100, 20) == 80.0, apply_discount(100, 20)
assert apply_discount(100, 0) == 100.0, apply_discount(100, 0)
assert apply_discount(100, 150) == 0.0, apply_discount(100, 150)   # clamp at 0
assert apply_discount(50, 100) == 0.0, apply_discount(50, 100)
assert isinstance(apply_discount(100, 20), float)

print("OK")
