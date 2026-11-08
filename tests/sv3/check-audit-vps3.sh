cd /tmp
P="sudo -u postgres psql -d digital_bank -X"
echo "=== $(date -u) don dep user thu ==="
$P -c "DELETE FROM accounts WHERE user_id IN (SELECT id FROM users WHERE username='tmp_test');" -c "DELETE FROM users WHERE username='tmp_test';"
$P -c "SELECT username, role, is_active FROM users ORDER BY id;" -c "SELECT account_no, balance FROM accounts ORDER BY 1;"
echo "=== Thong ke audit_logs theo hanh dong/ket qua ==="
$P -c "SELECT action, status, count(*) FROM audit_logs GROUP BY 1,2 ORDER BY 1,2;"
echo "=== 12 dong gan nhat ==="
$P -c "SELECT to_char(event_time,'HH24:MI:SS') AS gio, username, action, status, client_ip, left(details,48) AS chi_tiet FROM audit_logs ORDER BY id DESC LIMIT 12;"
