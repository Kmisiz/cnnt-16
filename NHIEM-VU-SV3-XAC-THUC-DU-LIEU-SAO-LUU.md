# TÀI LIỆU HƯỚNG DẪN NHIỆM VỤ SINH VIÊN 3 (SV3)
**Hạng mục phụ trách: Dựng Xác thực & Phân quyền (`vps2`), Cơ sở dữ liệu (`vps3`) và Sao lưu & Phục hồi mã hóa**
*(Đề tài 16: Thiết kế hạ tầng CNTT an toàn cho ngân hàng số)*

---

## 1. TỔNG QUAN NHIỆM VỤ CỦA SV3

Theo phân công tại Phiếu giao đề 16 (*"SV3: Dựng xác thực, dữ liệu và sao lưu. Nộp file hoặc số liệu kèm giải thích phần thực hiện"*), bạn chịu trách nhiệm xây dựng lõi nghiệp vụ và dữ liệu của Ngân hàng số:
1. **Dựng Vùng Dữ liệu (`vps3-data-db` — `10.10.10.30`):** Cài đặt PostgreSQL 16, thiết kế lược đồ CSDL (`users`, `accounts`, `audit_logs`), phân quyền tài khoản CSDL theo nguyên tắc **Quyền tối thiểu (Least Privilege — cấm `DROP/TRUNCATE`)** và giới hạn xác thực trong `pg_hba.conf`.
2. **Dựng Vùng Ứng dụng (`vps2-app-api` — `10.10.10.20`):** Lập trình Backend FastAPI thực hiện băm mật khẩu (`bcrypt`), cấp phát **JWT (`HS256`)**, kiểm tra **Phân quyền theo vai trò (RBAC: `customer`, `teller`, `admin`)** và ghi nhật ký kiểm toán (Audit Log).
3. **Dựng Cơ chế Sao lưu & Phục hồi (`backup_db.sh` & `restore_db.sh`):** Xuất dữ liệu tự động bằng `pg_dump`, mã hóa bản sao lưu bằng chuẩn **`AES-256 (GPG)`** và khôi phục dữ liệu mẫu khi có sự cố (phục vụ nghiệm thu **KT1** và **KT3**).

*(Lưu ý: Phần cấu hình tường lửa mạng UFW giữa các máy do bạn SV2 phụ trách).*

---

## 2. HƯỚNG DẪN KẾT NỐI SSH VÀ QUY TẮC TIMESTAMP BẮT BUỘC

### 2.1. Cách kết nối SSH vào `vps2` và `vps3` (Qua Bastion Host `vps4`)
Vì `vps2` (`10.10.10.20`) và `vps3` (`10.10.10.30`) nằm hoàn toàn trong mạng nội bộ (không có IP Public để bảo mật), bạn kết nối từ máy tính cá nhân nhảy qua **Bastion Host `vps4`** bằng cờ `-J`:

```bash
# 1. Kết nối thẳng vào vps3-data-db (10.10.10.30)
ssh -i ~/.ssh/id_ed25519 -J <username_cua_ban>@<IP_PUBLIC_VPS4> <username_cua_ban>@10.10.10.30

# 2. Kết nối thẳng vào vps2-app-api (10.10.10.20)
ssh -i ~/.ssh/id_ed25519 -J <username_cua_ban>@<IP_PUBLIC_VPS4> <username_cua_ban>@10.10.10.20

# 3. Kết nối vào vps4-mgmt-log (10.10.10.40) để đặt script Backup/Restore
ssh -i ~/.ssh/id_ed25519 <username_cua_ban>@<IP_PUBLIC_VPS4>
```

### 2.2. Quy tắc bắt buộc: Bật Timestamp trên Terminal
Ngay khi SSH vào bất kỳ máy nào, hãy chạy lệnh sau để dòng nhắc lệnh luôn in kèm ngày giờ chuẩn ISO-8601 (bắt buộc khi chụp ảnh bằng chứng):
```bash
echo 'export PS1="[\$(date -Is)] \u@\h:\w\$ "' >> ~/.bashrc && source ~/.bashrc
```

---

