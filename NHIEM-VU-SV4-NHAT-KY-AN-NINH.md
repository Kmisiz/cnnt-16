# SV4: NHẬT KÝ AN NINH, LOG THÔ TẬP TRUNG VÀ KIỂM THỬ NGHIỆM THU

**Đề 16: Thiết kế hạ tầng CNTT an toàn cho ngân hàng số (Ngân hàng Số Mười Sáu)**
**Phiếu giao:** SV4 là "Kiểm thử chính sách và nhật ký".
**Sản phẩm kỹ thuật riêng của SV4:** (1) cấu hình luồng log thô rsyslog; (2) phần audit log ở ba tầng; (3) script và bằng chứng KT1–KT3.

> Tài liệu này thay bản cũ. Những chỗ sửa so với bản cũ nằm ở mục 9.

---

## 1. Vai trò và ranh giới với các thành viên khác

Nhật ký của hệ thống chạy thành **hai luồng song song, độc lập nhau**:

| | Luồng 1: log thô | Luồng 2: log đã phân tích |
|---|---|---|
| Công nghệ | rsyslog + bảng `audit_logs` | Wazuh SIEM |
| Giữ gì | Nguyên văn từng dòng log | Alert theo rule, FIM, tương quan sự kiện |
| Dùng để | Bằng chứng gốc cho KT3, điều tra khi dashboard hỏng | Phát hiện và cảnh báo trên cả 5 máy |
| **Người phụ trách** | **SV4 (tài liệu này)** | Trưởng nhóm (SV1) |

| Việc | SV4 | Trưởng nhóm | SV3 | SV2 |
|---|---|---|---|---|
| Định dạng dòng log của `bank-app.log` (mục 5) | Chủ trì, chốt định dạng | Dùng để viết decoder và rule | Sửa code theo chốt | |
| rsyslog trên vps2 và vps4, logrotate | Làm | | | |
| Luật tường lửa TCP 514 | Đề xuất | | | Áp luật VPC và UFW |
| Wazuh agent, FIM, rule, dashboard | Không làm | Làm | | |
| Sao lưu và phục hồi CSDL | Chạy KT3.2 bằng script của SV3 | | Viết script | |
| Chạy và lưu bằng chứng KT1–KT3 | Làm | Hỗ trợ | Hỗ trợ | Hỗ trợ |

SV4 không cấu hình Wazuh. SV4 chỉ cung cấp số đếm từ log thô để trưởng nhóm đối soát (mục 6).

---

## 2. Thiết kế chạy song song

```text
vps2:  FastAPI ──► stdout ──systemd──► /var/log/bank-app.log
                                           │
                    ┌──────────────────────┴───────────────────────┐
                    │ Luồng 1 (SV4)                                │ Luồng 2 (trưởng nhóm)
                    ▼                                              ▼
          rsyslog (imfile) ──TCP 514──► vps4                Wazuh agent ──TCP 1514──► vps4
          hàng đợi đĩa trên vps2        /var/log/central-bank/       manager → indexer → dashboard
                                        <máy>/<chương trình>.log

          Song song: audit() ghi thêm một dòng vào bảng audit_logs (PostgreSQL, vps3)
```

Nguyên tắc:
1. **Hai luồng cùng đọc một file nguồn, nhưng không đọc của nhau.** Wazuh không đọc từ kho rsyslog. Hỏng một luồng không làm hỏng luồng kia.
2. **Luồng thô dùng TCP**, không dùng UDP. Bản cũ dùng `@` (UDP), có thể mất gói mà không báo.
3. **Cổng 514 do rsyslog dùng.** Bộ thu syslog của Wazuh tắt mặc định và cũng dùng 514; không bật nó trên vps4.
4. **Không bật FIM trên `/var/log/central-bank/`.** Thư mục này đổi liên tục nên sẽ sinh alert liên tục. Chống sửa log dựa vào việc kho log nằm trên máy khác với nơi sinh log.

---

## 3. Ba tầng nhật ký ứng dụng

