# Chay tren vps2: dung tai khoan ung dung bank_app tan cong CSDL tren vps3
export PGPASSWORD='AppSecretPass_2026!'
c(){ psql -h 10.10.10.30 -U bank_app -d digital_bank "$@"; }
echo "=== $(date -u) KIEM THU DAC QUYEN TOI THIEU (bank_app tu vps2 -> vps3) ==="
echo "audit_logs truoc: $(c -Atc 'SELECT count(*) FROM audit_logs') dong; transactions: $(c -Atc 'SELECT count(*) FROM transactions') dong"
for q in "DELETE FROM transactions" "DROP TABLE users" "DELETE FROM audit_logs" "UPDATE audit_logs SET status='SUCCESS'" "TRUNCATE audit_logs" "DROP TABLE audit_logs" "ALTER TABLE audit_logs DISABLE TRIGGER ALL" "CREATE TABLE hack(x int)" "GRANT ALL ON audit_logs TO bank_app" "TRUNCATE accounts CASCADE" "ALTER ROLE bank_app SUPERUSER" "CREATE ROLE evil SUPERUSER"; do
  printf '%s  %-48s -> ' "$(date -u +%T)" "$q"; c -c "$q" 2>&1 | head -1
done
echo "audit_logs sau: $(c -Atc 'SELECT count(*) FROM audit_logs') dong; transactions: $(c -Atc 'SELECT count(*) FROM transactions') dong"
echo "--- Thao tac hop le van duoc phep (bank_app chi doc/them):"
printf '%s  SELECT count(*) FROM audit_logs -> ' "$(date -u +%T)"; c -Atc "SELECT count(*) FROM audit_logs"
