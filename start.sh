#!/usr/bin/env bash
set -euo pipefail

DATADIR=/data
PWFILE=/app/password.txt

# Env we expect:
# PRIVATE_KEY (0x…)
# SIGNER_ADDRESS (0x…)
# ACCOUNT_PASSWORD (string)
# CHAIN_ID (e.g., 999)

if [ ! -f "$PWFILE" ]; then
  echo "${ACCOUNT_PASSWORD:-password123}" > "$PWFILE"
fi

# First boot: create genesis & init chain
if [ ! -d "$DATADIR/geth" ]; then
  echo ">> Generating genesis.json"
  python3 /app/generate_genesis.py
  echo ">> Initializing geth datadir"
  geth --datadir "$DATADIR" init /app/genesis.json
fi

# Import key once (if not in keystore)
if [ -z "$(ls -A $DATADIR/keystore 2>/dev/null || true)" ]; then
  echo ">> Importing signer key"
  echo "${PRIVATE_KEY:?private key required}" | sed 's/^0x//' > /app/pk.txt
  geth account import --datadir "$DATADIR" --password "$PWFILE" /app/pk.txt
  rm -f /app/pk.txt
fi

# Start geth (http rpc @ 9636), mine as signer
echo ">> Starting geth node"
exec geth \
  --datadir "$DATADIR" \
  --syncmode full \
  --http --http.addr 0.0.0.0 --http.port 9636 \
  --http.corsdomain "*" --http.api eth,net,web3,txpool,debug,engine \
  --ws --ws.addr 0.0.0.0 --ws.port 9646 --ws.origins "*" --ws.api eth,net,web3 \
  --networkid "${CHAIN_ID:-999}" \
  --allow-insecure-unlock \
  --unlock "${SIGNER_ADDRESS:?missing signer}" \
  --password "$PWFILE" \
  --mine --miner.etherbase "${SIGNER_ADDRESS}" \
  --miner.gasprice 1000000000 \
  --ipcdisable
