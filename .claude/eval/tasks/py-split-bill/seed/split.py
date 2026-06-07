def split_bill(total_cents, people):
    # BUG: integer division drops the remainder, so the parts don't sum to
    # total_cents (looks like an even split, but loses cents).
    share = total_cents // people
    return [share] * people
