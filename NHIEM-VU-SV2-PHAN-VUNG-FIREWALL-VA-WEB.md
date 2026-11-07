# TÀI LIỆU HƯỚNG DẪN NHIỆM VỤ SINH VIÊN 2 (SV2)
**Hạng mục phụ trách: Cấu hình phân vùng, lọc truy cập (Firewall), Chốt chặn WAF (`vps1`) & Web Server (`vps0`)**
*(Đề tài 16: Thiết kế hạ tầng CNTT an toàn cho ngân hàng số)*

---

## 1. TỔNG QUAN NHIỆM VỤ CỦA SV2

Theo phân công tại Phiếu giao đề 16 (*"SV2: Cấu hình phân vùng, lọc truy cập. Nộp file hoặc số liệu kèm giải thích phần thực hiện"*), bạn chịu trách nhiệm chính trên luồng cổng vào và toàn bộ chính sách tường lửa phân vùng của hệ thống 5 VPS:

```
[ Khách hàng Internet ]
          │
          │ HTTPS (Port 443)
          ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 1. vps0-web-public (10.10.10.5) — VÙNG WEB CÔNG KHAI (SV2 dựng)      │
│ • Chứa giao diện Web Ngân hàng số tĩnh (/var/www/html - Read-Only)   │
│ • Mã hóa HTTPS/TLS 1.3                                               │
│ • Cô lập: Chỉ biết duy nhất IP của vps1 (10.10.10.10:8080)           │
└───────────────────────────────────┬──────────────────────────────────┘
                                    │ HTTP (Port 8080)
                                    ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 2. vps1-dmz-fw (10.10.10.10) — CHỐT CHẶN TƯỜNG LỬA & WAF (SV2 dựng)  │
│ • Đứng chắn giữa Web (vps0) và App (vps2)                            │
│ • Lọc Layer 7 WAF (Chặn SQLi, XSS, Path Traversal, RCE) + Rate Limit │
│ • Chỉ chuyển tiếp request sạch sang vps2 (10.10.10.20:8080)          │
└───────────────────────────────────┬──────────────────────────────────┘
                                    │ HTTP (Port 8080)
                                    ▼
       [ vps2-app-api (10.10.10.20) ] ───► [ vps3-data-db (10.10.10.30) ]
       (SV2 áp đặt UFW chặn vps0)          (SV2 áp đặt UFW chặn vps0 & vps1)
```

### Bảng thông tin 5 VPS trong mạng nội bộ `10.10.10.0/24`:
* **`vps0-web-public` (`10.10.10.5`):** Máy chủ Web công khai (Có IP Public — Leader cung cấp).
* **`vps1-dmz-fw` (`10.10.10.10`):** Máy chủ Tường lửa trung gian / WAF Reverse Proxy Gateway.
* **`vps2-app-api` (`10.10.10.20`):** Máy chủ Ứng dụng Backend.
* **`vps3-data-db` (`10.10.10.30`):** Máy chủ Cơ sở dữ liệu PostgreSQL.
* **`vps4-mgmt-log` (`10.10.10.40`):** Máy chủ Quản trị Bastion & Log tập trung (Có IP Public — Leader cung cấp).

---

## 2. HƯỚNG DẪN KẾT NỐI SSH VÀ QUY TẮC BẮT BUỘC

### 2.1. Cách kết nối SSH từ máy tính cá nhân
* **Vào `vps0` hoặc `vps4` (Có IP Public):**
  ```bash
  ssh -i ~/.ssh/id_ed25519 <username_cua_ban>@<IP_PUBLIC>
  ```