1. **Tầng CSDL (`vps3-data-db`):** bảng `audit_logs`. Tài khoản ứng dụng `bank_app` chỉ có `SELECT`, `INSERT` trên bảng này (xem `database/init_db.sql`). Không có `UPDATE`, `DELETE`.
2. **Tầng ứng dụng (`vps2-app-api`):** hàm `audit()` trong `backend/main.py` ghi một dòng vào `bank-app.log` (qua stdout và systemd) và một dòng vào `audit_logs`.
3. **Tầng giao diện (`vps0`):** trang "Nhật ký an ninh" tại `/admin/`, gọi `GET /api/admin/audit-logs`.

### Các sự kiện thực tế trong code

| `ACTION` | `STATUS` | Ý nghĩa |
|---|---|---|
| `LOGIN` | `SUCCESS` | Đăng nhập thành công, ghi vai trò |
| `LOGIN` | `FAILED` | Sai tên đăng nhập hoặc mật khẩu |
| `LOGIN` | `DENIED` | Đúng mật khẩu nhưng tài khoản bị khóa |
| `RBAC` | `DENIED` | Người dùng thiếu quyền gọi API quản trị |
| `TOKEN_INVALID` | | Token không hợp lệ |
| `ADMIN_PATH_PROBE` | | Dò đường dẫn quản trị |
| `TRANSFER` | `SUCCESS` | Chuyển tiền nội bộ |
| `CREATE_USER`, `LOCK_USER`, `UNLOCK_USER` | `SUCCESS` | Thao tác quản trị |
| `VIEW_ACCOUNT`, `LIST_ACCOUNTS` | | Xem tài khoản |

Danh sách này lấy từ `backend/main.py`. Nếu code đổi, cập nhật bảng ở đây.

### Xem dữ liệu `audit_logs` từ máy cá nhân

```bash
ssh -J <user>@<IP_PUBLIC_VPS4> <user>@10.10.10.30
sudo -u postgres psql -d digital_bank -c "SELECT event_time, username, action, status, client_ip, details FROM audit_logs ORDER BY event_time DESC LIMIT 10;"
```

---

## 4. Cấu hình luồng log thô (rsyslog)

> Các cấu hình dưới đây chưa được chạy thử trên máy của nhóm. Luôn chạy `sudo rsyslogd -N1` để kiểm tra cú pháp trước khi `restart`.

### 4.1. vps4: nhận log qua TCP

```bash
# Chỉ bật TCP. Không bật UDP.
sudo sed -i 's/^#module(load="imtcp")/module(load="imtcp")/' /etc/rsyslog.conf
sudo sed -i 's/^#input(type="imtcp" port="514")/input(type="imtcp" port="514")/' /etc/rsyslog.conf

cat << 'EOF' | sudo tee /etc/rsyslog.d/10-central-bank.conf
$template RemoteLogs,"/var/log/central-bank/%HOSTNAME%/%PROGRAMNAME%.log"
# Chỉ ghi log đến từ máy khác, không ghi lặp log cục bộ của vps4
if ($fromhost-ip != '127.0.0.1') then ?RemoteLogs
EOF

sudo mkdir -p /var/log/central-bank
sudo rsyslogd -N1 && sudo systemctl restart rsyslog
```

UFW trên vps4: mở TCP 514 từ `10.10.10.0/24`, bỏ luật UDP 514 nếu đã có.

```bash
sudo ufw allow from 10.10.10.0/24 to any port 514 proto tcp comment 'FW-09 rsyslog TCP'
sudo ufw delete allow from 10.10.10.0/24 to any port 514 proto udp   # nếu luật này đã tồn tại
```

Luật VPC của GCP cũng cần chuyển FW-09 từ `udp:514,tcp:514` sang chỉ `tcp:514`. SV2 áp dụng.

### 4.2. vps2: chuyển `bank-app.log` bằng TCP có hàng đợi đĩa

```bash
cat << 'EOF' | sudo tee /etc/rsyslog.d/20-forward-bank.conf
module(load="imfile" PollingInterval="2")
input(type="imfile" File="/var/log/bank-app.log" Tag="bank-api" Severity="info" Facility="local0"
      PersistStateInterval="100")

local0.* action(type="omfwd" target="10.10.10.40" port="514" protocol="tcp"
                queue.type="LinkedList" queue.filename="fwd_bank_api"
                queue.maxDiskSpace="100m" queue.saveOnShutdown="on"
                action.resumeRetryCount="-1" action.resumeInterval="10")
EOF
sudo rsyslogd -N1 && sudo systemctl restart rsyslog
```

