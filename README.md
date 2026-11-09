# Đề 16: Thiết kế hạ tầng CNTT an toàn cho ngân hàng số

**Ngân hàng Số Mười Sáu** là mô hình ngân hàng số giả định. Nhóm dựng 5 máy ảo trên Google Cloud, tách thành các vùng mạng có kiểm soát, dùng dữ liệu giả và không xử lý giao dịch tài chính thật.

Nhật ký chạy thành **hai luồng song song, độc lập nhau** trên `vps4`: log thô (rsyslog và bảng `audit_logs`) làm bằng chứng gốc, và Wazuh SIEM giám sát cả 5 máy để phân tích và cảnh báo (xem mục 4).

> Điền các mục trong dấu `<...>` trước khi nộp.

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
