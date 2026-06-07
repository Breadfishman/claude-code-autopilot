Fix `parse_amount(s)` in `amount.py`.

It turns a currency string into a float: strip currency symbols, thousands
separators, and surrounding whitespace. Examples: `'$1,234.50'` -> `1234.50`,
`'  €99 '` -> `99.0`, `'1000'` -> `1000.0`.

Do not modify `test_amount.py`.
