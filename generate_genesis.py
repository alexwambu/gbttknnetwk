import json, os

CHAIN_ID = int(os.getenv("CHAIN_ID", "999"))
SIGNER = os.getenv("SIGNER_ADDRESS")  # 0x… (same as deployer/coinbase)
if not SIGNER or not SIGNER.startswith("0x") or len(SIGNER) != 42:
    raise SystemExit("SIGNER_ADDRESS env var must be a 20-byte hex address (0x…)")

# Clique extraData = 32 bytes vanity + signer list (20 bytes each) + 65 bytes seal
vanity = "0x" + "00"*32
signer_no0x = SIGNER[2:]
signer_padded = signer_no0x.lower()
seal = "00"*65
extraData = vanity + signer_padded + seal

genesis = {
  "config": {
    "chainId": CHAIN_ID,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0,
    "clique": { "period": 2, "epoch": 30000 }
  },
  "difficulty": "0x1",
  "gasLimit": "0x2FEFD800",          # ~ 805,306,368
  "baseFeePerGas": "0x3B9ACA00",      # 1 gwei
  "alloc": {
    SIGNER: { "balance": "0x52B7D2DCC80CD2E4000000" }  # ~1e24 wei for gas (1,000,000 ETH)
  },
  "extraData": extraData,
  "timestamp": "0x0",
  "nonce": "0x0",
  "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "coinbase": "0x0000000000000000000000000000000000000000",
  "number": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000"
}

with open("genesis.json", "w") as f:
    json.dump(genesis, f, indent=2)

print("Wrote genesis.json with signer", SIGNER, "chainId", CHAIN_ID)
