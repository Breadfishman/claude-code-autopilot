def add_event(name, log=[]):
    # BUG: the default list is created once and shared across every call,
    # so omitted-log calls accumulate into the same list.
    log.append(name)
    return log
