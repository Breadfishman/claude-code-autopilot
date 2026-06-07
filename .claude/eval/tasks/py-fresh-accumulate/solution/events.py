def add_event(name, log=None):
    if log is None:
        log = []
    log.append(name)
    return log
