Fix `paginate(items, page, size)` in `paginate.py`.

Pages are **1-indexed**: page 1 returns the first `size` items, page 2 the next
`size`, and so on. An out-of-range page returns an empty list.

Do not modify `test_paginate.py`.
