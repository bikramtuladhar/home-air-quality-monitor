#!/usr/bin/env bash
# Expose the Grafana wall publicly via a named Cloudflare Tunnel.
set -e
HOST="qai.bikramtuladhar.info.np"
NAME="pm25-wall"
CFDIR="$HOME/.cloudflared"

[ -f "$CFDIR/cert.pem" ] || { echo "ERROR: $CFDIR/cert.pem missing — run 'cloudflared tunnel login' first"; exit 1; }

echo ">>> tunnel"
if cloudflared tunnel list --output json 2>/dev/null | grep -q "\"name\":\"$NAME\""; then
  echo "tunnel '$NAME' already exists"
else
  cloudflared tunnel create "$NAME"
fi
UUID=$(cloudflared tunnel list --output json | python3 -c "import sys,json;print(next(t['id'] for t in json.load(sys.stdin) if t['name']=='$NAME'))")
echo "UUID=$UUID"

echo ">>> DNS route ($HOST)"
cloudflared tunnel route dns "$NAME" "$HOST" 2>&1 | grep -vi "already exists" || true

echo ">>> config"
cat > "$CFDIR/config.yml" <<EOF
tunnel: $UUID
credentials-file: $CFDIR/$UUID.json
ingress:
  - hostname: $HOST
    service: http://localhost:3000
  - service: http_status:404
EOF

echo ">>> boot service"
sudo tee /etc/systemd/system/cloudflared-pm25.service >/dev/null <<EOF
[Unit]
After=network.target
[Service]
User=$USER
ExecStart=/usr/bin/cloudflared tunnel --config $CFDIR/config.yml run
Restart=always
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared-pm25

echo ">>> grafana root_url"
sudo tee /etc/systemd/system/grafana-server.service.d/override.conf >/dev/null <<EOF
[Service]
Environment=GF_AUTH_ANONYMOUS_ENABLED=true
Environment=GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer
Environment=GF_SERVER_ROOT_URL=https://$HOST/
EOF
sudo systemctl daemon-reload && sudo systemctl restart grafana-server

echo ">>> done"