* **Vào các máy nội bộ (`vps1`, `vps2`, `vps3`) thông qua Bastion `vps4`:**
  ```bash
  # Nhảy qua vps4 để vào vps1 (10.10.10.10)
  ssh -i ~/.ssh/id_ed25519 -J <username_cua_ban>@<IP_PUBLIC_VPS4> <username_cua_ban>@10.10.10.10

  # Tương tự nếu cần vào vps2 (.20) hoặc vps3 (.30) để bật Firewall UFW:
  ssh -i ~/.ssh/id_ed25519 -J <username_cua_ban>@<IP_PUBLIC_VPS4> <username_cua_ban>@10.10.10.20
  ssh -i ~/.ssh/id_ed25519 -J <username_cua_ban>@<IP_PUBLIC_VPS4> <username_cua_ban>@10.10.10.30
  ```

### 2.2. Quy tắc bắt buộc: Bật Timestamp trên Terminal
Ngay khi đăng nhập vào bất kỳ máy nào, bạn **bắt buộc** chạy lệnh sau để mọi câu lệnh và ảnh chụp màn hình đều có dấu thời gian (timestamp) chuẩn chấm điểm:
```bash
echo 'export PS1="[\$(date -Is)] \u@\h:\w\$ "' >> ~/.bashrc && source ~/.bashrc
```

---

## 3. TRIỂN KHAI CHI TIẾT TỪNG PHẦN

### PHẦN A: Dựng Máy chủ Web Công khai trên `vps0-web-public` (`10.10.10.5`)

#### Bước 1: Cài đặt Nginx & Tạo chứng chỉ SSL/TLS mã hóa HTTPS
SSH vào **`vps0-web-public` (`10.10.10.5`)** và chạy:
```bash
sudo apt update && sudo apt install -y nginx openssl curl jq netcat-openbsd

sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/bank.key \
  -out /etc/nginx/ssl/bank.crt \
  -subj "/C=VN/ST=Hanoi/L=Hanoi/O=DigitalBank/CN=digitalbank.local"

sudo chmod 600 /etc/nginx/ssl/bank.key
```

