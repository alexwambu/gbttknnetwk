import os, json, threading, time
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse
from web3 import Web3

# Secrets / Settings
PASSWORD1 = os.getenv("PASSWORD1", "show-rpc-and-token")
PASSWORD2 = os.getenv("PASSWORD2", "show-network-check")
CHAIN_ID = int(os.getenv("CHAIN_ID", "999"))
CURRENCY_SYMBOL = os.getenv("CURRENCY_SYMBOL", "GBT")

RENDER_URL = os.getenv("RENDER_EXTERNAL_URL", "")  # Render injects this; fallback to service URL if known
RPC_RENDER = os.getenv("PUBLIC_RPC_URL", "")       # you can set a public https URL here

# Local RPC (container -> geth)
LOCAL_RPC = "http://127.0.0.1:9636"

DEPLOYED_FILE = "deployed.json"

app = FastAPI()
w3 = Web3(Web3.HTTPProvider(LOCAL_RPC))

def read_address():
    if os.path.exists(DEPLOYED_FILE):
        with open(DEPLOYED_FILE) as f:
            return json.load(f).get("address")
    return None

# Kick a background deploy (run once) after boot
def background_deploy():
    # give geth time to start
    for _ in range(10):
        try:
            if w3.is_connected():
                break
        except Exception:
            pass
        time.sleep(1)
    os.system("python3 /app/deploy_contract.py")

threading.Thread(target=background_deploy, daemon=True).start()

@app.get("/", response_class=HTMLResponse)
def home():
    addr = read_address() or "0x0000000000000000000000000000000000000000"
    # Static display — no refresh
    html = f"""
    <!doctype html>
    <html><head><meta charset="utf-8" />
      <title>GBTNetwork • Contract Address</title>
      <style>
        body {{ background:#0e0e0e; color:#f8d46b; font-family:ui-sans-serif,system-ui; display:flex; align-items:center; justify-content:center; height:100vh; margin:0; }}
        .card {{ background:#151515; border:1px solid #6b5b2e; padding:24px 28px; border-radius:14px; box-shadow:0 4px 30px rgba(0,0,0,.6); text-align:center; max-width:840px; }}
        h1 {{ margin:0 0 12px; font-size:22px; }}
        code {{ font-size:16px; background:#1d1d1d; padding:8px 12px; border-radius:10px; display:inline-block; }}
        button {{ margin-top:12px; padding:10px 14px; border-radius:10px; border:1px solid #6b5b2e; background:#1a1a1a; color:#f8d46b; cursor:pointer; }}
      </style>
    </head><body>
      <div class="card">
        <h1>GoldBarTether Contract Address</h1>
        <code id="addr">{addr}</code><br/>
        <button onclick="navigator.clipboard.writeText(document.getElementById('addr').innerText)">Copy</button>
        <div style="margin-top:16px; color:#bfae6a">Chain ID: {CHAIN_ID} • Currency: {CURRENCY_SYMBOL}</div>
      </div>
    </body></html>
    """
    return HTMLResponse(html)

@app.get("/api/info")
def info(pw: str = Query(..., alias="password")):
    if pw != PASSWORD1:
        raise HTTPException(status_code=401, detail="unauthorized")
    addr = read_address()
    rpc_urls = [
        "https://localhost:9636",
        "https://GBTNetwork:9636",
        "https://GBTNetwork",
    ]
    # Prefer render public URL if provided
    if RPC_RENDER:
        rpc_urls.append(RPC_RENDER)
    elif RENDER_URL:
        rpc_urls.append(RENDER_URL)
    return {
        "chainId": CHAIN_ID,
        "currency": CURRENCY_SYMBOL,
        "rpc": rpc_urls,
        "token_contract": addr
    }

@app.get("/api/network-check")
def network_check(pw2: str = Query(..., alias="password")):
    if pw2 != PASSWORD2:
        raise HTTPException(status_code=401, detail="unauthorized")
    if not w3.is_connected():
        raise HTTPException(status_code=503, detail="rpc not ready")
    try:
        coinbase = w3.eth.coinbase
    except Exception:
        coinbase = None
    return {
        "chainId": CHAIN_ID,
        "networkCheckAddress": coinbase,
        "latestBlock": hex(w3.eth.block_number)
    }
