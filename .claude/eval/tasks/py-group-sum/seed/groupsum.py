def sum_by(rows, key, value):
    out = {}
    for r in rows:
        # BUG: overwrites the running total instead of accumulating it.
        out[r[key]] = r[value]
    return out
