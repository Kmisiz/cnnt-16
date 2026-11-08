# Chay tren vps3: KT3 sao luu ma hoa -> mo phong mat du lieu -> giai ma + phuc hoi -> doi chieu checksum
cd /tmp
P="sudo -u postgres psql -d digital_bank -X"
H(){ $P -Atc "SELECT md5(coalesce((SELECT string_agg(account_no||':'||balance::text,',' ORDER BY account_no) FROM accounts),'')||'|'||coalesce((SELECT string_agg(id||':'||from_account||'>'||to_account||':'||amount::text,',' ORDER BY id) FROM transactions),'')||'|'||(SELECT count(*) FROM audit_logs)||'|'||(SELECT count(*) FROM users))"; }
S(){ $P -c "SELECT (SELECT count(*) FROM users) AS users, (SELECT count(*) FROM accounts) AS accounts, (SELECT count(*) FROM transactions) AS transactions, (SELECT count(*) FROM audit_logs) AS audit_logs, (SELECT sum(balance)::bigint FROM accounts) AS tong_so_du;"; }
echo "=== $(date -u) [1] Sao luu ma hoa AES-256-CBC (pbkdf2)"
sudo /usr/local/bin/backup_bank_db.sh
LATEST=$(sudo bash -c 'ls -t /var/backups/postgres/digital_bank_*.sql.gz.enc | head -n1')
sudo ls -l "$LATEST"; echo "8 byte dau file (ma hoa, khong doc duoc noi dung): $(sudo head -c 8 "$LATEST")"
echo "--- khoa sai thi khong giai ma duoc:"; echo wrong | sudo tee /tmp/wp >/dev/null; sudo bash -c "openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/tmp/wp -in '$LATEST' 2>&1 | gunzip 2>&1 | head -c 120 | tr -cd '[:print:]
'"; echo; sudo rm -f /tmp/wp
echo "=== $(date -u) [2] Trang thai TRUOC su co"; S; BEFORE=$(H); echo "checksum truoc = $BEFORE"
echo "=== $(date -u) [3] MO PHONG SU CO: TRUNCATE transactions, accounts CASCADE"
$P -c "TRUNCATE TABLE transactions, accounts CASCADE;"; S
echo "=== $(date -u) [4] PHUC HOI: giai ma AES-256 -> gunzip -> psql"
sudo bash -c "openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/root/.backup_passphrase -in '$LATEST' | gunzip | sudo -u postgres psql -d digital_bank -q" 2>&1 | grep -iE "error|fatal" || echo "(khong co loi)"
echo "=== $(date -u) [5] Trang thai SAU phuc hoi"; S; AFTER=$(H); echo "checksum sau   = $AFTER"
[ "$BEFORE" = "$AFTER" ] && echo "KET QUA: KHOP - du lieu phuc hoi 100%" || echo "KET QUA: KHONG KHOP"
$P -c "SELECT account_no, balance FROM accounts ORDER BY 1;"
echo "=== $(date -u) [6] Kiem tra quyen sau phuc hoi"
$P -c "SELECT table_name, string_agg(privilege_type, ',' ORDER BY privilege_type) AS quyen_bank_app FROM information_schema.role_table_grants WHERE grantee='bank_app' GROUP BY 1 ORDER BY 1;"