#### Bước 2: Tạo Giao diện Web Ngân hàng số & Khóa quyền Read-Only (Chống ghi Webshell khi RCE)
```bash
cat << 'EOF' | sudo tee /var/www/html/index.html
<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <title>Ngân Hàng Số An Toàn - Đề tài 16</title>
  <style>
    body { font-family: 'Segoe UI', Arial, sans-serif; max-width: 820px; margin: 30px auto; padding: 20px; background: #eef2f5; }
    .header { background: #003366; color: white; padding: 16px 22px; border-radius: 8px 8px 0 0; }
    .card { background: white; padding: 22px; border-radius: 0 0 8px 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin-bottom: 20px; }
    .form-group { margin-bottom: 12px; }
    label { display: block; font-weight: bold; margin-bottom: 5px; color: #333; }
    input { width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; }
    .btn-group { display: flex; gap: 10px; margin-top: 15px; flex-wrap: wrap; }
    button { padding: 10px 16px; border: none; border-radius: 4px; cursor: pointer; font-weight: bold; }
    .btn-primary { background: #0052cc; color: white; }
    .btn-success { background: #00875a; color: white; }
    .btn-danger { background: #de350b; color: white; }
    pre { background: #1a1a1a; color: #00ff66; padding: 15px; border-radius: 6px; overflow-x: auto; font-family: Consolas, monospace; }
    .badge { display: inline-block; padding: 4px 8px; border-radius: 4px; font-size: 12px; font-weight: bold; }
  </style>
</head>
<body>
  <div class="header">
    <h2>🏦 CỔNG NGÂN HÀNG SỐ AN TOÀN (MÔ HÌNH 5 VPS CÔ LẬP)</h2>
    <small>Luồng bảo mật: Web (vps0: .5) &rarr; WAF Firewall (vps1: .10) &rarr; App API (vps2: .20) &rarr; DB (vps3: .30)</small>
  </div>

  <div class="card">
    <h3>1. Đăng nhập Xác thực (JWT Authentication)</h3>
    <div class="form-group">
      <label>Tài khoản (Username):</label>
      <input id="username" value="khachhang01" placeholder="khachhang01 hoặc admin01">
    </div>
    <div class="form-group">
      <label>Mật khẩu (Password):</label>
      <input id="password" type="password" value="KhachHang@123">
    </div>
    <button class="btn-primary" onclick="login()">Đăng nhập</button>
    <span id="login-status" style="margin-left: 10px;"></span>

    <hr style="margin: 20px 0; border: 0; border-top: 1px solid #eee;">

    <h3>2. Nghiệp vụ & Kiểm tra Phân quyền theo Vai trò (RBAC - KT1)</h3>
    <div class="btn-group">
      <button class="btn-success" onclick="callApi('/api/my-account')">Xem Số Dư Cá Nhân (Quyền Customer)</button>
      <button class="btn-danger" onclick="callApi('/api/admin/audit-logs')">Xem Nhật Ký An Ninh (Chỉ Quyền Admin)</button>
    </div>

    <h3 style="margin-top: 25px;">3. Phản hồi từ Hệ thống (Kèm Timestamp xác thực):</h3>
    <pre id="output">// Chưa có thao tác...</pre>
  </div>

  <script>
    let token = "";
    async function login() {
      const u = document.getElementById('username').value;
      const p = document.getElementById('password').value;
      document.getElementById('output').textContent = "Đang gửi yêu cầu qua cổng tường lửa WAF (vps1)...";
      try {
        const res = await fetch('/api/login', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({username: u, password: p})
        });
        const data = await res.json();
        const ts = new Date().toISOString();
        if (res.ok) {
          token = data.access_token;
          document.getElementById('login-status').innerHTML = `<span class="badge" style="background:#e3fcef;color:#006644;">Đã xác thực: ${data.role} (${data.full_name})</span>`;
        } else {
          document.getElementById('login-status').innerHTML = `<span class="badge" style="background:#ffebe6;color:#bf2600;">Thất bại (HTTP ${res.status})</span>`;
        }
        document.getElementById('output').textContent = `[${ts}] HTTP ${res.status}\n` + JSON.stringify(data, null, 2);
      } catch (err) {
        document.getElementById('output').textContent = `[${new Date().toISOString()}] Lỗi: ` + err;
      }
    }

    async function callApi(endpoint) {
      if (!token) {
        alert("Vui lòng đăng nhập trước!");
        return;
      }
      try {
        const res = await fetch(endpoint, {
          headers: {'Authorization': 'Bearer ' + token}
        });
        const data = await res.json();
        const ts = new Date().toISOString();
        document.getElementById('output').textContent = `[${ts}] GET ${endpoint} -> HTTP ${res.status}\n` + JSON.stringify(data, null, 2);
      } catch (err) {
        document.getElementById('output').textContent = `[${new Date().toISOString()}] Lỗi: ` + err;
      }
    }
  </script>
</body>
</html>
EOF

# Khóa quyền Read-Only thư mục Web để chống tải Webshell nếu Web bị RCE
sudo chown -R root:root /var/www/html
sudo chmod -R 755 /var/www/html
sudo chmod 644 /var/www/html/index.html
```

#### Bước 3: Cấu hình Nginx trên `vps0` chỉ chuyển tiếp về duy nhất `vps1` (`10.10.10.10:8080`)
```bash
cat << 'EOF' | sudo tee /etc/nginx/sites-available/default
server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name _;

    ssl_certificate /etc/nginx/ssl/bank.crt;
    ssl_certificate_key /etc/nginx/ssl/bank.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    client_max_body_size 1M;

    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    # CHỈ BIẾT DUY NHẤT IP CỦA CHỐT CHẶN TƯỜNG LỬA vps1 (10.10.10.10)
    location /api/ {
        proxy_pass http://10.10.10.10:8080/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

sudo nginx -t && sudo systemctl restart nginx
```

---

### PHẦN B: Dựng Chốt chặn Tường lửa Ứng dụng (WAF & Rate Limit Gateway) trên `vps1-dmz-fw` (`10.10.10.10`)