Hàng đợi đĩa giữ tin khi vps4 tạm mất kết nối và gửi lại khi kết nối trở lại. Phải kiểm chứng bằng thử nghiệm S4 ở mục 6, không tin vào cấu hình.

### 4.3. Xoay vòng log

vps4:

```bash
cat << 'EOF' | sudo tee /etc/logrotate.d/central-bank
/var/log/central-bank/*/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    postrotate
        systemctl kill -s HUP rsyslog.service >/dev/null 2>&1 || true
    endscript
}
EOF
```

vps2 (`bank-app.service` ghi bằng `StandardOutput=append:` nên systemd giữ file mở, phải dùng `copytruncate`):

```bash
cat << 'EOF' | sudo tee /etc/logrotate.d/bank-app
/var/log/bank-app.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
```

> Lưu ý: `copytruncate` có thể mất vài dòng ghi giữa lúc sao chép và cắt file. Ghi giới hạn này vào báo cáo.

### 4.4. Đồng bộ thời gian

Hai luồng so sánh thời điểm sự kiện. Chạy `timedatectl` trên cả 5 máy và ghi lại trạng thái đồng bộ vào bằng chứng.

---

## 5. Hợp đồng định dạng log (SV4, SV3 và trưởng nhóm)

Decoder và rule của Wazuh bám vào định dạng này. Đổi định dạng là làm hỏng rule của trưởng nhóm.

```text
[<asctime>] <LEVEL> bank-api USER=<tên> | ACTION=<hành động> | STATUS=<kết quả> | IP=<ip> | DETAILS=<chi tiết>
```

Quy tắc:
- Giữ nguyên thứ tự trường, dấu phân cách ` | ` và tiền tố `USER=`.
- Thêm hành động mới thì thêm giá trị `ACTION`, không đổi cấu trúc dòng.
- Muốn đổi cấu trúc thì báo trưởng nhóm trước, đổi cả decoder và chạy lại `wazuh-logtest`.

**Rủi ro đã thấy trong code (cần SV3 sửa):** `audit()` ghi `username` và `details` do người dùng nhập mà không lọc. `LoginIn.username` chỉ giới hạn 1–50 ký tự, không cấm khoảng trắng, ký tự `|` hay ký tự xuống dòng. Kẻ tấn công có thể nhập tên như `a | ACTION=LOGIN | STATUS=SUCCESS` để giả trường, hoặc chèn dòng giả vào `bank-app.log`. Hướng sửa: trong `audit()`, thay ký tự điều khiển và `|` trong `username` và `details` trước khi ghi. Cả bảng `audit_logs` (tham số hóa) lẫn file log đều cần được kiểm tra lại sau khi sửa.

---

## 6. Kiểm chứng và đối soát giữa hai luồng

### 6.1. KT3.1: đăng nhập sai có bằng chứng log

Chạy ba lần đăng nhập sai (đúng tài khoản, sai mật khẩu), rồi lấy bằng chứng ở **ba nơi** có timestamp:

```bash
# (a) Log thô trên vps4
sudo cat /var/log/central-bank/*/bank-api.log | grep 'ACTION=LOGIN' | grep 'STATUS=FAILED' | tail -n 5

# (b) Bảng audit_logs (chạy trên vps3)
sudo -u postgres psql -d digital_bank -c "SELECT event_time, username, action, status, client_ip FROM audit_logs WHERE action='LOGIN' AND status='FAILED' ORDER BY event_time DESC LIMIT 5;"

# (c) Phần của trưởng nhóm: alert rule 100100 và 100101 trên Wazuh
```

Bằng chứng chính cho KT3.1 là (a) và (b). Alert Wazuh ở (c) là bằng chứng bổ sung do trưởng nhóm cung cấp.

### 6.2. Đối soát số lượng (số đo thật cho phần so sánh)

