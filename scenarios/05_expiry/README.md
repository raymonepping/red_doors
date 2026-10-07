# 05 — Short-lived authority really ends

`./scenarios/05_expiry/run.sh` (≈ 30 s; `--long` adds door 8, ≈ 11 min)

**Say:** "Everything we handed out had a clock on it. Let us wait for the clocks."
**Click:** run the script; optionally show door 3/5/4 detail pages.
**They see:** an expired wrapping token (door 3), an expired Treasury certificate (door 5) and a revoked database login (door 4) are each refused — by Vault or PostgreSQL, not by the UI. With `--long`, an unapproved launch-code request expires.
