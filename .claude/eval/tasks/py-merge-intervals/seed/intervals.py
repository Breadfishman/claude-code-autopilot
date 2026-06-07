def merge(intervals):
    # BUG: assumes the input is already sorted, and only merges on strict
    # overlap (so it misses touching intervals like [1,2] and [2,3]).
    out = []
    for s, e in intervals:
        if out and s < out[-1][1]:
            out[-1][1] = max(out[-1][1], e)
        else:
            out.append([s, e])
    return out
