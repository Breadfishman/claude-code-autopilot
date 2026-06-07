def top_n(items, n):
    # BUG: sorts ascending (returns the smallest), and sorts the caller's
    # list in place (mutates the input).
    items.sort()
    return items[:n]
