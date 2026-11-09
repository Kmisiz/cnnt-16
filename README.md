# Đề 16: Thiết kế hạ tầng CNTT an toàn cho ngân hàng số

**Ngân hàng Số Mười Sáu** là mô hình ngân hàng số giả định. Nhóm dựng 5 máy ảo trên Google Cloud, tách thành các vùng mạng có kiểm soát, dùng dữ liệu giả và không xử lý giao dịch tài chính thật.

Nhật ký chạy thành **hai luồng song song, độc lập nhau** trên `vps4`: log thô (rsyslog và bảng `audit_logs`) làm bằng chứng gốc, và Wazuh SIEM giám sát cả 5 máy để phân tích và cảnh báo (xem mục 4).

> Điền các mục trong dấu `<...>` trước khi nộp. Mục 11 là danh sách kiểm tra cuối cùng.

## 1. Thành viên và phân công

Nhóm 4 người. Mỗi người có sản phẩm kỹ thuật riêng và nộp phiếu đóng góp cá nhân theo mẫu của giảng viên.

| Họ tên | MSSV | Vai trò | Phụ trách |
|---|---|---|---|
| `<Họ tên>` | `<MSSV>` | Trưởng nhóm, SV1 | Kiến trúc và phân tích nguy cơ, hạ tầng GCP, Wazuh SIEM giám sát 5 máy (agent, FIM, rule, dashboard) và so sánh với rsyslog (phần mở rộng tự chọn), tích hợp, README |
| `<Họ tên>` | `<MSSV>` | SV2 | Phân vùng và lọc truy cập: UFW, luật VPC, Nginx trên vps0 và vps1 |
| `<Họ tên>` | `<MSSV>` | SV3 | Xác thực, dữ liệu, sao lưu: backend vps2, PostgreSQL vps3, sao lưu mã hóa và phục hồi |
| `<Họ tên>` | `<MSSV>` | SV4 | Kiểm thử chính sách và nhật ký: audit log ba tầng, luồng log thô rsyslog, chạy và lưu bằng chứng KT1–KT3 |

Ranh giới giữa luồng log thô (SV4) và SIEM (trưởng nhóm) nằm ở mục 4. Tài liệu nhiệm vụ của SV4: `NHIEM-VU-SV4-NHAT-KY-AN-NINH.md`.

## 2. Phạm vi và giả định

- Chỉ dùng dữ liệu giả lập. Không có giao dịch tài chính thật.
- Môi trường: Google Cloud, region `asia-southeast1`, zone `asia-southeast1-b`, mạng `bank-vpc` dải `10.10.10.0/24`.
- vps0–vps3: `e2-small` (2 vCPU, 2 GB RAM), Ubuntu 22.04 LTS, đĩa 20 GB.
- vps4 (chạy Wazuh all-in-one): 4 GB RAM, đĩa 50 GB, Ubuntu 22.04 LTS. Machine type: `e2-medium` (theo lịch sử commit nâng cấp RAM của vps4).
- vps2 và vps3 không có IP công khai, ra Internet qua Cloud NAT để cài gói.

## 3. Kiến trúc tóm tắt

```text
Khách hàng ──443──► vps0-web-public   10.10.10.5   Nginx, TLS, giao diện web        [agent]
                        │ 8080
                        ▼
                    vps1-dmz-fw       10.10.10.10  Nginx WAF, rate limit            [agent]
                        │ 8080
                        ▼
                    vps2-app-api      10.10.10.20  FastAPI, JWT, RBAC, audit log    [agent]
                        │ 5432
                        ▼
                    vps3-data-db      10.10.10.30  PostgreSQL                       [agent]

Quản trị ──SSH──► vps4-mgmt-log       10.10.10.40  Bastion, rsyslog tập trung,
                                                   Wazuh server + indexer + dashboard
```

