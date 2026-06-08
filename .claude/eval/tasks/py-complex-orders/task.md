Implement order pricing across `models.py`, `pricing.py`, and `orders.py`. All
four pieces must work together:

1. `line_total(item)`: `qty` × `unit_price`, then apply `item["discount_pct"]`
   percent off. A discount never makes a line negative (clamp at `0.0`). Returns a float.
2. `order_subtotal(order)`: the sum of `line_total` over `order["items"]`. An
   empty order is `0.0`.
3. `apply_tax(subtotal, rate)`: `subtotal` plus tax at `rate` (e.g. `0.1` = 10%),
   **rounded to 2 decimal places**.
4. `order_total(order, tax_rate)`: the subtotal with tax applied. Before computing,
   validate every item — a negative `qty` raises `ValueError`.