Trước khi chạy, ghi lại số đếm hiện tại. Sau khi chạy N lần đăng nhập sai, ghi lại số đếm mới và lấy hiệu.

```bash
# Log thô trên vps4 (SV4)
sudo cat /var/log/central-bank/*/bank-api.log | grep 'ACTION=LOGIN' | grep -c 'STATUS=FAILED'

# Bảng audit_logs, chạy trên vps3 (SV4)
sudo -u postgres psql -d digital_bank -tc "SELECT count(*) FROM audit_logs WHERE action='LOGIN' AND status='FAILED';"

# Wazuh, chạy trên vps4 (trưởng nhóm; cần cài jq)
sudo jq -c 'select(.rule.id=="100100")' /var/ossec/logs/alerts/alerts.json | wc -l
```

Ba hiệu số phải bằng N. Nếu lệch, ghi lệch bao nhiêu và vì sao. Đó là dữ liệu so sánh độ phủ.

### 6.3. Các thử nghiệm độ tin cậy của luồng thô

| Mã | Thao tác | Quan sát |
|---|---|---|
| S4 | Chặn TCP 514 từ vps2 đến vps4 (UFW trên vps4) khoảng 5 phút, sinh 10 sự kiện đăng nhập sai, mở lại | Bao nhiêu dòng đến được vps4 sau khi mở lại |
| S5 | Thêm 10 dòng vào `bank-app.log`, chạy `logrotate -f /etc/logrotate.d/bank-app`, sinh thêm 10 sự kiện | Có mất dòng nào quanh thời điểm xoay vòng |
| S6 | `df -h` trên vps4 trước và sau một ngày log | Mức tăng dung lượng của `/var/log/central-bank` |

Chỉ ghi kết quả đã đo. Chưa chạy thì để trống.

---

## 7. Bộ kiểm thử nghiệm thu KT1–KT3

SV4 chạy và lưu bằng chứng; mọi thành viên cùng tham gia (yêu cầu của giảng viên).

- Bật timestamp dòng nhắc lệnh trên mọi máy:

```bash
echo 'export PS1="[\$(date -Is)] \u@\h:\w\$ "' >> ~/.bashrc && source ~/.bashrc
```

- Script kiểm thử lấy mật khẩu từ biến môi trường, không ghi mật khẩu vào file:

```bash
export APP_DB_PASS='<mật khẩu bank_app>'
export BACKUP_DB_PASS='<mật khẩu bank_backup>'
```

- Chạy và lưu log: `./run_all_tests.sh | tee test_results_$(date +%Y-%m-%dT%H-%M-%S).log`.
- Quy trình KT3.2 dùng **script sao lưu và phục hồi của SV3** trên vps3, không dùng bản sao lưu riêng trên vps4, để chỉ có một cơ chế sao lưu.

| Mã | Đầu vào | Thao tác | Kết quả mong đợi | Kết quả thực tế | Đánh giá | Bằng chứng |
|---|---|---|---|---|---|---|
| KT1.1 | Tài khoản khách hàng hợp lệ | Đăng nhập và gọi `/api/my-account` | HTTP 200, đúng số dư | `<điền>` | `<Đạt/Chưa đạt>` | `<ảnh hoặc log có timestamp>` |
| KT1.2 | Token của khách hàng | Gọi `/api/admin/audit-logs` | HTTP 403; có dòng `ACTION=RBAC` trạng thái bị từ chối trong log | `<điền>` | `<Đạt/Chưa đạt>` | `<điền>` |
| KT2.1 | vps1 | `nc -zv -w 3 10.10.10.30 5432` | Hết thời gian chờ | `<điền>` | `<Đạt/Chưa đạt>` | `<điền>` |
| KT2.2 | vps2 | `nc -zv -w 3 10.10.10.30 5432` | Kết nối thành công | `<điền>` | `<Đạt/Chưa đạt>` | `<điền>` |
| KT3.1 | Tài khoản hợp lệ, sai mật khẩu | Đăng nhập sai 3 lần | HTTP 401; log ở vps4 và `audit_logs` đều có sự kiện `LOGIN` trạng thái `FAILED` | `<điền>` | `<Đạt/Chưa đạt>` | `<ảnh mục 6.1 (a) và (b)>` |
| KT3.2 | CSDL `digital_bank` | Sao lưu, xóa dữ liệu bảng tài khoản, phục hồi, kiểm tra quyền | Dữ liệu nguyên trạng; `bank_app` không chạy được `DELETE` trên `audit_logs` và `DROP TABLE` | `<điền>` | `<Đạt/Chưa đạt>` | `<điền>` |

