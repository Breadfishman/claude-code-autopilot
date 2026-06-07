def sum_by(rows, key, value):
    out = {}
    for r in rows:
        out[r[key]] = out.get(r[key], 0) + r[value]
    return out
