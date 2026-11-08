A=http://10.10.10.20:8080
J='Content-Type: application/json'
login(){ curl -s -D - -o /dev/null -X POST $A/api/login -H "$J" -d "{\"username\":\"$1\",\"password\":\"$2\"}" | tr -d '\r' | sed -n 's/^set-cookie: kn_session=\([^;]*\).*/\1/Ip'; }
q(){ PGPASSWORD='AppSecretPass_2026!' psql -h 10.10.10.30 -U bank_app -d digital_bank -Atc "$1"; }
echo "=== $(date -u) test dong thoi ==="
echo "so deadlock trong log truoc test: $(sudo grep -c DeadlockDetected /var/log/bank-app.log)"
T1=$(login user1 'User1@123'); T2=$(login user2 'User2@123')
echo "truoc: $(q "SELECT string_agg(account_no||'='||balance::bigint, ' ' ORDER BY account_no) FROM accounts WHERE account_no IN ('1900888801','1900888802')") | giao dich: $(q 'SELECT count(*) FROM transactions')"
rm -f /tmp/codes
# 40 giao dich cheo nhau cung luc: user1->user2 va user2->user1, moi lan 1000 VND
for i in $(seq 20); do
  ( curl -s -o /dev/null -w '%{http_code}\n' -X POST $A/api/transfer -H "$J" -H "Authorization: Bearer $T1" -d '{"to_account":"1900888802","amount":1000,"note":"par"}' >> /tmp/codes ) &
  ( curl -s -o /dev/null -w '%{http_code}\n' -X POST $A/api/transfer -H "$J" -H "Authorization: Bearer $T2" -d '{"to_account":"1900888801","amount":1000,"note":"par"}' >> /tmp/codes ) &
done; wait
echo "ma tra ve:"; sort /tmp/codes | uniq -c
echo "sau:   $(q "SELECT string_agg(account_no||'='||balance::bigint, ' ' ORDER BY account_no) FROM accounts WHERE account_no IN ('1900888801','1900888802')") | giao dich: $(q 'SELECT count(*) FROM transactions')"
echo "tong so du (phai la 70000000): $(q 'SELECT sum(balance)::bigint FROM accounts')"
echo "so deadlock trong log sau test: $(sudo grep -c DeadlockDetected /var/log/bank-app.log)"
rm -f /tmp/codes
