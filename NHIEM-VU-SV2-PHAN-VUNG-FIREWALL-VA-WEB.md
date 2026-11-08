# HƯỚNG DẪN TRIỂN KHAI CHI TIẾT: THÀNH VIÊN 2 (HIẾU - SV2)
**Đề tài 16: Thiết kế hạ tầng CNTT an toàn cho Ngân hàng số (Mười Sáu Bank)**  
**Phụ trách:** Phân vùng mạng (Network Segmentation), Host-based Firewall (UFW), DMZ WAF Gateway (`vps1-dmz-fw`) và Web Server Giao diện Ngân hàng số (`vps0-web-public`).

---

## 1. SƠ ĐỒ KIẾN TRÚC MẠNG & VAI TRÒ CỦA SV2

Hệ thống được triển khai trên Google Cloud Platform (GCP) trong mạng VPC `bank-vpc` (`10.10.10.0/24` - vùng `asia-southeast1-b`):

| Máy chủ | IP Nội bộ | External IP (Public) | Vai trò trong kiến trúc |
| :--- | :--- | :--- | :--- |
| **`vps0-web-public`** | `10.10.10.5` | **`34.124.217.241`** | **Public Web Tier:** Chạy Nginx HTTPS (TLS 1.3), phục vụ giao diện Web tĩnh Mười Sáu Bank (`/var/www/muoisau`). Người dùng Internet truy cập tại: **`https://34.124.217.241`**. |
| **`vps1-dmz-fw`** | `10.10.10.10` | `34.87.91.248` (DMZ) | **DMZ Firewall & WAF Tier:** Tường lửa trung gian + Nginx Layer 7 WAF & Rate Limiting (`5r/m` chống Brute-force `/api/login`), kiểm soát luồng dữ liệu từ `vps0` vào `vps2`. |
| **`vps2-app-api`** | `10.10.10.20` | Không (None) | **Application Tier (SV3):** Chạy Core Banking API (FastAPI cổng `8080`). Chỉ nhận kết nối từ `vps1` (`10.10.10.10`). |
| **`vps3-data-db`** | `10.10.10.30` | Không (None) | **Data Tier (SV3):** Chạy PostgreSQL 16 (cổng `5432`). Chỉ nhận kết nối từ `vps2` (`10.10.10.20`). |
| **`vps4-mgmt-log`** | `10.10.10.40` | **`136.85.99.236`** | **Management & SIEM Tier (SV1 & SV4):** Bastion Host duy nhất được phép SSH (`22/tcp`) vào các máy nội bộ và thu thập Syslog tập trung (`514/udp`). |

---

### 1.1. Lệnh PowerShell dành cho Hiếu (kết nối từ máy tính ở nhà)
Hiếu mở **PowerShell** trên máy tính cá nhân ở nhà và copy paste các lệnh sau:
- **Truy cập thẳng vào máy Web Public (`vps0-web-public`):**
  ```powershell
  ssh hieu@34.124.217.241
  ```
  *(Hoặc nhảy qua Bastion Host: `ssh -J hieu@136.85.99.236 hieu@10.10.10.5`)*
- **Truy cập vào máy DMZ WAF (`vps1-dmz-fw`):**
  ```powershell
  ssh -J hieu@136.85.99.236 hieu@10.10.10.10
  ```

---

## 2. THIẾT LẬP FIREWALL (UFW) TRÊN CÁC PHÂN VÙNG

> **Lưu ý sống còn trước khi bật UFW:** Trên mọi máy chủ, phải mở quyền SSH từ `vps4-mgmt-log` (`10.10.10.40`) trước khi gõ `ufw enable` để không bị khóa kết nối điều khiển.

### 2.1. Cấu hình UFW trên `vps0-web-public` (`10.10.10.5`)
SSH vào `vps0-web-public` và chạy:
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Cho phep nguoi dung Internet truy cap Web HTTP (80) va HTTPS (443)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Chi cho phep SSH quan tri tu VPS4 (Bastion Host) va IAP/Admin khi can
sudo ufw allow from 10.10.10.40 to any port 22 proto tcp

