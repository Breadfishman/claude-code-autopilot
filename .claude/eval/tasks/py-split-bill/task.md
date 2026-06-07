Fix `split_bill(total_cents, people)` in `split.py`.

Split `total_cents` (a non-negative integer) among `people` (a positive
integer) as evenly as possible.

Requirements:
- Return a list of `people` integer cent amounts whose **sum is exactly
  `total_cents`** (no cents lost).
- Distribute any remainder one extra cent at a time to the earliest people,
  so the amounts come out in non-increasing order.
