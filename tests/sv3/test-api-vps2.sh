A=http://10.10.10.20:8080
J='Content-Type: application/json'
login(){ curl -s -D - -o /dev/null -X POST $A/api/login -H "$J" -d "{\"username\":\"$1\",\"password\":\"$2\"}" | tr -d '\r' | sed -n 's/^set-cookie: kn_session=\([^;]*\).*/\1/Ip'; }
req(){ # name expected method path token [body]
  local name="$1" exp="$2" m="$3" p="$4" t="$5" b="$6" code
  if [ -n "$b" ]; then code=$(curl -s -o /tmp/out -w '%{http_code}' -X $m "$A$p" -H "$J" ${t:+-H "Authorization: Bearer $t"} -d "$b")
  else code=$(curl -s -o /tmp/out -w '%{http_code}' -X $m "$A$p" ${t:+-H "Authorization: Bearer $t"}); fi
  [ "$code" = "$exp" ] && r=PASS || r=FAIL
  printf '%-4s %-52s expect=%s got=%s  %s\n' $r "$name" $exp $code "$(head -c 80 /tmp/out | tr '\n' ' ')"
}
sumbal(){ PGPASSWORD='AppSecretPass_2026!' psql -h 10.10.10.30 -U bank_app -d digital_bank -Atc "SELECT sum(balance)::bigint FROM accounts"; }

cat > /tmp/forge.py <<'PY'
import base64, json, hmac, hashlib, sys
b = lambda x: base64.urlsafe_b64encode(x).rstrip(b'=').decode()
mode = sys.argv[1]
if mode == 'wrongsecret':
    h = b(json.dumps({'alg':'HS256','typ':'JWT'}).encode()); p = b(json.dumps({'sub':'admin','uid':4,'role':'admin','exp':9999999999}).encode())
    print(h+'.'+p+'.'+b(hmac.new(b'guess',(h+'.'+p).encode(),hashlib.sha256).digest()))
elif mode == 'none':
    print(b(json.dumps({'alg':'none','typ':'JWT'}).encode())+'.'+b(json.dumps({'sub':'admin','uid':4,'role':'admin','exp':9999999999}).encode())+'.')
elif mode == 'tamper':
    h, p, s = sys.argv[2].split('.')
    d = json.loads(base64.urlsafe_b64decode(p + '=' * (-len(p) % 4))); d['role'] = 'admin'; d['uid'] = 4
    print(h + '.' + b(json.dumps(d).encode()) + '.' + s)
PY

echo "=== $(date -u) ==="
T1=$(login user1 'User1@123'); T2=$(login user2 'User2@123'); TT=$(login teller 'Teller@123'); TA=$(login admin 'Admin@123')
echo "do dai token: user1=${#T1} user2=${#T2} teller=${#TT} admin=${#TA}"
echo "tong so du truoc: $(sumbal)"

echo "--- XAC THUC"
req "khong token -> /api/me"                    401 GET /api/me ""
req "token rac"                                 401 GET /api/me "abc.def.ghi"
req "token ky sai secret (gia admin)"           401 GET /api/me "$(python3 /tmp/forge.py wrongsecret)"
req "token alg=none (gia admin)"                401 GET /api/me "$(python3 /tmp/forge.py none)"
req "sua payload user1 thanh admin"             401 GET /api/admin/users "$(python3 /tmp/forge.py tamper "$T1")"
req "login sai mat khau"                        401 POST /api/login "" '{"username":"user1","password":"sai"}'
req "login user khong ton tai"                  401 POST /api/login "" '{"username":"khong_co","password":"x"}'
req "SQLi: admin' OR '1'='1"                    401 POST /api/login "" "{\"username\":\"admin' OR '1'='1\",\"password\":\"x\"}"
req "SQLi: admin'--"                            401 POST /api/login "" "{\"username\":\"admin'--\",\"password\":\"x\"}"
req "login thieu truong password"               422 POST /api/login "" '{"username":"admin"}'
req "username 80 ky tu"                         422 POST /api/login "" "{\"username\":\"$(printf 'a%.0s' $(seq 80))\",\"password\":\"x\"}"