sudo ufw --force enable
sudo ufw status verbose
```

### 2.2. Cấu hình UFW trên `vps1-dmz-fw` (`10.10.10.10`)
Từ `vps4-mgmt-log`, SSH sang `vps1-dmz-fw` (`ssh 10.10.10.10`) và chạy:
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 1. Quan tri SSH tu Bastion Host (VPS4)
sudo ufw allow from 10.10.10.40 to any port 22 proto tcp

# 2. Chi cho phep VPS0 (10.10.10.5) va VPS4 (test) goi vao cong WAF 8080
sudo ufw allow from 10.10.10.5 to any port 8080 proto tcp
sudo ufw allow from 10.10.10.40 to any port 8080 proto tcp

sudo ufw --force enable
sudo ufw status verbose
```

### 2.3. Phối hợp kiểm tra UFW trên `vps2-app-api` (`10.10.10.20`) và `vps3-data-db` (`10.10.10.30`)
Đảm bảo các quy tắc cô lập vùng trong đã được bật:
- **Trên `vps2-app-api` (`10.10.10.20`):**
  ```bash
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow from 10.10.10.40 to any port 22 proto tcp
  sudo ufw allow from 10.10.10.10 to any port 8080 proto tcp
  sudo ufw --force enable
  ```
- **Trên `vps3-data-db` (`10.10.10.30`):**
  ```bash
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow from 10.10.10.40 to any port 22 proto tcp
  sudo ufw allow from 10.10.10.20 to any port 5432 proto tcp
  sudo ufw --force enable
  ```

---

## 3. TRIỂN KHAI DMZ WAF & RATE-LIMITING GATEWAY TRÊN `vps1-dmz-fw` (`10.10.10.10`)

Thực hiện trên máy **`vps1-dmz-fw` (`10.10.10.10`)**:

### Bước 1: Cài đặt Nginx và tải mã nguồn từ GitHub
```bash
sudo apt update && sudo apt install -y nginx git
cd ~
rm -rf cnnt-16
git clone https://github.com/Kmisiz/cnnt-16.git
```

### Bước 2: Kích hoạt cấu hình WAF (`vps1-waf.conf`)
File cấu hình `cnnt-16/frontend/nginx/vps1-waf.conf` đã được thiết lập sẵn:
- **Rate Limiting:** Chống Brute-force `/api/login` (`5 requests/phút` trên mỗi IP thật của khách hàng qua header `X-Real-IP`) và chống DoS `/api/*` (`10 requests/giây`).
- **Layer 7 WAF:** Chặn các mẫu tấn công SQL Injection (`UNION SELECT`, `DROP TABLE`...), XSS (`<script>`), Path Traversal (`../`) và các công cụ quét tự động (`sqlmap`, `nikto`, `nmap`).
- **Forward Auth & Cookie:** Chuyển tiếp nguyên vẹn `Cookie`, `X-Real-IP`, `X-Original-URI` về `10.10.10.20:8080`.

Chạy lệnh áp dụng cấu hình:
```bash
sudo cp ~/cnnt-16/frontend/nginx/vps1-waf.conf /etc/nginx/sites-available/muoisau-waf.conf
sudo ln -sf /etc/nginx/sites-available/muoisau-waf.conf /etc/nginx/sites-enabled/muoisau-waf.conf
sudo rm -f /etc/nginx/sites-enabled/default

sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx
```

---

## 4. TRIỂN KHAI WEB SERVER GIAO DIỆN NGÂN HÀNG SỐ TRÊN `vps0-web-public` (`10.10.10.5`)

Thực hiện trên máy **`vps0-web-public` (`10.10.10.5`)**:

### Bước 1: Cài đặt Nginx, OpenSSL và tải mã nguồn từ GitHub
```bash
sudo apt update && sudo apt install -y nginx openssl git
cd ~
rm -rf cnnt-16
git clone https://github.com/Kmisiz/cnnt-16.git
```

### Bước 2: Tạo chứng chỉ số SSL/TLS (Hỗ trợ TLS 1.2 / TLS 1.3)
```bash
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/bank.key \
  -out /etc/nginx/ssl/bank.crt \
  -subj "/C=VN/ST=Hanoi/L=Hanoi/O=MuoiSauBank/OU=ITSecurity/CN=muoisaubank.vn"
sudo chmod 600 /etc/nginx/ssl/bank.key
```

### Bước 3: Sao chép mã nguồn Giao diện Web vào `/var/www/muoisau`
Bộ giao diện chuẩn trong `cnnt-16/frontend/` bao gồm:
- `index.html`, `assets/css/style.css`, `assets/js/app.js`: Giao diện Internet Banking dành cho khách hàng cá nhân.
- `admin/index.html`, `admin/admin.js`: Phân hệ Quản trị & Vận hành nội bộ (chỉ hiển thị khi có phiên đăng nhập của `admin` hoặc `teller`).