## 3. TRIỂN KHAI CHI TIẾT TỪNG PHẦN

### PHẦN A: Dựng Cơ sở dữ liệu & Phân quyền tối thiểu trên `vps3-data-db` (`10.10.10.30`)

#### Bước 1: Cài đặt PostgreSQL 16 & Khởi tạo CSDL Ngân hàng số (`digital_bank`)
SSH vào **`vps3-data-db` (`10.10.10.30`)** và chạy:

```bash
sudo apt update && sudo apt install -y postgresql postgresql-contrib gnupg

sudo -u postgres psql << 'EOF'
-- 1. Tạo Database Ngân hàng số
CREATE DATABASE digital_bank;
\c digital_bank

-- 2. Tạo bảng Người dùng (Users) lưu mật khẩu băm Bcrypt và vai trò RBAC
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('customer', 'teller', 'admin')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Tạo bảng Tài khoản ngân hàng giả định (Accounts)
CREATE TABLE accounts (
    account_no VARCHAR(20) PRIMARY KEY,
    user_id INT REFERENCES users(id),
    balance NUMERIC(15, 2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(10) DEFAULT 'VND',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Tạo bảng Nhật ký an ninh & Kiểm toán (Audit Logs)
CREATE TABLE audit_logs (
    id SERIAL PRIMARY KEY,
    event_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    username VARCHAR(50),
    action VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL,
    client_ip VARCHAR(50),
    details TEXT
);

-- 5. Thiết lập QUYỀN TỐI THIỂU (Least Privilege) cho tài khoản ứng dụng 'bank_app'
-- Chỉ cấp quyền SELECT, INSERT, UPDATE. CẤM hoàn toàn quyền DROP, TRUNCATE, ALTER!
CREATE USER bank_app WITH PASSWORD 'AppSecretPass_2026!';
GRANT CONNECT ON DATABASE digital_bank TO bank_app;
GRANT USAGE ON SCHEMA public TO bank_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO bank_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO bank_app;

-- 6. Tạo tài khoản 'bank_backup' chuyên trách sao lưu & phục hồi dữ liệu
CREATE USER bank_backup WITH SUPERUSER PASSWORD 'BackupSecretPass_2026!';
EOF
```

#### Bước 2: Cấu hình PostgreSQL lắng nghe nội bộ & Siết chặt `pg_hba.conf`
```bash
PG_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW config_file;')
PG_HBA=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;')

# Cho phép PostgreSQL lắng nghe trên địa chỉ nội bộ 10.10.10.30
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = 'localhost,10.10.10.30'/" "$PG_CONF"

# Chỉ cho phép bank_app từ vps2 (10.10.10.20) và bank_backup từ vps4 (10.10.10.40)
# Từ chối thẳng (reject) mọi kết nối từ vps0 (.5) và vps1 (.10)
cat << 'EOF' | sudo tee -a "$PG_HBA"
# Digital Bank Host-Based Access Control
host    digital_bank    bank_app        10.10.10.20/32          scram-sha-256
host    digital_bank    bank_backup     10.10.10.40/32          scram-sha-256
host    all             all             10.10.10.5/32           reject
host    all             all             10.10.10.10/32          reject
EOF

sudo systemctl restart postgresql
sudo systemctl status postgresql
```

---

### PHẦN B: Dựng Backend Xác thực JWT & Phân quyền RBAC trên `vps2-app-api` (`10.10.10.20`)

#### Bước 1: Cài đặt môi trường Python 3 & Thư viện bảo mật
SSH vào **`vps2-app-api` (`10.10.10.20`)** và chạy:

```bash
sudo apt update && sudo apt install -y python3-pip python3-venv curl jq
sudo mkdir -p /opt/bank-app && cd /opt/bank-app
sudo python3 -m venv venv
sudo /opt/bank-app/venv/bin/pip install fastapi uvicorn psycopg2-binary pyjwt passlib[bcrypt] bcrypt==4.0.1 pydantic
```

