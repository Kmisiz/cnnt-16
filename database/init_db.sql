-- =====================================================================
-- Muoi Sau Bank - Khoi tao CSDL (chay tren vps3-data-db 10.10.10.30)
--
--   sudo -u postgres createdb digital_bank   (phai tao truoc, file nay khong tu tao)
--   sudo -u postgres psql -d digital_bank < init_db.sql
--
-- Tai khoan nguoi dung mau KHONG nap o day: backend tu tao (mat khau bam
-- bcrypt) o lan khoi dong dau tien khi bang users con trong.
-- =====================================================================

CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(50)  UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name     VARCHAR(100) NOT NULL,
    role          VARCHAR(20)  NOT NULL CHECK (role IN ('customer', 'teller', 'admin')),
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by    VARCHAR(50)  DEFAULT 'system',
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS accounts (
    account_no VARCHAR(20)   PRIMARY KEY,
    user_id    INT UNIQUE    NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    balance    NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    currency   VARCHAR(10)   NOT NULL DEFAULT 'VND',
    updated_at TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS transactions (
    id           SERIAL PRIMARY KEY,
    from_account VARCHAR(20)   NOT NULL REFERENCES accounts(account_no),
    to_account   VARCHAR(20)   NOT NULL REFERENCES accounts(account_no),
    amount       NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    note         VARCHAR(140),
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tx_from ON transactions (from_account, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tx_to   ON transactions (to_account, created_at DESC);

CREATE TABLE IF NOT EXISTS audit_logs (
    id         BIGSERIAL PRIMARY KEY,
    event_time TIMESTAMPTZ  NOT NULL DEFAULT now(),
    username   VARCHAR(50),
    action     VARCHAR(100) NOT NULL,
    status     VARCHAR(20)  NOT NULL,
    client_ip  VARCHAR(50),
    details    TEXT
);
CREATE INDEX IF NOT EXISTS idx_audit_time ON audit_logs (event_time DESC);

-- ---------------------------------------------------------------------
-- Tai khoan CSDL
--   bank_app    : dung boi backend (vps2) - quyen toi thieu
-- Doi mat khau truoc khi trien khai that.
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'bank_app') THEN
        CREATE ROLE bank_app LOGIN PASSWORD 'AppSecretPass_2026!';
    END IF;
END
$$;

REVOKE ALL ON DATABASE digital_bank FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

GRANT CONNECT ON DATABASE digital_bank TO bank_app;
GRANT USAGE ON SCHEMA public TO bank_app;

-- Nghiep vu: doc / them / sua. Khong DELETE, khong DROP, khong TRUNCATE.
GRANT SELECT, INSERT, UPDATE ON users, accounts, transactions TO bank_app;
-- Nhat ky: chi duoc them va doc, khong sua/xoa duoc dau vet.
GRANT SELECT, INSERT ON audit_logs TO bank_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO bank_app;
