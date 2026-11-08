# HƯỚNG DẪN TRIỂN KHAI CHI TIẾT: THÀNH VIÊN 3 (THẮNG - SV3)
**Đề tài 16: Thiết kế hạ tầng CNTT an toàn cho Ngân hàng số (Mười Sáu Bank)**  
**Phụ trách:** Cơ sở dữ liệu PostgreSQL (`vps3-data-db`), Core Banking API (`vps2-app-api`: Xác thực JWT + HttpOnly Cookie, Phân quyền RBAC, Nhật ký Audit) và Sao lưu - Phục hồi dữ liệu.

---

## 1. TỔNG QUAN VAI TRÒ CỦA SV3 TRONG HỆ THỐNG

SV3 chịu trách nhiệm xây dựng và bảo vệ 2 phân vùng cốt lõi nhất của Ngân hàng Số Mười Sáu:
1. **`vps3-data-db` (`10.10.10.30` - Data Tier):**
   - Chạy Hệ quản trị CSDL **PostgreSQL 16** (`digital_bank`).
   - Áp dụng nguyên tắc **Đặc quyền tối thiểu (Least Privilege)**: Tài khoản kết nối từ ứng dụng (`bank_app`) chỉ có quyền `SELECT, INSERT, UPDATE` trên các bảng nghiệp vụ và chỉ có quyền `SELECT, INSERT` trên bảng `audit_logs` (không có quyền `DELETE`, `DROP`, `TRUNCATE`). Ngay cả khi tầng App bị xâm nhập, kẻ tấn công cũng không thể xóa bảng hay xóa dấu vết giao dịch.
2. **`vps2-app-api` (`10.10.10.20` - Application Tier):**
   - Chạy dịch vụ **FastAPI Core Banking (`main.py`)** lắng nghe tại `10.10.10.20:8080`.
   - Băm mật khẩu bằng **Bcrypt**; cấp phát **JWT Token** đồng thời qua `HttpOnly; Secure; SameSite=Strict` Cookie (`kn_session`) và `Bearer` Header.
   - Hỗ trợ endpoint nội bộ `/api/auth/staff-check` để Nginx trên `vps0` kiểm tra quyền trước khi mở trang `/admin/` (trả về `404 Not Found` nếu là khách hàng hoặc chưa đăng nhập).
   - Tự động khởi tạo dữ liệu mẫu chuẩn ngân hàng ngay khi khởi động dịch vụ.

### Bảng tài khoản mặc định được tự động khởi tạo:

| Tên đăng nhập | Mật khẩu | Vai trò (`role`) | Số tài khoản | Số dư khởi tạo | Quyền hạn chính |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`user1`** | `User1@123` | `customer` | `1900888801` | `50,000,000 VND` | Xem số dư, chuyển khoản nội bộ, xem sao kê cá nhân. |
| **`user2`** | `User2@123` | `customer` | `1900888802` | `20,000,000 VND` | Tài khoản thụ hưởng mẫu để demo chuyển tiền. |
| **`teller`** | `Teller@123` | `teller` | *(Nội bộ)* | - | Truy cập `/admin/`, tra cứu danh sách tài khoản khách hàng (`/api/accounts`). |
| **`admin`** | `Admin@123` | `admin` | *(Nội bộ)* | - | Toàn quyền tại `/admin/`: Quản lý người dùng, Khóa/Mở khóa tài khoản, Tạo nhân sự mới, Xem nhật ký bảo mật (`audit_logs`). |

---

## 2. TRIỂN KHAI CƠ SỞ DỮ LIỆU TRÊN `vps3-data-db` (`10.10.10.30`)

Từ `vps4-mgmt-log`, SSH vào **`vps3-data-db` (`10.10.10.30`)** và thực hiện tuần tự:

### Bước 1: Cài đặt PostgreSQL 16 và tải mã nguồn từ GitHub
```bash
sudo apt update && sudo apt install -y postgresql postgresql-contrib git
cd ~
rm -rf cnnt-16
git clone https://github.com/Kmisiz/cnnt-16.git
```

### Bước 2: Khởi tạo Schema `digital_bank` và phân quyền Least Privilege (`bank_app`)
File `~/cnnt-16/database/init_db.sql` đã định nghĩa đầy đủ 4 bảng (`users`, `accounts`, `transactions`, `audit_logs`), tạo user `bank_app` (mật khẩu `AppSecretPass_2026!`) và thu hồi toàn bộ quyền `DELETE / DROP / TRUNCATE`.

