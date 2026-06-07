Fix token verification across `tokens.py` and `session.py`.

`tokens.py`:
- `make_token(user, secret)` creates a token string for `user`.
- `verify_token(token, secret)` must return the `user` only if the token was
  created with the SAME `secret`; otherwise return `None`. A tampered or
  malformed token returns `None`.

`session.py` builds on these:
- `login(user, password, secret)` returns a token (assume the password is
  already valid).
- `current_user(token, secret)` returns the logged-in user or `None`.

The bug: verification currently trusts any token regardless of secret. Fix it
**without breaking the `login` -> `current_user` round trip.**
