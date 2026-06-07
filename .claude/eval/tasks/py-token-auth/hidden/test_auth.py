from tokens import make_token, verify_token
from session import login, current_user

t = make_token("alice", "s3cret")
assert verify_token(t, "s3cret") == "alice"            # correct secret
assert verify_token(t, "wrong") is None                # wrong secret
assert verify_token("alice.deadbeef", "s3cret") is None  # tampered signature
assert verify_token("garbage", "s3cret") is None       # malformed

# the login -> current_user round trip must still work
tok = login("bob", "pw", "k")
assert current_user(tok, "k") == "bob"
assert current_user(tok, "other") is None

print("OK")