SSH vào **`vps1-dmz-fw` (`10.10.10.10`)** và thiết lập bộ lọc kiểm duyệt mọi request từ `vps0` gửi sang trước khi cho phép vào `vps2`:

```bash
sudo apt update && sudo apt install -y nginx curl jq netcat-openbsd

cat << 'EOF' | sudo tee /etc/nginx/sites-available/default
# 1. Rate Limiting chống Brute-force mật khẩu: Tối đa 5 request đăng nhập / phút / IP
limit_req_zone $http_x_forwarded_for zone=waf_login_limit:10m rate=5r/m;

server {
    listen 10.10.10.10:8080;
    server_name _;

    # 2. Luật lọc WAF Layer 7: Chặn SQL Injection, XSS, Path Traversal, RCE
    if ($query_string ~* "(union.*select|select.*from|insert.*into|drop.*table|;--|<script>|%3Cscript%3E|\.\./|/etc/passwd)") {
        return 403 '{"detail": "WAF Blocked: Phat hien dau hieu tan cong trong Query String!"}';
    }
    if ($request_uri ~* "(\.\./|\.\.\\|%2e%2e|cmd=|exec=|/bin/sh|/bin/bash)") {
        return 403 '{"detail": "WAF Blocked: Phat hien tan cong Path Traversal / RCE!"}';
    }

    # 3. Kiểm soát luồng đăng nhập với Rate Limit
    location /api/login {
        limit_req zone=waf_login_limit burst=3 nodelay;
        proxy_pass http://10.10.10.20:8080/api/login;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # 4. Chuyển tiếp các request hợp lệ sang vps2-app-api (10.10.10.20:8080)
    location /api/ {
        proxy_pass http://10.10.10.20:8080/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

sudo nginx -t && sudo systemctl restart nginx
```

---

### PHẦN C: CẤU HÌNH PHÂN VÙNG & LỌC TRUY CẬP (UFW DEFAULT DENY) TRÊN CÁC MÁY

Theo đúng yêu cầu **B3** (*"áp dụng chính sách mặc định hạn chế, chỉ mở luồng cần thiết"*), SV2 thiết lập tường lửa UFW trên từng phân vùng:

#### 1. Trên `vps0-web-public` (`10.10.10.5` — Vùng Web Công khai)
```bash
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH Management'
sudo ufw allow 80/tcp comment 'HTTP Public'
sudo ufw allow 443/tcp comment 'HTTPS Public'
sudo ufw --force enable
sudo ufw status verbose
```

#### 2. Trên `vps1-dmz-fw` (`10.10.10.10` — Vùng Chốt chặn DMZ Firewall)
```bash
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
# Chặn tuyệt đối vps0 SSH sang vps1
sudo ufw deny from 10.10.10.5 to any port 22 proto tcp comment 'DENY SSH from Web vps0'
sudo ufw allow from 10.10.10.40 to any port 22 proto tcp comment 'Allow SSH from Bastion vps4'
sudo ufw allow 22/tcp comment 'SSH Fallback'
# Chỉ mở cổng 8080 cho duy nhất vps0 (10.10.10.5)
sudo ufw allow from 10.10.10.5 to any port 8080 proto tcp comment 'Allow ONLY vps0 Web to WAF'
sudo ufw --force enable
sudo ufw status verbose
```

#### 3. Trên `vps2-app-api` (`10.10.10.20` — Vùng Ứng dụng)
```bash
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 10.10.10.40 to any port 22 proto tcp comment 'Allow SSH from Bastion vps4'
sudo ufw allow 22/tcp comment 'SSH Fallback'
# Chặn tuyệt đối Web vps0 (10.10.10.5) đi tắt vào vps2
sudo ufw deny from 10.10.10.5 to any comment 'DENY direct access from Web vps0'
# Chỉ nhận request cổng 8080 từ chốt chặn WAF vps1 (10.10.10.10)
sudo ufw allow from 10.10.10.10 to any port 8080 proto tcp comment 'Allow ONLY WAF vps1 to App'
sudo ufw --force enable
sudo ufw status verbose
```

