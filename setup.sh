#!/usr/bin/env bash
# One-shot install: PMS5003 exporter + VictoriaMetrics + Grafana + swap.
# Run on the Pi as: sudo bash ~/setup.sh
# Staged files (pms5003_exporter.py, prometheus.yml) are expected in the
# invoking user's home dir; we resolve it even though we run under sudo.
set -euo pipefail
HOME_DIR=$(eval echo "~${SUDO_USER:-$USER}")
VM_VER=v1.106.1

echo ">>> [1/5] exporter deps + files"
apt-get update -qq
apt-get install -y python3-serial python3-prometheus-client
mkdir -p /opt/pms5003
cp "$HOME_DIR/pms5003_exporter.py" "$HOME_DIR/prometheus.yml" /opt/pms5003/

cat >/etc/systemd/system/pms5003.service <<'EOF'
[Unit]
After=multi-user.target
[Service]
ExecStart=/usr/bin/python3 /opt/pms5003/pms5003_exporter.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

echo ">>> [2/5] VictoriaMetrics"
A=$([ "$(uname -m)" = aarch64 ] && echo arm64 || echo arm)
cd /tmp
curl -sL "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/$VM_VER/victoria-metrics-linux-$A-$VM_VER.tar.gz" | tar xz
mv -f victoria-metrics-prod /usr/local/bin/
mkdir -p /var/lib/victoria-metrics

cat >/etc/systemd/system/victoriametrics.service <<'EOF'
[Unit]
After=network.target
[Service]
ExecStart=/usr/local/bin/victoria-metrics-prod \
  -storageDataPath=/var/lib/victoria-metrics \
  -promscrape.config=/opt/pms5003/prometheus.yml \
  -retentionPeriod=10y \
  -memory.allowedPercent=40
Restart=always
[Install]
WantedBy=multi-user.target
EOF

echo ">>> [3/5] 1 GB swap"
if [ ! -f /swapfile ]; then
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
fi

echo ">>> [4/5] Grafana"
apt-get install -y apt-transport-https software-properties-common curl gnupg
mkdir -p /etc/apt/keyrings
curl -s https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" >/etc/apt/sources.list.d/grafana.list
apt-get update -qq
apt-get install -y grafana

echo ">>> [5/5] enable services"
systemctl daemon-reload
systemctl enable --now pms5003 victoriametrics grafana-server

echo
echo "Done. Checks:"
sleep 3
curl -s localhost:8000/metrics | grep -m1 pms5003 || echo "  (exporter not producing yet — check: journalctl -u pms5003)"
echo "  VictoriaMetrics: http://192.168.1.115:8428"
echo "  Grafana:         http://192.168.1.115:3000  (admin/admin)"