#### Bước 2: Tạo mã nguồn Backend (`/opt/bank-app/main.py`)
```bash
cat << 'EOF' | sudo tee /opt/bank-app/main.py
import logging
from datetime import datetime, timedelta, timezone
from fastapi import FastAPI, HTTPException, Depends, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
import psycopg2
from psycopg2.extras import RealDictCursor
from passlib.context import CryptContext
import jwt

logging.basicConfig(
    filename="/var/log/bank-app.log",
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s - %(message)s'
)
logger = logging.getLogger("BankAPI")

DB_CONFIG = {
    "host": "10.10.10.30",
    "port": 5432,
    "dbname": "digital_bank",
    "user": "bank_app",
    "password": "AppSecretPass_2026!"
}

JWT_SECRET = "Bank_Super_Secret_JWT_Key_2026"
JWT_ALGO = "HS256"
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBearer()
app = FastAPI(title="Digital Banking Secure Core API")

def get_db():
    return psycopg2.connect(**DB_CONFIG, cursor_factory=RealDictCursor)

def write_audit(username: str, action: str, status_str: str, client_ip: str, details: str):
    msg = f"USER={username} | ACTION={action} | STATUS={status_str} | IP={client_ip} | DETAILS={details}"
    if status_str == "SUCCESS":
        logger.info(msg)
    else:
        logger.warning(msg)
    try:
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO audit_logs (username, action, status, client_ip, details) VALUES (%s, %s, %s, %s, %s)",
                    (username, action, status_str, client_ip, details)
                )
            conn.commit()
    except Exception as e:
        logger.error(f"Audit log DB write failed: {e}")

@app.on_event("startup")
def init_mock_accounts():
    """Tự động khởi tạo dữ liệu mẫu cho 3 vai trò: Customer, Teller, Admin"""
    try:
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) as cnt FROM users")
                if cur.fetchone()["cnt"] == 0:
                    users = [
                        ("khachhang01", pwd_context.hash("KhachHang@123"), "Nguyen Van A", "customer"),
                        ("giaodichvien01", pwd_context.hash("Teller@123"), "Tran Thi B", "teller"),
                        ("admin01", pwd_context.hash("Admin@123"), "Le Quan Tri", "admin"),
                    ]
                    for u in users:
                        cur.execute("INSERT INTO users (username, password_hash, full_name, role) VALUES (%s, %s, %s, %s) RETURNING id", u)
                        uid = cur.fetchone()["id"]
                        if u[3] == "customer":
                            cur.execute("INSERT INTO accounts (account_no, user_id, balance) VALUES (%s, %s, %s)", ("1900888801", uid, 50000000.00))
                conn.commit()
    except Exception as e:
        print(f"Startup DB init check: {e}")

class LoginRequest(BaseModel):
    username: str
    password: str

@app.post("/api/login")
def login(req: LoginRequest, request: Request):
    ip = request.headers.get("X-Forwarded-For", request.client.host)
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM users WHERE username = %s", (req.username,))
            user = cur.fetchone()

    if not user or not pwd_context.verify(req.password, user["password_hash"]):
        write_audit(req.username, "LOGIN", "FAILED", ip, "Sai mat khau hoac tai khoan khong ton tai")
        raise HTTPException(status_code=401, detail="Sai thông tin đăng nhập!")

    payload = {
        "sub": user["username"],
        "uid": user["id"],
        "role": user["role"],
        "exp": datetime.now(timezone.utc) + timedelta(minutes=30)
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGO)
    write_audit(user["username"], "LOGIN", "SUCCESS", ip, f"Role={user['role']}")
    return {"access_token": token, "role": user["role"], "full_name": user["full_name"]}

def verify_token(request: Request, creds: HTTPAuthorizationCredentials = Depends(security)):
    ip = request.headers.get("X-Forwarded-For", request.client.host)
    try:
        return jwt.decode(creds.credentials, JWT_SECRET, algorithms=[JWT_ALGO])
    except Exception:
        write_audit("UNKNOWN", "AUTH_TOKEN", "DENIED", ip, "Token khong hop le hoac het han")
        raise HTTPException(status_code=401, detail="Token không hợp lệ hoặc đã hết hạn")

@app.get("/api/my-account")
def get_my_account(request: Request, user=Depends(verify_token)):
    ip = request.headers.get("X-Forwarded-For", request.client.host)
    if user["role"] != "customer":
        write_audit(user["sub"], "VIEW_ACCOUNT", "DENIED", ip, f"Role {user['role']} bi tu choi")
        raise HTTPException(status_code=403, detail="Chỉ Khách hàng mới có tài khoản cá nhân!")
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT account_no, balance, currency, updated_at FROM accounts WHERE user_id = %s", (user["uid"],))
            acc = cur.fetchone()
    write_audit(user["sub"], "VIEW_ACCOUNT", "SUCCESS", ip, f"Account={acc['account_no']}")
    return acc

@app.get("/api/admin/audit-logs")
def get_audit_logs(request: Request, user=Depends(verify_token)):
    ip = request.headers.get("X-Forwarded-For", request.client.host)
    if user["role"] != "admin":
        write_audit(user["sub"], "VIEW_AUDIT_LOGS", "DENIED", ip, f"Truy cap trai phep tu role={user['role']}")
        raise HTTPException(status_code=403, detail="Từ chối truy cập: Yêu cầu quyền Admin!")
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM audit_logs ORDER BY event_time DESC LIMIT 20")
            logs = cur.fetchall()
    write_audit(user["sub"], "VIEW_AUDIT_LOGS", "SUCCESS", ip, "Admin xem nhat ky he thong")
    return {"audit_logs": logs}
EOF
```

