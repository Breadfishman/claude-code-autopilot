import re


def parse_amount(s):
    cleaned = re.sub(r"[^0-9.\-]", "", s)
    return float(cleaned)
