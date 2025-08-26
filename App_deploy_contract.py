import json, os, time
from web3 import Web3
from solcx import install_solc, compile_source

RPC_LOCAL = os.getenv("NODE_RPC_URL", "http://127.0.0.1:9636")
PRIVATE_KEY = os.getenv("PRIVATE_KEY")
SIGNER_ADDRESS = os.getenv("SIGNER_ADDRESS")
CHAIN_ID = int(os.getenv("CHAIN_ID", "999"))

PRICE_FEED = os.getenv("PRICE_FEED", "0x0000000000000000000000000000000000000000")
FEE_RECEIVER = os.getenv("FEE_RECEIVER", "0xF7F965b65E735Fb1C22266BdcE7A23CF5026AF1E")

OUTFILE = "deployed.json"

def wait_rpc():
    w3 = Web3(Web3.HTTPProvider(RPC_LOCAL))
    for _ in range(120):
        try:
            if w3.is_connected():
                w3.eth_chain_id
                return w3
        except Exception:
            pass
        time.sleep(1)
    raise RuntimeError("RPC not ready")

def maybe_deploy():
    if os.path.exists(OUTFILE):
        with open(OUTFILE) as f:
            j = json.load(f)
            if j.get("address"):
                return j["address"]
    w3 = wait_rpc()
    acct = w3.eth.account.from_key(PRIVATE_KEY)
    assert acct.address.lower() == SIGNER_ADDRESS.lower(), "PRIVATE_KEY != SIGNER_ADDRESS"

    install_solc("0.8.21")
    with open("GoldBarTether_flat.sol") as f:
        src = f.read()

    compiled = compile_source(src, output_values=["abi","bin"], solc_version="0.8.21")
    (_, iface) = next(iter(compiled.items()))
    abi, bytecode = iface["abi"], iface["bin"]

    Contract = w3.eth.contract(abi=abi, bytecode=bytecode)
    tx = Contract.constructor(PRICE_FEED, SIGNER_ADDRESS, FEE_RECEIVER).build_transaction({
        "from": acct.address,
        "nonce": w3.eth.get_transaction_count(acct.address),
        "gas": 6_500_000,
        "gasPrice": w3.to_wei("1", "gwei"),
        "chainId": CHAIN_ID
    })
    signed = w3.eth.account.sign_transaction(tx, PRIVATE_KEY)
    txh = w3.eth.send_raw_transaction(signed.rawTransaction)
    rcpt = w3.eth.wait_for_transaction_receipt(txh)
    addr = rcpt.contractAddress
    with open(OUTFILE,"w") as f:
        json.dump({"address": addr, "tx": txh.hex()}, f, indent=2)
    return addr

if __name__ == "__main__":
    print("Deploying GBT if needed…")
    addr = maybe_deploy()
    print("Deployed at:", addr)