Chạy lệnh triển khai:
```bash
sudo mkdir -p /var/www/muoisau
sudo rm -rf /var/www/muoisau/*
sudo cp -r ~/cnnt-16/frontend/index.html ~/cnnt-16/frontend/assets ~/cnnt-16/frontend/admin /var/www/muoisau/
sudo chown -R www-data:www-data /var/www/muoisau
sudo chmod -R 755 /var/www/muoisau
```

### Bước 4: Kích hoạt cấu hình Nginx HTTPS + Bảo vệ `/admin` bằng `404 Not Found`
File `cnnt-16/frontend/nginx/vps0-muoisau.conf` đã tích hợp sẵn:
1. Chuyển hướng toàn bộ HTTP (`80`) sang HTTPS (`443`) với TLS 1.2/1.3 và các Security Headers (`HSTS`, `CSP`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`).
2. Bảo vệ đường dẫn `/admin` bằng `auth_request /_internal/staff-check`:
   - Khi người dùng chưa đăng nhập hoặc đăng nhập bằng tài khoản `customer` cố truy cập `https://<IP_PUBLIC_VPS0>/admin`, Nginx nhận mã `401/403` từ hàm kiểm tra nội bộ và ánh xạ qua `error_page 401 403 = @not_found; return 404;` -> **Trả về trang `404 Not Found` mặc định của Nginx**.
   - Khi đăng nhập bằng `admin` hoặc `teller`, cookie `kn_session` hợp lệ -> Nginx trả mã `200` và mở giao diện `/admin/`.

Chạy lệnh áp dụng:
```bash
sudo cp ~/cnnt-16/frontend/nginx/vps0-muoisau.conf /etc/nginx/sites-available/muoisau.conf
sudo ln -sf /etc/nginx/sites-available/muoisau.conf /etc/nginx/sites-enabled/muoisau.conf
sudo rm -f /etc/nginx/sites-enabled/default

sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx
```

---

## 5. DANH MỤC KIỂM THỬ & CHỤP ẢNH BÁO CÁO DÀNH CHO SV2

Sau khi triển khai xong, Hiếu (SV2) thực hiện các lệnh kiểm chứng sau và chụp ảnh màn hình gửi vào báo cáo nhóm:

1. **Chứng minh cô lập mạng (KT2.2):**
   - Đứng trên `vps0-web-public` (`10.10.10.5`), thử kết nối thẳng vào App (`10.10.10.20:8080`) và DB (`10.10.10.30:5432`):
     ```bash
     curl -m 3 http://10.10.10.20:8080/api/health
     nc -zv -w 3 10.10.10.30 5432
     ```
     -> **Kết quả mong đợi:** Cả 2 lệnh đều bị `Connection timed out` (do UFW chặn hoàn toàn kết nối tắt từ `vps0` sang `vps2` và `vps3`).

2. **Chứng minh ẩn trang `/admin` bằng lỗi `404 Not Found`:**
   - Mở trình duyệt ẩn danh (chưa đăng nhập) hoặc đăng nhập tài khoản khách hàng `user1` (`User1@123`), sau đó gõ địa chỉ:  
     👉 **`https://34.124.217.241/admin`**
   - **Kết quả mong đợi:** Trình duyệt hiển thị trang trắng **`404 Not Found - nginx`** giống hệt như khi gõ một đường dẫn không tồn tại (`/trang-khong-ton-tai`).

3. **Chứng minh WAF chặn SQL Injection & Rate Limiting chặn Brute-force (KT2.1):**
   ```bash
   # Test WAF chan SQLi truc tiep qua IP Public cua vps0:
   curl -k -i "https://34.124.217.241/api/accounts?id=1%20UNION%20SELECT%20*--+"

   # Test Rate Limiting chan Brute-force (>5 lan/phut) tren /api/login:
   for i in {1..8}; do
     curl -k -s -o /dev/null -w "Lan $i: HTTP %{http_code}\n" \
       -X POST https://34.124.217.241/api/login \
       -H "Content-Type: application/json" \
       -d '{"username":"admin","password":"sai_mat_khau"}'
   done
   ```
   -> **Kết quả mong đợi:** Lệnh SQLi trả về `HTTP/2 403` (`WAF Blocked`), và vòng lặp đăng nhập sai từ lần thứ 6–8 trở đi trả về `HTTP/2 429` (`Too Many Requests`).
