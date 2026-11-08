cd /tmp
echo "=== $(date -u) vps2 ==="
echo "--- [1] Dich vu"
systemctl is-active bank-app; systemctl is-enabled bank-app
ps -o user,pid,cmd -C python3 | head -4
echo "--- [2] Cong lang nghe (phai la 10.10.10.20:8080, khong phai 0.0.0.0)"
ss -ltnp 2>/dev/null | grep -E ':8080|:22 ' | awk '{print $1,$4}'
echo "--- [3] Quyen file nhay cam"
sudo stat -c "%a %U:%G %n" /opt/bank-app/.env /opt/bank-app /var/log/bank-app.log
echo "--- [4] .env: khong in gia tri bi mat"
sudo sed -E 's/^(DB_PASSWORD|JWT_SECRET)=.*/\1=***an***/' /opt/bank-app/.env
echo -n "JWT_SECRET con la gia tri mau? "; sudo grep -q 'JWT_SECRET=thay-bang-chuoi-ngau-nhien' /opt/bank-app/.env && echo "CO (LOI)" || echo "Khong (tot), do dai: $(sudo grep ^JWT_SECRET= /opt/bank-app/.env | cut -d= -f2 | tr -d '\n' | wc -c)"
echo "--- [5] Loi trong log ung dung"
sudo grep -ciE "error|traceback|exception" /var/log/bank-app.log | xargs echo "so dong loi:"
sudo grep -iE "error|traceback" /var/log/bank-app.log | tail -5
echo "--- [6] UFW"
sudo ufw status verbose | sed -n 1,12p
echo "--- [7] Tu vps2: sang vps3"
echo -n "vps3:5432 (phai MO)   : "; timeout 4 bash -c '</dev/tcp/10.10.10.30/5432' 2>&1 && echo MO || echo "bi chan/khong thong"
echo -n "vps3:22   (phai CHAN) : "; timeout 4 bash -c '</dev/tcp/10.10.10.30/22' 2>/dev/null && echo "MO (LOI)" || echo "bi chan (tot)"
echo -n "vps1:8080 (WAF, SV2)  : "; timeout 4 bash -c '</dev/tcp/10.10.10.10/8080' 2>/dev/null && echo MO || echo "chan/chua cai WAF"
echo -n "vps0:443  (web)       : "; timeout 4 bash -c '</dev/tcp/10.10.10.5/443' 2>/dev/null && echo MO || echo "chan/khong thong"
echo "--- [8] DB: dang nhap sai / sai user"
export PGCONNECT_TIMEOUT=5
echo -n "bank_app sai mat khau: "; PGPASSWORD=sai psql -h 10.10.10.30 -U bank_app -d digital_bank -c "select 1" 2>&1 | head -1
echo -n "user postgres tu vps2: "; PGPASSWORD=postgres psql -h 10.10.10.30 -U postgres -d digital_bank -c "select 1" 2>&1 | head -1
echo -n "bank_app vao DB khac : "; PGPASSWORD='AppSecretPass_2026!' psql -h 10.10.10.30 -U bank_app -d postgres -c "select 1" 2>&1 | head -1
echo -n "TLS toi DB?          : "; PGPASSWORD='AppSecretPass_2026!' psql -h 10.10.10.30 -U bank_app -d digital_bank -Atc "select ssl from pg_stat_ssl where pid=pg_backend_pid()"
echo "--- [9] Header & lo thong tin cua API"
curl -sI http://10.10.10.20:8080/api/health | tr -d '\r' | head -8
echo -n "/docs (Swagger) mo?  : "; curl -s -o /dev/null -w '%{http_code}\n' http://10.10.10.20:8080/docs
echo -n "/openapi.json mo?    : "; curl -s -o /dev/null -w '%{http_code}\n' http://10.10.10.20:8080/openapi.json
echo "--- [10] Syslog chuyen sang vps4?"
sudo grep -rE '^\s*[^#]*@{1,2}[0-9a-zA-Z]' /etc/rsyslog.conf /etc/rsyslog.d/ 2>/dev/null || echo "KHONG co cau hinh chuyen syslog tu xa"
echo "--- [11] Tai nguyen"
free -m | sed -n 1,2p; df -h / | tail -1
