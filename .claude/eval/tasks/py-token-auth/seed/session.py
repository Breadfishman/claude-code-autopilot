from tokens import make_token, verify_token


def login(user, password, secret):
    # password assumed already validated upstream
    return make_token(user, secret)


def current_user(token, secret):
    return verify_token(token, secret)