Chạy lệnh khởi tạo:
```bash
sudo -u postgres psql -f ~/cnnt-16/database/init_db.sql
```

### Bước 3: Cấu hình PostgreSQL chỉ lắng nghe IP nội bộ và chỉ nhận kết nối từ `vps2-app-api` (`10.10.10.20`)
```bash
PG_CONF="/etc/postgresql/16/main/postgresql.conf"
PG_HBA="/etc/postgresql/16/main/pg_hba.conf"

# Cho phep lang nghe tren IP noi bo 10.10.10.30
sudo sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = 'localhost,10.10.10.30'/" "$PG_CONF"

# Chi cho phep user bank_app ket noi tu duy nhat IP cua VPS2 (10.10.10.20/32)
if ! sudo grep -q "10.10.10.20/32" "$PG_HBA"; then
  echo "host    digital_bank    bank_app    10.10.10.20/32    scram-sha-256" | sudo tee -a "$PG_HBA"
fi

sudo systemctl restart postgresql
sudo systemctl enable postgresql
```

### Bước 4: Thiết lập Tường lửa UFW trên `vps3-data-db`
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 10.10.10.40 to any port 22 proto tcp
sudo ufw allow from 10.10.10.20 to any port 5432 proto tcp
sudo ufw --force enable
sudo ufw status verbose
```

---

## 3. TRIỂN KHAI CORE BANKING API TRÊN `vps2-app-api` (`10.10.10.20`)

Từ `vps4-mgmt-log`, SSH vào **`vps2-app-api` (`10.10.10.20`)** và thực hiện tuần tự:

### Bước 1: Cài đặt môi trường Python và tải mã nguồn từ GitHub
```bash
sudo apt update && sudo apt install -y python3 python3-venv python3-pip git
cd ~
rm -rf cnnt-16
git clone https://github.com/Kmisiz/cnnt-16.git
```

### Bước 2: Thiết lập thư mục dịch vụ `/opt/bank-app` và cài đặt thư viện
```bash
sudo useradd -r -s /usr/sbin/nologin bankapp 2>/dev/null || true
sudo mkdir -p /opt/bank-app
sudo cp ~/cnnt-16/backend/main.py ~/cnnt-16/backend/requirements.txt /opt/bank-app/
sudo cp ~/cnnt-16/backend/bank-app.env.example /opt/bank-app/.env

sudo python3 -m venv /opt/bank-app/venv
sudo /opt/bank-app/venv/bin/pip install --upgrade pip
sudo /opt/bank-app/venv/bin/pip install -r /opt/bank-app/requirements.txt

sudo chown -R bankapp:bankapp /opt/bank-app
sudo chmod 600 /opt/bank-app/.env
```

### Bước 3: Kích hoạt Systemd Service `bank-app.service`
Khi `bank-app.service` khởi chạy, hàm `seed_data()` trong `main.py` sẽ tự động kết nối sang `10.10.10.30` và nạp sẵn 4 tài khoản mẫu (`user1`, `user2`, `teller`, `admin`) cùng lịch sử giao dịch ban đầu nếu bảng đang trống.

```bash
sudo cp ~/cnnt-16/backend/bank-app.service /etc/systemd/system/bank-app.service
sudo systemctl daemon-reload
sudo systemctl enable bank-app
sudo systemctl restart bank-app
sudo systemctl status bank-app --no-pager
```

### Bước 4: Thiết lập Tường lửa UFW trên `vps2-app-api`
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 10.10.10.40 to any port 22 proto tcp
sudo ufw allow from 10.10.10.10 to any port 8080 proto tcp
sudo ufw --force enable
sudo ufw status verbose
```

---

## 4. THIẾT LẬP SAO LƯU MÃ HÓA (AES-256) & KIỂM THỬ PHỤC HỒI TRÊN `vps3-data-db`

Thực hiện trên **`vps3-data-db` (`10.10.10.30`)** để đáp ứng yêu cầu Sao lưu tự động và Kiểm thử phục hồi (KT3.1):

