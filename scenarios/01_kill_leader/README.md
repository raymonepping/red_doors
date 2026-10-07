# 01 — Kill the active Vault pod

`./scenarios/01_kill_leader/run.sh` (≈ 1 min)

**Say:** "Vault runs as three nodes. I am going to kill the one in charge — mid-demo."
**Click:** open **Cluster** in one window and the **Corridor** in another; run the script (it knocks on door 1 every second).
**They see:** leadership moves to another node within seconds, door 1 keeps opening (≈ 1 knock lost in the switchover), and the killed pod comes back unsealed by itself.
