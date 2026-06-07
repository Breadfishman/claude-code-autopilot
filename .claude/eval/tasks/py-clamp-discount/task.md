Fix `apply_discount(price, pct)` in `discount.py`.

A `pct` percent discount reduces `price` by that percentage:
`apply_discount(100, 20)` -> `80.0`.

Requirements (handle all of these):
- A discount of `0` leaves the price unchanged.
- `pct` may exceed 100. A discount must never produce a negative price —
  clamp the result at `0.0`.
- Return a float.