#### 4. Trên `vps3-data-db` (`10.10.10.30` — Vùng Dữ liệu — Trọng tâm KT2)
```bash
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 10.10.10.40 to any port 22 proto tcp comment 'Allow SSH from Bastion vps4'
sudo ufw allow 22/tcp comment 'SSH Fallback'
# Chặn tuyệt đối vps0 (Web) và vps1 (DMZ) kết nối trực tiếp vào cổng DB 5432 (Đáp ứng KT2)
sudo ufw deny from 10.10.10.5 to any port 5432 proto tcp comment 'DENY Web vps0 direct to DB - KT2'
sudo ufw deny from 10.10.10.10 to any port 5432 proto tcp comment 'DENY DMZ vps1 direct to DB - KT2'
# Chỉ mở cổng 5432 cho vps2 (App: .20) và vps4 (Backup: .40)
sudo ufw allow from 10.10.10.20 to any port 5432 proto tcp comment 'Allow App vps2 to PostgreSQL'
sudo ufw allow from 10.10.10.40 to any port 5432 proto tcp comment 'Allow Mgmt vps4 to PostgreSQL'
sudo ufw --force enable
sudo ufw status verbose
```

---

## 4. KIỂM THỬ LỌC TRUY CẬP & THU THẬP MINH CHỨNG (CÓ TIMESTAMP)

SV2 chạy các lệnh sau và chụp ảnh màn hình (đã có timestamp) để nộp vào báo cáo:

1. **Đứng trên `vps0-web-public` (`10.10.10.5`) — Kiểm thử cô lập Web Server (KT2):**
   ```bash
   echo "=== [KT2 - SV2] KIEM TRA CO LAP TU WEB SERVER (vps0: 10.10.10.5) ==="
   # 1. Thử chọc thẳng vào DB vps3 (5432) -> KỲ VỌNG: Connection timed out
   nc -zv -w 3 10.10.10.30 5432
   # 2. Thử đi tắt vào App vps2 (8080) -> KỲ VỌNG: Connection timed out
   nc -zv -w 3 10.10.10.20 8080
   # 3. Thử SSH sang vps1 (22) -> KỲ VỌNG: Connection timed out / refused
   nc -zv -w 3 10.10.10.10 22
   # 4. Kết nối đúng luồng duy nhất qua cổng WAF vps1 (8080) -> KỲ VỌNG: Succeeded!
   nc -zv -w 3 10.10.10.10 8080
   ```

2. **Đứng trên `vps1-dmz-fw` (`10.10.10.10`) — Kiểm thử chặn vùng DMZ vào DB (KT2):**
   ```bash
   echo "=== [KT2 - SV2] KIEM TRA CHAN KET NOI TU DMZ (vps1) VAO DB (vps3:5432) ==="
   nc -zv -w 3 10.10.10.30 5432
   ```

3. **Kiểm thử WAF chặn tấn công SQL Injection & Path Traversal:**
   ```bash
   curl -sk -i "https://10.10.10.5/api/my-account?id=1%20UNION%20SELECT%20*--&file=../../etc/passwd"
   ```

---

## 5. DANH MỤC SẢN PHẨM KỸ THUẬT CÁ NHÂN SV2 CẦN NỘP
1. File cấu hình Nginx trên `vps0` (`/etc/nginx/sites-available/default`) và giao diện `/var/www/html/index.html`.
2. File cấu hình WAF & Rate Limiting trên `vps1` (`/etc/nginx/sites-available/default`).
3. Tập hợp kết quả `sudo ufw status numbered` trên các phân vùng.
4. Bộ ảnh chụp màn hình có timestamp chứng minh kết quả kiểm thử **KT2** và **WAF Blocked**.
