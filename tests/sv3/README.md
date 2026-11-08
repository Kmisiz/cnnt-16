# Kiem thu SV3 (xac thuc, du lieu, sao luu)

Chay tu may nha, vi du: `ssh -J thang2k6adu@34.87.139.11 thang2k6adu@10.10.10.20 'bash -s' < tests/sv3/test-api-vps2.sh`

| File | Chay tren | Kiem tra gi |
|---|---|---|
| test-api-vps2.sh | vps2 | 48 request API: token gia, SQLi, RBAC, nghiep vu chuyen khoan, khoa/mo khoa, tao user |
| test-concurrency-vps2.sh | vps2 | 40 chuyen khoan cheo nhau cung luc, khong deadlock, tong so du khong doi |
| check-infra-vps2.sh | vps2 | dich vu, cong, quyen file, tuong lua, ket noi DB sai, TLS toi DB |
| check-infra-vps3.sh | vps3 | cau hinh PostgreSQL, quyen bank_app, UFW, backup (giai ma dung/sai khoa) |
| check-network-vps3.sh | vps3 | vps3 khong goi duoc vps2 |
| check-audit-vps3.sh | vps3 | don user thu `tmp_test` + thong ke audit_logs (chay SAU test-api) |
| test-least-privilege-vps2.sh | vps2 | bank_app tan cong CSDL: DELETE/DROP/TRUNCATE/GRANT/tao superuser phai bi chan |
| test-kt1-kt3-login-vps2.sh | vps2 | KT1 chuc nang khach, KT3 dang nhap sai co log, RBAC (chuyen khoan di roi chuyen lai) |
| test-backup-restore-vps3.sh | vps3 | KT3 backup ma hoa, mo phong mat du lieu, phuc hoi, doi chieu checksum |

Luu y: test-api tao user `tmp_test` (bank_app khong co quyen DELETE), phai chay check-audit-vps3.sh de xoa bang quyen postgres.
Mat khau demo trong cac script la du lieu gia lap.