echo "--- PHAN QUYEN (RBAC)"
req "customer -> /api/my-account"               200 GET /api/my-account "$T1"
req "customer -> /api/accounts (nhan vien)"     403 GET /api/accounts "$T1"
req "customer -> /api/admin/users"              403 GET /api/admin/users "$T1"
req "customer -> /api/admin/audit-logs"         403 GET /api/admin/audit-logs "$T1"
req "customer tu khoa user2"                    403 PATCH /api/admin/users/user2/status "$T1" '{"is_active":false}'
req "teller -> /api/accounts"                   200 GET /api/accounts "$TT"
req "teller -> /api/admin/users"                403 GET /api/admin/users "$TT"
req "teller -> /api/transfer"                   403 POST /api/transfer "$TT" '{"to_account":"1900888801","amount":1000}'
req "teller -> /api/my-account"                 403 GET /api/my-account "$TT"
req "admin -> /api/admin/users"                 200 GET /api/admin/users "$TA"
req "admin -> /api/admin/audit-logs"            200 GET "/api/admin/audit-logs?limit=5" "$TA"
req "admin -> /api/transfer"                    403 POST /api/transfer "$TA" '{"to_account":"1900888801","amount":1000}'
req "staff-check customer"                      403 GET /api/auth/staff-check "$T1"
req "staff-check khong dang nhap"               401 GET /api/auth/staff-check ""
req "staff-check teller"                        204 GET /api/auth/staff-check "$TT"
req "staff-check admin"                         204 GET /api/auth/staff-check "$TA"

echo "--- NGHIEP VU CHUYEN KHOAN"
req "chuyen vuot so du"                         400 POST /api/transfer "$T1" '{"to_account":"1900888802","amount":400000000}'
req "so tien am"                                422 POST /api/transfer "$T1" '{"to_account":"1900888802","amount":-1000}'
req "so tien 0"                                 422 POST /api/transfer "$T1" '{"to_account":"1900888802","amount":0}'
req "so tien > han muc 500tr"                   422 POST /api/transfer "$T1" '{"to_account":"1900888802","amount":600000000}'
req "chuyen cho chinh minh"                     400 POST /api/transfer "$T1" '{"to_account":"1900888801","amount":1000}'
req "tai khoan nhan khong ton tai"              404 POST /api/transfer "$T1" '{"to_account":"1900999999","amount":1000}'
req "so tai khoan chua chu (SQLi)"              422 POST /api/transfer "$T1" '{"to_account":"1; DROP TABLE users","amount":1000}'
req "lookup SQLi"                               400 GET "/api/accounts/lookup?account_no=1%27%20OR%20%271" "$T1"
req "lookup tai khoan hop le"                   200 GET "/api/accounts/lookup?account_no=1900888802" "$T1"
req "sao ke cua minh"                           200 GET /api/my-transactions "$T1"

echo "--- KHOA / MO KHOA TAI KHOAN"
req "admin tu khoa chinh minh"                  400 PATCH /api/admin/users/admin/status "$TA" '{"is_active":false}'
req "admin khoa user2"                          200 PATCH /api/admin/users/user2/status "$TA" '{"is_active":false}'
req "user2 dung token cu sau khi bi khoa"       401 GET /api/my-account "$T2"
req "user2 dang nhap khi bi khoa"               403 POST /api/login "" '{"username":"user2","password":"User2@123"}'
req "admin mo khoa user2"                       200 PATCH /api/admin/users/user2/status "$TA" '{"is_active":true}'
req "user2 dang nhap lai"                       200 POST /api/login "" '{"username":"user2","password":"User2@123"}'

echo "--- TAO NGUOI DUNG"
req "tao user trung ten"                        409 POST /api/admin/users "$TA" '{"username":"user1","password":"Abcdef12","full_name":"Trung","role":"customer"}'
req "mat khau ngan < 8"                         422 POST /api/admin/users "$TA" '{"username":"tmp_test","password":"123","full_name":"Tmp Test","role":"customer"}'
req "role khong hop le"                         422 POST /api/admin/users "$TA" '{"username":"tmp_test","password":"Abcdef12","full_name":"Tmp Test","role":"root"}'
req "tao customer tmp_test (se xoa sau)"        201 POST /api/admin/users "$TA" '{"username":"tmp_test","password":"Abcdef12","full_name":"Tmp Test","role":"customer","initial_balance":0}'

echo "--- DONG THOI: 20 chuyen khoan song song 2 chieu (user1<->user2, 1000 VND moi lan)"
for i in $(seq 10); do
  curl -s -o /dev/null -X POST $A/api/transfer -H "$J" -H "Authorization: Bearer $T1" -d '{"to_account":"1900888802","amount":1000,"note":"par"}' &
  curl -s -o /dev/null -X POST $A/api/transfer -H "$J" -H "Authorization: Bearer $T2" -d '{"to_account":"1900888801","amount":1000,"note":"par"}' &
done; wait
echo "tong so du sau: $(sumbal)"
req "logout" 200 POST /api/logout "$T1"
