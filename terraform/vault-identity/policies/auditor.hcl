# Auditors may see which doors exist (metadata), never what is behind them.
path "doors/metadata/*" {
  capabilities = ["list", "read"]
}
