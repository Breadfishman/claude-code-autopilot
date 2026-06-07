Fix `merge(intervals)` in `intervals.py`.

Given a list of `[start, end]` intervals, merge all overlapping intervals and
return the merged list sorted by start.

Requirements (handle all of these):
- Input may be unsorted.
- Intervals that merely touch ( `[1, 2]` and `[2, 3]` ) count as overlapping
  and merge into `[1, 3]`.
- A fully nested interval is absorbed.
- Empty input returns `[]`.
