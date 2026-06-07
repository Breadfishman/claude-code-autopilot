from amount import parse_amount

assert parse_amount("$1,234.50") == 1234.50, parse_amount("$1,234.50")
assert parse_amount("  €99 ") == 99.0, parse_amount("  €99 ")
assert parse_amount("1000") == 1000.0, parse_amount("1000")

print("OK")
