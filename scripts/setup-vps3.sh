#!/bin/bash
# Muoi Sau Bank - Cai dat vps3-data-db (10.10.10.30): PostgreSQL + UFW + sao luu ma hoa
# Chay: sudo REPO=/duong/dan/cnnt-16 bash scripts/setup-vps3.sh
set -euo pipefail
REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
DB_IP=10.10.10.30; APP_IP=10.10.10.20; MGMT_IP=10.10.10.40

echo "== [1/5] Cai PostgreSQL =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y postgresql postgresql-contrib openssl
PGVER=$(ls /etc/postgresql | sort -V | tail -1)
PG_CONF="/etc/postgresql/$PGVER/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PGVER/main/pg_hba.conf"
echo "PostgreSQL phien ban: $PGVER"

echo "== [2/5] Tao database va phan quyen least-privilege =="
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='digital_bank'" | grep -q 1 \
  || sudo -u postgres createdb digital_bank
sudo -u postgres psql -v ON_ERROR_STOP=1 -d digital_bank < "$REPO/database/init_db.sql"

echo "== [3/5] Chi lang nghe IP noi bo, chi nhan bank_app tu vps2 =="
sed -i "s/^#\?listen_addresses.*/listen_addresses = 'localhost,$DB_IP'/" "$PG_CONF"
grep -q "$APP_IP/32" "$PG_HBA" || \
  echo "host    digital_bank    bank_app    $APP_IP/32    scram-sha-256" >> "$PG_HBA"
systemctl restart postgresql
systemctl enable postgresql

echo "== [4/5] UFW =="
ufw default deny incoming
ufw default allow outgoing
ufw allow from $MGMT_IP to any port 22 proto tcp
ufw allow from $APP_IP to any port 5432 proto tcp
ufw --force enable

echo "== [5/5] Sao luu ma hoa AES-256 + cron 02:00 =="
mkdir -p /var/backups/postgres
chown postgres:postgres /var/backups/postgres; chmod 700 /var/backups/postgres
if [ ! -f /root/.backup_passphrase ]; then
  openssl rand -base64 24 > /root/.backup_passphrase
fi
chmod 600 /root/.backup_passphrase
cat > /usr/local/bin/backup_bank_db.sh <<'BEOF'
#!/bin/bash
set -euo pipefail
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ENC_FILE="/var/backups/postgres/digital_bank_${TIMESTAMP}.sql.gz.enc"
sudo -u postgres pg_dump --clean --if-exists digital_bank | gzip | \
  openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:/root/.backup_passphrase -out "${ENC_FILE}"
chmod 600 "${ENC_FILE}"
logger -t BANK_BACKUP "BACKUP_SUCCESS: Created encrypted backup ${ENC_FILE}"
echo "[OK] Da tao ban sao luu ma hoa: ${ENC_FILE}"
BEOF
chmod 700 /usr/local/bin/backup_bank_db.sh
/usr/local/bin/backup_bank_db.sh
# Luu y: khong dung "crontab -l | grep -v" trong set -e/pipefail (grep tra ve 1 khi crontab rong -> mat dong cron)
{ crontab -l 2>/dev/null || true; } | { grep -v backup_bank_db.sh || true; } > /tmp/cron.new
echo "0 2 * * * /usr/local/bin/backup_bank_db.sh" >> /tmp/cron.new
crontab /tmp/cron.new && rm -f /tmp/cron.new

echo; echo "HOAN TAT vps3."
ufw status verbose
