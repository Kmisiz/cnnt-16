# configs

Cấu hình theo từng máy hoặc dịch vụ. Đầu mỗi file ghi rõ chạy trên máy nào.

| Thư mục | Nội dung | Phụ trách |
|---|---|---|
| `wazuh/` | Decoder, rule, cấu hình FIM và `<localfile>` cho agent | Trưởng nhóm |
| `rsyslog/` | Cấu hình nhận log trên vps4 và chuyển log từ vps2 | SV4 |
| `ufw/` | Đầu ra `ufw status verbose` của từng máy | SV2 |

Cấu hình Nginx nằm trong `frontend/nginx/`.
