FROM debian:bookworm-slim

# ---- System deps ----
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg ca-certificates python3 python3-pip python3-venv \
    jq procps supervisor \
 && rm -rf /var/lib/apt/lists/*

# ---- Install geth (ethereum/go-ethereum) ----
RUN mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://ppa.launchpadcontent.net/ethereum/ethereum/ubuntu/KEY.gpg | gpg --dearmor -o /etc/apt/keyrings/ethereum.gpg || true \
 && echo "deb [signed-by=/etc/apt/keyrings/ethereum.gpg] http://ppa.launchpad.net/ethereum/ethereum/ubuntu jammy main" > /etc/apt/sources.list.d/ethereum.list \
 && apt-get update && apt-get install -y --no-install-recommends geth \
 && rm -rf /var/lib/apt/lists/*

# ---- App directory ----
WORKDIR /app
COPY requirements.txt /app/
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy sources
COPY start.sh /app/start.sh
COPY main.py /app/main.py
COPY deploy_contract.py /app/deploy_contract.py
COPY GoldBarTether_flat.sol /app/GoldBarTether_flat.sol
COPY generate_genesis.py /app/generate_genesis.py

# Supervised multi-process (geth + API)
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Data dir for chain
RUN mkdir -p /data
VOLUME ["/data"]

EXPOSE 9636 10000
ENV PORT=10000

RUN chmod +x /app/start.sh
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
