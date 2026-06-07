Fix `sum_by(rows, key, value)` in `groupsum.py`.

Given a list of dicts, return a dict mapping each distinct `row[key]` to the
**sum** of `row[value]` across all rows with that key. Empty input -> `{}`.

Do not modify `test_groupsum.py`.
