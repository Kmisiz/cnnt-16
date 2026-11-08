cd /tmp
P="sudo -u postgres psql -d digital_bank -X"
echo "=== $(date -u) vps3 ==="
echo "--- [1] Dich vu & cong mang"
systemctl is-active postgresql; systemctl is-enabled postgresql
ss -ltn | grep -E ':5432|:22 '
echo "--- [2] pg_hba (dong khong phai comment)"
sudo grep -vE '^\s*(#|$)' /etc/postgresql/14/main/pg_hba.conf
echo "--- [3] Thong so bao mat"
$P -Atc "SHOW listen_addresses;" -c "SHOW password_encryption;" -c "SHOW ssl;"
echo "--- [4] Thuoc tinh role bank_app (phai khong co quyen dac biet)"
$P -c "SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls, rolcanlogin FROM pg_roles WHERE rolname IN ('bank_app','postgres');"
echo "--- [5] Quyen tren database/schema"
$P -c "SELECT datname, datacl FROM pg_database WHERE datname='digital_bank';" -c "SELECT nspname, nspacl FROM pg_namespace WHERE nspname='public';"
echo "--- [6] Owner cac bang (bank_app khong duoc la owner)"
$P -c "SELECT tablename, tableowner FROM pg_tables WHERE schemaname='public' ORDER BY 1;"
echo "--- [7] Quyen bank_app tren tung bang"
$P -c "SELECT table_name, string_agg(privilege_type, ',' ORDER BY privilege_type) AS quyen FROM information_schema.role_table_grants WHERE grantee='bank_app' GROUP BY 1 ORDER BY 1;"
echo "--- [8] UFW"
sudo ufw status verbose
echo "--- [9] Sao luu"
sudo bash -c 'ls -l /var/backups/postgres/; stat -c "%a %U:%G %n" /var/backups/postgres /root/.backup_passphrase /usr/local/bin/backup_bank_db.sh; echo "cron:"; crontab -l'
echo "--- [10] Kiem tra toan ven file backup moi nhat"
sudo bash -c '
F=$(ls -t /var/backups/postgres/*.enc | head -1); echo "file: $F"
echo -n "giai ma dung khoa + gzip -t: "; openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/root/.backup_passphrase -in "$F" | gzip -t && echo OK
echo -n "giai ma SAI khoa phai that bai: "; echo wrongpass > /tmp/wp; openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/tmp/wp -in "$F" 2>/dev/null | gunzip 2>/dev/null | head -c 50 | wc -c | xargs -I{} echo "{} byte doc duoc (0 = tot)"; rm -f /tmp/wp
echo -n "noi dung dump co chua du lieu thuong khong (grep ten user trong file ma hoa): "; grep -c "user1" "$F" || true
echo "so dong COPY trong dump:"; openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/root/.backup_passphrase -in "$F" | gunzip | grep -c "^COPY"
echo "syslog BANK_BACKUP:"; grep BANK_BACKUP /var/log/syslog | tail -3'
echo "--- [11] Chuyen syslog sang vps4 (SIEM)?"
sudo grep -rE '^\s*[^#]*@{1,2}[0-9a-zA-Z]' /etc/rsyslog.conf /etc/rsyslog.d/ 2>/dev/null || echo "KHONG co cau hinh chuyen syslog tu xa"
echo "--- [12] Dung luong / thoi gian / cap nhat"
df -h / | tail -1; timedatectl | grep -E "Time zone|synchronized"
