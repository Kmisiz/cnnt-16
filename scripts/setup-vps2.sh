#!/bin/bash
# Muoi Sau Bank - Cai dat vps2-app-api (10.10.10.20): FastAPI Core Banking + UFW
# Chay: sudo REPO=/duong/dan/cnnt-16 bash scripts/setup-vps2.sh   (sau khi vps3 xong)
set -euo pipefail
REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
APP_DIR=/opt/bank-app; WAF_IP=10.10.10.10; MGMT_IP=10.10.10.40

echo "== [1/5] Cai goi he thong =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-venv python3-pip

echo "== [2/5] Thu muc dich vu va thu vien =="
id bankapp >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin bankapp
mkdir -p $APP_DIR
cp "$REPO/backend/main.py" "$REPO/backend/requirements.txt" $APP_DIR/
if [ ! -f $APP_DIR/.env ]; then
  cp "$REPO/backend/bank-app.env.example" $APP_DIR/.env
  sed -i "s/^JWT_SECRET=.*/JWT_SECRET=$(openssl rand -hex 32)/" $APP_DIR/.env
fi
[ -d $APP_DIR/venv ] || python3 -m venv $APP_DIR/venv
$APP_DIR/venv/bin/pip install --upgrade pip
$APP_DIR/venv/bin/pip install -r $APP_DIR/requirements.txt
chown -R bankapp:bankapp $APP_DIR; chmod 600 $APP_DIR/.env

echo "== [3/5] File log (service dung ProtectSystem=strict nen file phai ton tai) =="
touch /var/log/bank-app.log
chown bankapp:bankapp /var/log/bank-app.log

echo "== [4/5] Systemd service =="
cp "$REPO/backend/bank-app.service" /etc/systemd/system/bank-app.service
systemctl daemon-reload
systemctl enable bank-app
systemctl restart bank-app
sleep 6
systemctl status bank-app --no-pager || true
echo "Health check:"; curl -s -m 5 http://10.10.10.20:8080/api/health; echo

echo "== [5/5] UFW =="
ufw default deny incoming
ufw default allow outgoing
ufw allow from $MGMT_IP to any port 22 proto tcp
ufw allow from $WAF_IP to any port 8080 proto tcp
ufw --force enable

echo; echo "HOAN TAT vps2."
ufw status verbose