> Cảnh báo: bản cũ của tài liệu dùng tài khoản `bank_backup` để chạy `DELETE FROM accounts`. Theo `database/init_db.sql`, `bank_backup` là `SUPERUSER`, nên đây là kết quả của tài khoản có toàn quyền, không chứng minh được "quyền tối thiểu". Chứng minh quyền tối thiểu bằng tài khoản `bank_app`.

---

## 8. Câu hỏi phụ giảng viên hay hỏi

**Vì sao lưu IP người dùng?**
Xác định thiết bị thực hiện giao dịch và phát hiện đăng nhập bất thường. Trong hệ thống, IP lấy từ giá trị đầu của `X-Forwarded-For` do Nginx đặt, nên chỉ đáng tin khi mọi luồng đều qua Nginx của nhóm.

**Có hai luồng log, vì sao cần cả hai?**
Log thô là bằng chứng gốc, nhẹ và đọc được khi không có dashboard. Wazuh phân tích và cảnh báo nhưng nặng và dễ treo trên máy nhỏ. Chạy song song để hỏng một luồng vẫn còn luồng kia.

**Log nhiều thì có đầy đĩa không?**
Có logrotate cho cả vps2 (giữ 7 ngày) và vps4 (giữ 14 ngày). Chỉ mục `idx_audit_time` trên `event_time` có trong `database/init_db.sql`. Nhóm chưa đo tốc độ truy vấn nên không nêu con số.

**Lưu trữ lạnh theo tháng?**
Đây là biện pháp đề xuất, chưa triển khai. Khi trình bày phải ghi là "đề xuất".

---

## 9. Những chỗ đã sửa so với bản cũ

| Bản cũ | Bản mới | Lý do |
|---|---|---|
| Bảng sự kiện có `LOGIN/LOCKED` và `LOGOUT` | Dùng `LOGIN/DENIED`; bỏ `LOGOUT` | `backend/main.py` không ghi hai sự kiện đó (`/api/logout` chỉ xóa cookie) |
| Chuyển log bằng UDP (`@`) | TCP có hàng đợi đĩa | UDP có thể mất gói mà không báo |
| Nhận cả UDP và TCP 514 | Chỉ TCP 514 | Giảm mặt tấn công, khớp với việc đổi sang TCP |
| Không có logrotate | Có logrotate vps2 và vps4 | Đĩa vps4 dùng chung với Wazuh |
| Mật khẩu CSDL và IP công khai ghi trong tài liệu | Dùng biến môi trường và chỗ trống | Tránh đưa bí mật lên Git |
| Cam kết "dưới 10 mili giây" và "bất biến 100%" | Bỏ | Chưa đo; phạm vi quyền chỉ áp dụng cho `bank_app` |
| Có script sao lưu GPG riêng trên vps4 | Dùng script của SV3 | Chỉ giữ một cơ chế sao lưu |
| Chưa nói về quan hệ với SIEM | Ranh giới và đối soát ở mục 1, 2, 6 | Nhóm chạy song song hai luồng |

## 10. Sản phẩm SV4 cần nộp

1. Cấu hình rsyslog: file nhận trên vps4 và file chuyển trên vps2, kèm file logrotate của cả hai máy.
2. Script chạy kiểm thử KT1–KT3 và file log chạy thực tế có timestamp.
3. Kết quả các thử nghiệm S4–S6 (chỉ phần đã đo) và bảng đối soát ba nguồn ở mục 6.2.
4. Bảng kiểm thử 6 cột hoàn chỉnh kèm ảnh có timestamp.
5. Phiếu đóng góp cá nhân: file đã tạo, bằng chứng, lỗi đã tự xử lý (ví dụ phát hiện lỗi chèn log ở mục 5).