| Máy | Vùng | IP nội bộ | IP công khai | Dịch vụ chính |
|---|---|---|---|---|
| `vps0-web-public` | Công khai | 10.10.10.5 | Có | Nginx, TLS (Let's Encrypt), giao diện web, Wazuh agent |
| `vps1-dmz-fw` | DMZ | 10.10.10.10 | `<có/không>` | Nginx WAF, giới hạn tần suất, Wazuh agent |
| `vps2-app-api` | Ứng dụng | 10.10.10.20 | Không | FastAPI (systemd `bank-app`), rsyslog chuyển log, Wazuh agent |
| `vps3-data-db` | Dữ liệu | 10.10.10.30 | Không | PostgreSQL, Wazuh agent |
| `vps4-mgmt-log` | Quản trị | 10.10.10.40 | Có | Bastion SSH, rsyslog tập trung, Wazuh all-in-one (agent cục bộ tự giám sát) |

**Luật tường lửa chính** (mặc định chặn mọi kết nối đến; bảng đầy đủ nằm trong tài liệu của SV2 và trưởng nhóm):

| Mã | Nguồn | Đích | Cổng | Hành động |
|---|---|---|---|---|
| FW-01 | Internet | vps0 | TCP 80, 443 | Cho phép |
| FW-02 | vps0 | vps1 | TCP 8080 | Cho phép |
| FW-03 | vps0 | vps2, vps3 | Tất cả | Chặn |
| FW-04 | vps1 | vps2 | TCP 8080 | Cho phép |
| FW-05 | vps1 | vps3 | TCP 5432 | Chặn |
| FW-06 | vps2 | vps3 | TCP 5432 | Cho phép |
| FW-07 | vps4 | vps3 | TCP 5432 | Cho phép |
| FW-08 | vps4 | vps0–vps3 | TCP 22 | Cho phép |
| FW-09 | vps0–vps3 | vps4 | TCP 514 | Cho phép (rsyslog, chỉ TCP) |
| FW-10 | vps0–vps3 | vps4 | TCP 1514 | Cho phép (Wazuh agent gửi sự kiện) |
| FW-11 | vps0–vps3 | vps4 | TCP 1515 | Cho phép (Wazuh agent đăng ký) |
| FW-12 | Quản trị viên | vps4 | Cổng dashboard Wazuh | Chỉ qua SSH tunnel, không mở ra Internet |

Hai lớp lọc: luật VPC của GCP (theo network tag) và UFW trong từng máy.

## 4. Giám sát và nhật ký song song

```text
vps2: FastAPI ─► /var/log/bank-app.log ─┬─ rsyslog ──TCP 514──► vps4: /var/log/central-bank/   (log thô)
                                        └─ Wazuh agent ─TCP 1514─► vps4: Wazuh ─► dashboard    (đã phân tích)
      audit() cũng ghi bảng audit_logs trên vps3
vps0, vps1, vps3: Wazuh agent ─TCP 1514─► vps4 (log hệ thống, FIM)
```

| | Luồng 1: log thô | Luồng 2: log đã phân tích |
|---|---|---|
| Công nghệ | rsyslog, bảng `audit_logs` | Wazuh SIEM |
| Giữ gì | Nguyên văn từng dòng log | Alert theo rule, FIM, tương quan sự kiện |
| Phạm vi | Log ứng dụng (vps2) và log xác thực | Cả 5 máy: log hệ thống, FIM, log ứng dụng |
| Dùng để | Bằng chứng gốc cho KT3, điều tra khi dashboard hỏng | Phát hiện và cảnh báo |
| Phụ trách | SV4 | Trưởng nhóm |

Nguyên tắc để hai luồng thật sự độc lập:
- Cùng đọc một file nguồn, không đọc của nhau. Hỏng một luồng không làm hỏng luồng kia.
- Luồng thô dùng TCP có hàng đợi đĩa, không dùng UDP vì UDP có thể mất gói mà không báo.
- Không bật bộ thu syslog của Wazuh trên vps4 vì cùng dùng cổng 514 với rsyslog.
- Không bật FIM trên thư mục log thô vì nó đổi liên tục và sẽ sinh alert liên tục.
- Đĩa vps4 dùng chung, nên cả hai luồng cần logrotate và theo dõi `df -h`.
- **Hợp đồng định dạng log:** decoder của Wazuh bám vào dòng `USER=… | ACTION=… | STATUS=… | IP=… | DETAILS=…` của `bank-app.log`. Đổi định dạng phải báo trưởng nhóm trước.
- Đối soát: sau mỗi bài thử, so số sự kiện ở log thô, `audit_logs` và Wazuh. Số liệu lệch là dữ liệu so sánh độ phủ (chi tiết ở tài liệu SV4).

## 5. Cấu trúc thư mục

Chỉ cố định các thư mục; tên file bên trong do từng thành viên tự đặt và tự push phần của mình. Mỗi thư mục có `README.md` mô tả mục đích và người phụ trách, thư mục con còn trống giữ bằng `.gitkeep`.

```text
cnnt-16/
├── README.md       File này
├── yeu-cau-goc/    Phiếu giao đề và hồ sơ chung của giảng viên
├── backend/        Mã nguồn API
├── frontend/       Giao diện web
├── database/       Lược đồ, dữ liệu mẫu, phân quyền CSDL
├── configs/        Cấu hình theo máy hoặc dịch vụ
│   ├── wazuh/      Decoder, rule, cấu hình FIM và log cho agent
│   ├── rsyslog/    Nhận và chuyển log tập trung, logrotate
│   └── ufw/        Đầu ra `ufw status verbose` từng máy
├── scripts/        Script cài đặt, sao lưu, phục hồi, chạy kiểm thử
├── docs/           Báo cáo, sơ đồ, bảng phân tích
│   └── dong-gop/   Phiếu đóng góp cá nhân, mỗi người một file
├── proofs/         Bằng chứng kiểm thử
│   ├── KT1/  KT2/  KT3/   Kiểm thử nghiệm thu
│   ├── SIEM/   Ảnh dashboard Wazuh
│   └── raw/    Log và dữ liệu thô
└── video/          Video demo, kịch bản, liên kết tải nếu file quá lớn cho Git
```

Quy ước chung:
- Mỗi thành viên chỉ push file thuộc phần mình phụ trách (bảng ở mục 1) để tránh xung đột.
- Không đưa lên Git: mật khẩu, khóa (`*.pem`, `*.key`), file `.env` thật, `wazuh-passwords.txt`, `wazuh-install-files.tar`.
- GitHub chặn file lớn hơn 100 MB. Video vượt mức này thì ghi liên kết tải trong `video/`.

## 6. Phiên bản phần mềm và công cụ

Điền bằng kết quả lệnh, không điền theo trí nhớ. Chạy trên từng máy và lưu kết quả vào `proofs/raw/`:

```bash
{ date -Is; lsb_release -ds; nginx -v 2>&1; python3 --version; psql --version; \
  ufw version | head -1; rsyslogd -v | head -1; \
  sudo /var/ossec/bin/wazuh-control info; } 2>&1
```

| Thành phần | Phiên bản | Máy | Ghi chú |
|---|---|---|---|
| Ubuntu | 22.04 LTS | cả 5 máy | |
| Nginx | `<điền>` | vps0, vps1 | |
| Python | `<điền>` | vps2 | |
| FastAPI, Uvicorn, Pydantic | 0.110.0, 0.28.0, 2.6.4 | vps2 | `backend/requirements.txt` |
| psycopg2-binary, PyJWT, passlib, bcrypt | 2.9.9, 2.8.0, 1.7.4, 4.0.1 | vps2 | `backend/requirements.txt` |
| PostgreSQL | `<điền>` | vps3 | Ghi cả kho gói nếu không dùng bản mặc định của Ubuntu |
| UFW | `<điền>` | cả 5 máy | |
| rsyslog | `<điền>` | vps2, vps4 | |
| Certbot (Let's Encrypt) | `<điền>` | vps0 | |
| Wazuh server, indexer, dashboard | `<điền>` | vps4 | Cài bằng `wazuh-install.sh -a` |
| Wazuh agent | `<điền>` | cả 5 máy | Không cao hơn phiên bản server |
| gcloud CLI | `<điền>` | máy quản trị | |

## 7. Dựng lại hệ thống từ đầu

Làm theo thứ tự. Sau mỗi bước chạy dòng "Kiểm tra" rồi mới sang bước kế tiếp. Lệnh chi tiết nằm trong tài liệu của người phụ trách.

| Bước | Máy | Việc | Người làm | Tài liệu | Kiểm tra |
|---|---|---|---|---|---|
| 0 | GCP | Tạo `bank-vpc`, subnet, Cloud NAT, luật VPC, 5 VM với IP nội bộ cố định | Trưởng nhóm | Tài liệu hạ tầng GCP của trưởng nhóm trong `docs/` | `gcloud compute instances list` thấy 5 máy `RUNNING` đúng IP |
| 1 | cả 5 | Bật timestamp dấu nhắc lệnh (lệnh dưới bảng) | Mọi người | | Dòng nhắc lệnh có giờ |
| 2 | vps3 | Cài PostgreSQL, chạy `database/init_db.sql`, áp `pg_hba.conf` | SV3 | `NHIEM-VU-SV3-XAC-THUC-DU-LIEU-SAO-LUU.md` | `\dt` liệt kê các bảng |
| 3 | vps3 | Sao lưu mã hóa và lịch chạy tự động | SV3 | cùng tài liệu SV3 | Có file sao lưu, restore thử thành công |
| 4 | vps2 | Cài ứng dụng từ `backend/`, tạo `/etc/bank-app.env` từ file mẫu, bật `bank-app` | SV3 | cùng tài liệu SV3 | `systemctl status bank-app` là `active`; `/var/log/bank-app.log` có dòng khởi động |
| 5 | vps1 | Nginx WAF, giới hạn tần suất | SV2 | `NHIEM-VU-SV2-PHAN-VUNG-FIREWALL-VA-WEB.md` | `nginx -t` thành công |
| 6 | vps0 | Nginx, giao diện `frontend/`, TLS | SV2 | cùng tài liệu SV2 | Trang đăng nhập mở được qua HTTPS |
| 7 | vps4, vps2 | rsyslog nhận (TCP 514) và chuyển log, logrotate | SV4 | `NHIEM-VU-SV4-NHAT-KY-AN-NINH.md` mục 4 | Dòng log từ vps2 xuất hiện trong `/var/log/central-bank/` |
| 8 | cả 5 | UFW theo vai trò, SSH mở trước khi bật | SV2 | tài liệu SV2 | `ufw status verbose` khớp bảng luật mục 3 |
| 9 | vps4 và agent | Wazuh SIEM (chi tiết dưới) | Trưởng nhóm | tài liệu Wazuh trong `docs/` | Dashboard thấy 5 agent `Active` |

```bash
echo 'export PS1="[\$(date -Is)] \u@\h:\w\$ "' >> ~/.bashrc && source ~/.bashrc
```

**Chi tiết bước 9 (Wazuh)**
1. Mở luật VPC và UFW cho TCP 1514 và 1515 từ `10.10.10.0/24` tới vps4, trên mạng `bank-vpc`. Không mở cổng dashboard ra Internet.
2. Cài all-in-one trên vps4: `curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh && sudo bash ./wazuh-install.sh -a`. Mật khẩu sinh ra nằm trong `wazuh-install-files.tar`.
3. Đổi mật khẩu `admin` bằng `wazuh-passwords-tool.sh -u admin -p '<mật khẩu mới>'`. Mật khẩu 8–64 ký tự, có chữ hoa, chữ thường, số và một ký hiệu trong `. * + ? -`. Xóa lệnh có mật khẩu khỏi lịch sử shell.
4. Truy cập dashboard qua SSH tunnel từ máy quản trị. Nếu gặp lỗi 500 sau khi đổi mật khẩu, xóa cookie của trang.
5. Cài agent trên cả 5 máy với `WAZUH_MANAGER='10.10.10.40'` (vps4 dùng agent cục bộ).
6. Áp cấu hình FIM và `<localfile>` cho `/var/log/bank-app.log` vào `ossec.conf` của từng agent. `realtime` chỉ hoạt động trên thư mục, nên tệp đơn như `/etc/passwd` khai báo qua thư mục cha kèm `restrict` và `recursion_level="0"`.
7. Chép decoder và rule tùy biến lên vps4, chạy `sudo /var/ossec/bin/wazuh-analysisd -t`, restart `wazuh-manager`, kiểm tra từng loại dòng log bằng `wazuh-logtest`.

## 8. Chạy kiểm thử nghiệm thu

Mọi thành viên cùng tham gia; SV4 chủ trì và lưu bằng chứng. Các cột "Kết quả thực tế" chỉ điền số đo thật, kèm thời gian. Mật khẩu truyền qua biến môi trường, không ghi vào script.

**Kiểm thử nghiệm thu (bắt buộc)**

| Mã | Đầu vào | Thao tác | Kết quả mong đợi | Kết quả thực tế | Đánh giá | Bằng chứng |
|---|---|---|---|---|---|---|
| KT1.1 | Tài khoản khách hàng hợp lệ | Đăng nhập, xem số dư | HTTP 200, đúng số dư | `<điền>` | `<Đạt/Chưa đạt>` | `proofs/KT1/` |
| KT1.2 | Token của khách hàng | Gọi API quản trị | HTTP 403; log có sự kiện `RBAC` bị từ chối | `<điền>` | `<Đạt/Chưa đạt>` | `proofs/KT1/` |
| KT2.1 | vps1 | `nc -zv -w 3 10.10.10.30 5432` | Hết thời gian chờ, bị chặn | `<điền>` | `<Đạt/Chưa đạt>` | `proofs/KT2/` |
| KT2.2 | vps2 | `nc -zv -w 3 10.10.10.30 5432` | Kết nối thành công | `<điền>` | `<Đạt/Chưa đạt>` | `proofs/KT2/` |
| KT3.1 | Tài khoản hợp lệ, sai mật khẩu | Đăng nhập sai 3 lần | HTTP 401; có sự kiện `LOGIN` trạng thái `FAILED` ở log thô vps4 và bảng `audit_logs` | `<điền>` | `<Đạt/Chưa đạt>` | `proofs/KT3/` |
| KT3.2 | CSDL `digital_bank` | Sao lưu, xóa dữ liệu bảng tài khoản, phục hồi, kiểm tra quyền | Dữ liệu nguyên trạng; tài khoản ứng dụng không xóa được `audit_logs` và không `DROP TABLE` | `<điền>` | `<Đạt/Chưa đạt>` | `proofs/KT3/` |

**Kịch bản SIEM (phần mở rộng, đối sánh với log thô)**

| Mã | Đầu vào | Thao tác | Kết quả mong đợi | Kết quả thực tế | Đánh giá | Bằng chứng |
|---|---|---|---|---|---|---|
| W1 | Thư mục web trên vps0 | Sửa `index.html`, tạo một tệp lạ | Alert FIM: rule 550 (tệp đổi), 554 (tệp mới) | `<điền, kèm độ trễ đo được>` | `<Đạt/Chưa đạt>` | `proofs/SIEM/` |
| W2 | `/etc/passwd` trên vps2 | Thêm một dòng user thử rồi dọn lại | Alert rule 550 cho `/etc/passwd` | `<điền>` | `<Đạt/Chưa đạt>` | `proofs/SIEM/` |
| W3a | SSH tới vps0 từ vps4 | ≥ 8 lần đăng nhập SSH với tên không tồn tại trong 120 giây | Rule 5710 từng lần, rồi rule 5712 | `<điền>` | `<Đạt/Chưa đạt>` | `proofs/SIEM/` |
| W3b | Đăng nhập API sai qua WAF | 3 lần sai trong 60 giây từ cùng một IP | Rule 100100 từng lần, rồi rule 100101 | `<điền>` | `<Đạt/Chưa đạt>` | `proofs/SIEM/` |

**Đối soát hai luồng:** sau mỗi bài đăng nhập sai N lần, ghi hiệu số đếm ở log thô, `audit_logs` và Wazuh. Cả ba phải bằng N; nếu lệch thì ghi lệch bao nhiêu và nguyên nhân.

**Độ tin cậy luồng thô:** thử cắt kết nối TCP 514 trong vài phút rồi mở lại, thử xoay vòng log, theo dõi dung lượng đĩa vps4. Chỉ ghi kết quả đã đo.

## 9. Quy định bằng chứng

- Bật timestamp dòng nhắc lệnh (bước 1 mục 7) trước khi chụp.
- Ảnh trình duyệt (dashboard, web) phải thấy thời gian hoặc kèm cửa sổ terminal chạy `date -Is`.
- Đặt tên `<mã-bài>_YYYY-MM-DDTHH-MM-SS.png`, dùng dấu `-` thay dấu `:` để hợp lệ trên Windows.
- Log và dữ liệu thô lưu ở `proofs/raw/`, ghi qua `| tee`.
- Ảnh chỉ chứa dữ liệu giả. Che mật khẩu, khóa, token và nội dung `wazuh-passwords.txt` trước khi lưu.

## 10. Video demo và nguồn tham khảo

**Video** (thư mục `video/`)
- Thời lượng 5–7 phút, quay rõ các tính năng chính và kết quả kiểm thử.
- Kịch bản theo mốc thời gian, ghi ai trình bày phần nào.
- GitHub chặn file lớn hơn 100 MB. Video vượt mức này thì ghi liên kết tải trong `video/`, hoặc dùng Git LFS (`<đã bật / không dùng>`).

**Nguồn tham khảo và phần có AI hỗ trợ** (giảng viên yêu cầu nêu rõ nguồn của mọi đoạn mã, cấu hình tham khảo và phần có AI)

| Phần | Nguồn hoặc công cụ | Người kiểm tra và hiểu rõ |
|---|---|---|
| Wazuh SIEM, FIM, decoder, rule | [Tài liệu Wazuh](https://documentation.wazuh.com/current/); AI hỗ trợ rà soát cú pháp | `<họ tên>` |
| rsyslog, logrotate | Tài liệu rsyslog; AI hỗ trợ viết cấu hình mẫu | `<họ tên>` |
| `<điền>` | `<điền>` | `<điền>` |

## 11. Danh sách kiểm tra trước khi nộp

- [ ] Đã điền toàn bộ `<...>` trong README, có họ tên thật và MSSV.
- [ ] Mỗi file được nhắc trong README tồn tại đúng đường dẫn.
- [ ] Không có mật khẩu, khóa, `wazuh-passwords.txt` hay `wazuh-install-files.tar` trong repo, kể cả trong lịch sử Git.
- [ ] Một người ngoài nhóm dựng lại thử theo mục 7 và chạy được mục 8.
- [ ] Mọi số đo trong bảng kiểm thử là số đo thật, có log gốc.
- [ ] Mỗi bài test có ảnh, log thô và giờ hợp lệ.
- [ ] Đủ phiếu đóng góp cá nhân cho từng thành viên.
- [ ] Có video demo hoặc liên kết tải.
- [ ] Đã ghi rõ phần AI hỗ trợ ở mục 10.