#### Bước 3: Thiết lập Systemd Service chạy Backend tự động trên `10.10.10.20:8080`
```bash
sudo touch /var/log/bank-app.log && sudo chmod 666 /var/log/bank-app.log

cat << 'EOF' | sudo tee /etc/systemd/system/bank-app.service
[Unit]
Description=Digital Banking FastAPI Backend
After=network.target

[Service]
User=root
WorkingDirectory=/opt/bank-app
ExecStart=/opt/bank-app/venv/bin/uvicorn main:app --host 10.10.10.20 --port 8080
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now bank-app
sudo systemctl status bank-app
```

---

### PHẦN C: Dựng Cơ chế Sao lưu Mã hóa GPG & Phục hồi Dữ liệu (Trên `vps4-mgmt-log` — `10.10.10.40`)

Để đảm bảo an toàn khi máy chủ DB (`vps3`) gặp sự cố, bản sao lưu được kéo về lưu trữ độc lập trên **`vps4-mgmt-log` (`10.10.10.40`)** và mã hóa bằng thuật toán **`AES-256 (GPG)`**.

SSH vào **`vps4-mgmt-log` (`10.10.10.40`)** và chạy:

```bash
sudo apt update && sudo apt install -y postgresql-client gnupg
sudo mkdir -p /opt/backups /opt/scripts

# 1. Tạo Script Sao lưu & Mã hóa AES-256 (/opt/scripts/backup_db.sh)
cat << 'EOF' | sudo tee /opt/scripts/backup_db.sh
#!/bin/bash
set -e
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="/opt/backups/digital_bank_${TIMESTAMP}.sql.gpg"
export PGPASSWORD='BackupSecretPass_2026!'

echo "[$(date -Is)] Bắt đầu sao lưu CSDL từ vps3 (10.10.10.30)..."
pg_dump -h 10.10.10.30 -U bank_backup -d digital_bank | \
  gpg --batch --yes --passphrase "Bank_GPG_Encrypt_Key_2026" --cipher-algo AES256 -c -o "$BACKUP_FILE"

echo "[$(date -Is)] Sao lưu & mã hóa AES-256 hoàn tất: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"
EOF

# 2. Tạo Script Giải mã & Phục hồi dữ liệu (/opt/scripts/restore_db.sh)
cat << 'EOF' | sudo tee /opt/scripts/restore_db.sh
#!/bin/bash
set -e
LATEST_BACKUP=$(ls -t /opt/backups/digital_bank_*.sql.gpg | head -n 1)
export PGPASSWORD='BackupSecretPass_2026!'

echo "[$(date -Is)] Đang giải mã và phục hồi từ bản sao lưu: $LATEST_BACKUP"
gpg --batch --yes --passphrase "Bank_GPG_Encrypt_Key_2026" -d "$LATEST_BACKUP" | \
  psql -h 10.10.10.30 -U bank_backup -d digital_bank

echo "[$(date -Is)] Phục hồi dữ liệu CSDL hoàn tất nguyên trạng!"
EOF

sudo chmod +x /opt/scripts/backup_db.sh /opt/scripts/restore_db.sh

# Thiết lập Cronjob tự động sao lưu hàng ngày lúc 02:00 sáng
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/scripts/backup_db.sh >> /var/log/backup_bank.log 2>&1") | crontab -
```

