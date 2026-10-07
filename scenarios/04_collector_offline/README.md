# 04 — Audit collector offline

`./scenarios/04_collector_offline/run.sh` (≈ 1 min)

**Say:** "Audit must never become the reason Vault stops. Watch what happens when our collector dies."
**Click:** **Audit** page; run the script.
**They see:** a "collector offline" banner while Vault keeps answering (its stdout audit device still records everything); when the API returns, Vault reconnects its socket device by itself and entries flow again.
