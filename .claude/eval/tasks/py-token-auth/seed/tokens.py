import hashlib


def make_token(user, secret):
    sig = hashlib.sha256((user + secret).encode()).hexdigest()[:16]
    return f"{user}.{sig}"


def verify_token(token, secret):
    # BUG: returns the user without checking the signature against `secret`.
    if "." not in token:
        return None
    user, _sig = token.split(".", 1)
    return user