---

## 4. KIỂM THỬ XÁC THỰC, PHÂN QUYỀN & PHỤC HỒI DỮ LIỆU (CÓ TIMESTAMP)

SV3 chạy các lệnh kiểm thử sau và chụp ảnh màn hình (đã có timestamp) để làm minh chứng cá nhân:

1. **Trên `vps2-app-api`: Kiểm thử xác thực JWT (`khachhang01`) và kiểm tra từ chối quyền Admin (`HTTP 403`):**
   ```bash
   echo "=== [SV3 - AUTH & RBAC TEST] ==="
   TOKEN=$(curl -s -X POST http://10.10.10.20:8080/api/login \
     -H "Content-Type: application/json" \
     -d '{"username":"khachhang01","password":"KhachHang@123"}' | jq -r .access_token)

   # Xem số dư cá nhân -> Thành công (HTTP 200)
   curl -s -i http://10.10.10.20:8080/api/my-account -H "Authorization: Bearer $TOKEN"

   # Cố tình gọi API Admin -> Bị từ chối (HTTP 403 Forbidden)
   curl -s -i http://10.10.10.20:8080/api/admin/audit-logs -H "Authorization: Bearer $TOKEN"
   ```

2. **Trên `vps4-mgmt-log`: Kiểm thử Sao lưu GPG, Giả lập mất dữ liệu, Phục hồi & Kiểm tra quyền tối thiểu DB (KT3):**
   ```bash
   echo "=== [SV3 - BACKUP, RESTORE & LEAST PRIVILEGE TEST] ==="
   # 1. Chạy sao lưu mã hóa GPG
   /opt/scripts/backup_db.sh

   # 2. Giả lập sự cố xóa toàn bộ bảng accounts
   PGPASSWORD='BackupSecretPass_2026!' psql -h 10.10.10.30 -U bank_backup -d digital_bank -c "DELETE FROM accounts;"
   PGPASSWORD='BackupSecretPass_2026!' psql -h 10.10.10.30 -U bank_backup -d digital_bank -c "SELECT * FROM accounts;"

   # 3. Khôi phục từ file backup .sql.gpg và kiểm tra lại dữ liệu
   /opt/scripts/restore_db.sh
   PGPASSWORD='BackupSecretPass_2026!' psql -h 10.10.10.30 -U bank_backup -d digital_bank -c "SELECT * FROM accounts;"

   # 4. Chứng minh tài khoản ứng dụng 'bank_app' bị chặn lệnh DROP TABLE
   PGPASSWORD='AppSecretPass_2026!' psql -h 10.10.10.30 -U bank_app -d digital_bank -c "DROP TABLE accounts;"
   ```

---

## 5. DANH MỤC SẢN PHẨM KỸ THUẬT CÁ NHÂN SV3 CẦN NỘP
1. File mã nguồn Backend `/opt/bank-app/main.py` và `/etc/systemd/system/bank-app.service` (trên `vps2`).
2. Script SQL khởi tạo CSDL & file `/etc/postgresql/16/main/pg_hba.conf` (trên `vps3`).
3. Hai file script `/opt/scripts/backup_db.sh` và `/opt/scripts/restore_db.sh` (trên `vps4`).
4. Bộ ảnh chụp màn hình có timestamp chứng minh:
   * Đăng nhập JWT thành công & chặn truy cập trái phép RBAC (`HTTP 403`).
   * Sao lưu mã hóa `.sql.gpg`, xóa giả lập và phục hồi thành công bảng `accounts`.
   * PostgreSQL từ chối lệnh `DROP TABLE` của tài khoản `bank_app`.
