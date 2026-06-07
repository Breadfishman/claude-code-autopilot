def paginate(items, page, size):
    # BUG: pages are 1-indexed, but this treats `page` as 0-indexed.
    start = page * size
    return items[start:start + size]
