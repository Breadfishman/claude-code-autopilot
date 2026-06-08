from models import make_item
from pricing import line_total, order_subtotal, apply_tax
from orders import order_total

# 1. line_total: discount + clamp
assert line_total(make_item("a", 2, 10.0)) == 20.0, line_total(make_item("a", 2, 10.0))
assert line_total(make_item("b", 2, 10.0, 50)) == 10.0, line_total(make_item("b", 2, 10.0, 50))
assert line_total(make_item("c", 1, 10.0, 150)) == 0.0, line_total(make_item("c", 1, 10.0, 150))

# 2. subtotal (+ empty)
order = {"items": [make_item("a", 2, 10.0), make_item("b", 1, 5.0, 20)]}  # 20 + 4 = 24
assert order_subtotal(order) == 24.0, order_subtotal(order)
assert order_subtotal({"items": []}) == 0.0, order_subtotal({"items": []})

# 3. tax, rounded to cents
assert apply_tax(24.0, 0.0825) == 25.98, apply_tax(24.0, 0.0825)

# 4. order_total + negative-qty validation
assert order_total(order, 0.10) == 26.40, order_total(order, 0.10)
try:
    order_total({"items": [make_item("x", -1, 5.0)]}, 0.10)
    raise AssertionError("expected ValueError on negative qty")
except ValueError:
    pass

print("OK")
