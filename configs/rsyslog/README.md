# Luồng log thô (rsyslog)

Bản sao cấu hình đang chạy trên máy chủ. Phụ trách: SV4. Hướng dẫn và giải thích đầy đủ: `NHIEM-VU-SV4-NHAT-KY-AN-NINH.md`, mục 4.

| File trong repo | Vị trí trên máy | Vai trò |
|---|---|---|
| `vps2/60-forward-bank-app.conf` | vps2: `/etc/rsyslog.d/60-forward-bank-app.conf` | Đọc `/var/log/bank-app.log` (imfile), gửi TCP 514 tới vps4, có hàng đợi đĩa |
| `vps2/logrotate-bank-app` | vps2: `/etc/logrotate.d/bank-app` | Xoay vòng log ứng dụng hằng ngày, giữ 14 bản, `copytruncate` |
| `vps4/10-central-bank.conf` | vps4: `/etc/rsyslog.d/10-central-bank.conf` | Ghi log từ máy khác vào `/var/log/central-bank/<máy>/<chương trình>.log`, không chép lặp vào `/var/log/syslog` |
| `vps4/logrotate-central-bank` | vps4: `/etc/logrotate.d/central-bank` | Xoay vòng kho log tập trung hằng ngày, giữ 14 bản |

Trên vps4, bộ nhận TCP 514 được bật trong `/etc/rsyslog.conf`:

```
module(load="imtcp")
input(type="imtcp" port="514")
```

Kiểm tra cú pháp trước khi khởi động lại: `sudo rsyslogd -N1 && sudo systemctl restart rsyslog`.
