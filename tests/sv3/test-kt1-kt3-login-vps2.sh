# Chay tren vps2: KT1 (khach dung chuc nang) + KT3 (dang nhap sai co log) + RBAC. Chuyen khoan di roi chuyen lai nen so du khong doi.
A=http://10.10.10.20:8080; J='Content-Type: application/json'
export PGPASSWORD='AppSecretPass_2026!'
q(){ psql -h 10.10.10.30 -U bank_app -d digital_bank -c "$1"; }
login(){ curl -s -D - -o /dev/null -X POST $A/api/login -H "$J" -d "{\"username\":\"$1\",\"password\":\"$2\"}" | tr -d '\r' | sed -n 's/^set-cookie: kn_session=\([^;]*\).*/\1/Ip'; }
ts(){ date -u +%T; }
echo "=== $(date -u) KT1: khach hop le dung duoc chuc nang duoc cap ==="
T1=$(login user1 'User1@123'); T2=$(login user2 'User2@123'); echo "$(ts) dang nhap user1, user2 -> token ${#T1}/${#T2} ky tu"
echo "$(ts) GET /api/my-account (user1):";  curl -s -H "Authorization: Bearer $T1" $A/api/my-account; echo
echo "$(ts) GET /api/accounts/lookup?account_no=1900888802:"; curl -s -H "Authorization: Bearer $T1" "$A/api/accounts/lookup?account_no=1900888802"; echo
echo "$(ts) POST /api/transfer user1 -> 1900888802, 500000 VND:"; curl -s -H "Authorization: Bearer $T1" -X POST $A/api/transfer -H "$J" -d '{"to_account":"1900888802","amount":500000,"note":"KT1 di"}'; echo
echo "$(ts) POST /api/transfer user2 -> 1900888801, 500000 VND (chuyen lai):"; curl -s -H "Authorization: Bearer $T2" -X POST $A/api/transfer -H "$J" -d '{"to_account":"1900888801","amount":500000,"note":"KT1 ve"}'; echo
echo "$(ts) GET /api/my-transactions?limit=2:"; curl -s -H "Authorization: Bearer $T1" "$A/api/my-transactions?limit=2" | head -c 500; echo
echo "$(ts) GET /api/my-account sau chuyen:"; curl -s -H "Authorization: Bearer $T1" $A/api/my-account; echo
echo; echo "=== $(date -u) KT3: dang nhap sai co bang chung log ==="
for i in 1 2 3; do printf '%s  login admin sai mat khau lan %s -> HTTP ' "$(ts)" $i; curl -s -o /dev/null -w '%{http_code}\n' -X POST $A/api/login -H "$J" -d '{"username":"admin","password":"MatKhauSai"}'; done
printf '%s  login user khong ton tai (hacker) -> HTTP ' "$(ts)"; curl -s -o /dev/null -w '%{http_code}\n' -X POST $A/api/login -H "$J" -d '{"username":"hacker","password":"x"}'
echo "$(ts) RBAC: user1 (customer) goi /api/admin/users:"; curl -s -w ' -> HTTP %{http_code}\n' -H "Authorization: Bearer $T1" $A/api/admin/users
echo "$(ts) Doc bang audit_logs trong CSDL (vps3) - 10 dong moi nhat:"
q "SELECT to_char(event_time AT TIME ZONE 'UTC','HH24:MI:SS') AS gio_utc, username, action, status, client_ip, left(details,45) AS chi_tiet FROM audit_logs ORDER BY id DESC LIMIT 10;"