### Bước 1: Tạo khóa mã hóa và Script sao lưu tự động `/usr/local/bin/backup_bank_db.sh`
```bash
sudo mkdir -p /var/backups/postgres
sudo chown postgres:postgres /var/backups/postgres
sudo chmod 700 /var/backups/postgres

# Tao passphrase ma hoa ban sao luu (chi root doc duoc)
echo "MuoiSauBank@BackupKey#2026" | sudo tee /root/.backup_passphrase > /dev/null
sudo chmod 600 /root/.backup_passphrase

sudo tee /usr/local/bin/backup_bank_db.sh > /dev/null << 'EOF'
#!/bin/bash
set -e
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/postgres"
ENC_FILE="${BACKUP_DIR}/digital_bank_${TIMESTAMP}.sql.gz.enc"

# Dump CSDL, nen gzip va ma hoa AES-256-CBC bang OpenSSL
sudo -u postgres pg_dump digital_bank | gzip | openssl enc -aes-256-cbc -salt -pbkdf2 \
  -pass file:/root/.backup_passphrase -out "${ENC_FILE}"

chmod 600 "${ENC_FILE}"
logger -t BANK_BACKUP "BACKUP_SUCCESS: Created encrypted backup ${ENC_FILE}"
echo "[OK] Da tao ban sao luu ma hoa: ${ENC_FILE}"
EOF

sudo chmod 700 /usr/local/bin/backup_bank_db.sh
```

### Bước 2: Chạy thử sao lưu ngay và cài đặt lịch tự động (Cronjob 02:00 sáng hàng ngày)
```bash
sudo /usr/local/bin/backup_bank_db.sh
ls -lh /var/backups/postgres/

# Dang ky Cronjob chay tu dong 02:00 hang ngay
(sudo crontab -l 2>/dev/null | grep -v "backup_bank_db.sh"; echo "0 2 * * * /usr/local/bin/backup_bank_db.sh") | sudo crontab -
```

---

## 5. KỊCH BẢN KIỂM THỬ BẢO MẬT DỮ LIỆU & PHỤC HỒI (CHỤP ẢNH BÁO CÁO SV3)

### 5.1. Kiểm thử Least Privilege: User `bank_app` không thể xóa dữ liệu hoặc xóa nhật ký
Trên `vps2-app-api` hoặc `vps3-data-db`, thử dùng tài khoản `bank_app` để xóa bảng `transactions` hoặc xóa `audit_logs`:
```bash
PGPASSWORD='AppSecretPass_2026!' psql -h 10.10.10.30 -U bank_app -d digital_bank -c "DELETE FROM transactions;"
PGPASSWORD='AppSecretPass_2026!' psql -h 10.10.10.30 -U bank_app -d digital_bank -c "DROP TABLE users;"
```
-> **Kết quả mong đợi:** PostgreSQL báo lỗi `ERROR: permission denied for table transactions` và `ERROR: must be owner of table users`.

### 5.2. Kiểm thử Sao lưu & Phục hồi sau sự cố mất dữ liệu (KT3.1)
Trên `vps3-data-db` (`10.10.10.30`), chạy kịch bản mô phỏng sự cố và khôi phục:
```bash
# 1. Tao ban sao luu moi nhat
sudo /usr/local/bin/backup_bank_db.sh
LATEST_BACKUP=$(ls -t /var/backups/postgres/digital_bank_*.sql.gz.enc | head -n 1)

# 2. Kiem tra so luong ban ghi truoc su co
sudo -u postgres psql -d digital_bank -c "SELECT account_number, owner_name, balance FROM accounts;"

# 3. Gia lap tham hoa: Quan tri vien DB vo tinh xoa trang bang transactions va accounts
sudo -u postgres psql -d digital_bank -c "TRUNCATE TABLE transactions, accounts CASCADE;"
sudo -u postgres psql -d digital_bank -c "SELECT COUNT(*) AS so_tai_khoan_con_lai FROM accounts;"

# 4. Giai ma ban sao luu AES-256 va phuc hoi (Restore)
sudo openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/root/.backup_passphrase -in "$LATEST_BACKUP" \
  | gunzip | sudo -u postgres psql -d digital_bank

# 5. Xac nhan du lieu so du va lich su giao dich da phuc hoi 100%
sudo -u postgres psql -d digital_bank -c "SELECT account_number, owner_name, balance FROM accounts;"
```
-> **Kết quả mong đợi:** Toàn bộ tài khoản (`1900888801` - `50,000,000 VND`, `1900888802` - `20,000,000 VND`) và lịch sử giao dịch được khôi phục nguyên vẹn 100%.
