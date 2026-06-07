import hashlib


def make_token(user, secret):
    sig = hashlib.sha256((user + secret).encode()).hexdigest()[:16]
    return f"{user}.{sig}"


def verify_token(token, secret):
    if "." not in token:
        return None
    user, sig = token.split(".", 1)
    expected = hashlib.sha256((user + secret).encode()).hexdigest()[:16]
    if sig == expected:
        return user
    return None
