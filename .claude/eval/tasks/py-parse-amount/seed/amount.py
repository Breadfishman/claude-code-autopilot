def parse_amount(s):
    # BUG: only strips '$' — commas and other symbols make float() raise.
    return float(s.replace("$", "").strip())
