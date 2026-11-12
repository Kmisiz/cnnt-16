"""
Muoi Sau Bank - Core Banking API
Chay tren vps2-app-api (10.10.10.20:8080), chi nhan request tu vps1-dmz-fw.

Phien dang nhap: JWT luu trong cookie HttpOnly (trinh duyet khong doc duoc bang JS).
Van ho tro header "Authorization: Bearer" de kiem thu bang curl.
"""

import logging
import os
import re
import sys
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import List, Optional

import jwt
import psycopg2
from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from passlib.context import CryptContext
from psycopg2.extras import RealDictCursor
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Cau hinh (doc tu bien moi truong, xem bank-app.env.example)
# ---------------------------------------------------------------------------
def _require_env(name: str) -> str:
    """Bien bi mat khong co gia tri mac dinh: thieu thi dich vu khong khoi dong."""
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Thieu bien moi truong bat buoc {name} (xem bank-app.env.example)")
    return value


DB_CONFIG = {
    "host": os.getenv("DB_HOST", "10.10.10.30"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "digital_bank"),
    "user": os.getenv("DB_USER", "bank_app"),
    "password": _require_env("DB_PASSWORD"),
    "connect_timeout": 5,
}

JWT_SECRET = _require_env("JWT_SECRET")
JWT_ALGORITHM = "HS256"
SESSION_MINUTES = int(os.getenv("SESSION_MINUTES", "30"))
COOKIE_NAME = "kn_session"

STAFF_ROLES = ["teller", "admin"]

# ---------------------------------------------------------------------------
# Logging: ghi ra stdout, systemd chuyen vao /var/log/bank-app.log,
# rsyslog tren vps2 day file nay ve vps4.
# ---------------------------------------------------------------------------
logger = logging.getLogger("bank-api")
logger.setLevel(logging.INFO)
_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(logging.Formatter("[%(asctime)s] %(levelname)s %(name)s %(message)s"))
logger.addHandler(_handler)
logger.propagate = False

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
_DUMMY_HASH = pwd_context.hash("khong-phai-mat-khau-that")
bearer = HTTPBearer(auto_error=False)

app = FastAPI(title="Kim Ngan Bank Core API", docs_url=None, redoc_url=None, openapi_url=None)


# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
@contextmanager
def db():
    try:
        conn = psycopg2.connect(**DB_CONFIG, cursor_factory=RealDictCursor)
    except psycopg2.Error as exc:
        logger.error("DB_CONNECT_ERROR %s", exc)
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Hệ thống đang bận, vui lòng thử lại sau.")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def client_ip(request: Request) -> str:
    xff = request.headers.get("X-Forwarded-For")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else "-"


# Dong log co dang  USER=.. | ACTION=.. | STATUS=.. | IP=.. | DETAILS=..  va decoder Wazuh bam vao
# dang nay. Du lieu do nguoi dung nhap khong duoc chua dau phan cach "|", ky tu dieu khien
# (gom xuong dong) hoac, o cac truong khong co khoang trang, ky tu trang.
_LOG_TOKEN_UNSAFE = re.compile(r"[\s|\x00-\x1f\x7f]")   # USER, IP
_LOG_TEXT_UNSAFE = re.compile(r"[|\x00-\x1f\x7f]")       # DETAILS


def _log_token(value: object, limit: int) -> str:
    return _LOG_TOKEN_UNSAFE.sub("_", str(value))[:limit]


def _log_text(value: object, limit: int) -> str:
    return _LOG_TEXT_UNSAFE.sub("_", str(value))[:limit]


def audit(username: Optional[str], action: str, result: str, ip: str, details: str = "") -> None:
    line = (f"USER={_log_token(username or '-', 50)} | ACTION={action} | STATUS={result} | "
            f"IP={_log_token(ip, 45)} | DETAILS={_log_text(details, 500)}")
    if result == "SUCCESS":
        logger.info(line)
    else:
        logger.warning(line)
    try:
        with db() as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO audit_logs (username, action, status, client_ip, details) VALUES (%s, %s, %s, %s, %s)",
                (username, action, result, ip[:50], details[:500]),
            )
    except Exception as exc:  # khong de loi ghi log lam hong request
        logger.error("AUDIT_WRITE_ERROR %s", exc)


# ---------------------------------------------------------------------------
# Du lieu mau (chi chay khi bang users con trong)
# ---------------------------------------------------------------------------
SEED_USERS = [
    # username, password, full_name, role, account_no, balance
    ("user1", "User1@123", "Nguyễn Văn An", "customer", "1900888801", Decimal("50000000")),
    ("user2", "User2@123", "Trần Thị Bình", "customer", "1900888802", Decimal("20000000")),
    ("teller", "Teller@123", "Phạm Minh Châu", "teller", None, None),
    ("admin", "Admin@123", "Lê Quốc Dũng", "admin", None, None),
]


@app.on_event("startup")
def seed_data() -> None:
    try:
        with db() as conn, conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS n FROM users")
            if cur.fetchone()["n"] > 0:
                return
            for username, password, name, role, acc_no, balance in SEED_USERS:
                cur.execute(
                    "INSERT INTO users (username, password_hash, full_name, role) VALUES (%s, %s, %s, %s) RETURNING id",
                    (username, pwd_context.hash(password), name, role),
                )
                uid = cur.fetchone()["id"]
                if acc_no:
                    cur.execute(
                        "INSERT INTO accounts (account_no, user_id, balance) VALUES (%s, %s, %s)",
                        (acc_no, uid, balance),
                    )
        logger.info("Seed data created")
    except Exception as exc:
        logger.warning("Seed skipped: %s", exc)


# ---------------------------------------------------------------------------
# Xac thuc & phan quyen
# ---------------------------------------------------------------------------
def _read_token(request: Request, creds: Optional[HTTPAuthorizationCredentials]) -> Optional[str]:
    if creds and creds.credentials:
        return creds.credentials
    return request.cookies.get(COOKIE_NAME)


def current_user(request: Request, creds: Optional[HTTPAuthorizationCredentials] = Depends(bearer)) -> dict:
    token = _read_token(request, creds)
    if not token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Phiên đăng nhập không tồn tại.")
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Phiên đăng nhập đã hết hạn.")
    except jwt.InvalidTokenError:
        audit(None, "TOKEN_INVALID", "DENIED", client_ip(request), request.url.path)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Phiên đăng nhập không hợp lệ.")

    # Tai khoan bi khoa sau khi da cap token thi cung khong dung duoc nua
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT id, username, full_name, role, is_active FROM users WHERE id = %s", (payload["uid"],))
        user = cur.fetchone()
    if not user or not user["is_active"]:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Tài khoản đã bị khóa hoặc không tồn tại.")
    return dict(user)


def require_roles(roles: List[str]):
    def checker(request: Request, user: dict = Depends(current_user)) -> dict:
        if user["role"] not in roles:
            audit(user["username"], "RBAC", "DENIED", client_ip(request),
                  f"role={user['role']} path={request.url.path}")
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Bạn không có quyền thực hiện chức năng này.")
        return user
    return checker


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------
class LoginIn(BaseModel):
    username: str = Field(min_length=1, max_length=50)
    password: str = Field(min_length=1, max_length=128)


class TransferIn(BaseModel):
    to_account: str = Field(pattern=r"^\d{6,20}$")
    amount: Decimal = Field(gt=0, le=Decimal("500000000"), decimal_places=2)
    note: str = Field(default="", max_length=140)


class CreateUserIn(BaseModel):
    username: str = Field(pattern=r"^[a-z0-9_.]{4,50}$")
    password: str = Field(min_length=8, max_length=128)
    full_name: str = Field(min_length=2, max_length=100)
    role: str = Field(pattern=r"^(customer|teller|admin)$")
    initial_balance: Decimal = Field(default=Decimal("0"), ge=0, max_digits=15, decimal_places=2)


class UserStatusIn(BaseModel):
    is_active: bool


# ---------------------------------------------------------------------------
# Endpoint chung
# ---------------------------------------------------------------------------
@app.get("/api/health")
def health():
    return {"status": "ok", "time": datetime.now(timezone.utc).isoformat()}


@app.post("/api/login")
def login(data: LoginIn, request: Request, response: Response):
    ip = client_ip(request)
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM users WHERE username = %s", (data.username,))
        user = cur.fetchone()

    # Luon chay verify (ke ca khi khong co user) de thoi gian phan hoi khong lo ten dang nhap co ton tai hay khong
    password_ok = pwd_context.verify(data.password, user["password_hash"] if user else _DUMMY_HASH)
    if not user or not password_ok:
        audit(data.username, "LOGIN", "FAILED", ip, "sai ten dang nhap hoac mat khau")
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Tên đăng nhập hoặc mật khẩu không đúng.")
    if not user["is_active"]:
        audit(data.username, "LOGIN", "DENIED", ip, "tai khoan bi khoa")
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Tài khoản đã bị tạm khóa. Vui lòng liên hệ ngân hàng.")

    expires = datetime.now(timezone.utc) + timedelta(minutes=SESSION_MINUTES)
    token = jwt.encode(
        {"sub": user["username"], "uid": user["id"], "role": user["role"], "exp": expires},
        JWT_SECRET,
        algorithm=JWT_ALGORITHM,
    )
    response.set_cookie(
        COOKIE_NAME, token,
        max_age=SESSION_MINUTES * 60, httponly=True, secure=True, samesite="strict", path="/",
    )
    audit(user["username"], "LOGIN", "SUCCESS", ip, f"role={user['role']}")
    return {
        "username": user["username"],
        "full_name": user["full_name"],
        "role": user["role"],
        "session_expires": expires.isoformat(),
    }


@app.post("/api/logout")
def logout(request: Request, response: Response):
    response.delete_cookie(COOKIE_NAME, path="/")
    return {"status": "ok"}


@app.get("/api/me")
def me(user: dict = Depends(current_user)):
    return {"username": user["username"], "full_name": user["full_name"], "role": user["role"]}


@app.get("/api/auth/staff-check", status_code=204)
def staff_check(request: Request, creds: Optional[HTTPAuthorizationCredentials] = Depends(bearer)):
    """
    Nginx tren vps0 goi endpoint nay (auth_request) truoc khi phuc vu /admin.
    204 = cho qua; 401/403 = Nginx tra ve trang 404 mac dinh.
    """
    original_uri = request.headers.get("X-Original-URI", "/admin")
    ip = client_ip(request)
    try:
        user = current_user(request, creds)
    except HTTPException:
        audit(None, "ADMIN_PATH_PROBE", "DENIED", ip, f"chua dang nhap uri={original_uri}")
        raise
    if user["role"] not in STAFF_ROLES:
        audit(user["username"], "ADMIN_PATH_PROBE", "DENIED", ip, f"role={user['role']} uri={original_uri}")
        raise HTTPException(status.HTTP_403_FORBIDDEN)
    return Response(status_code=204)


# ---------------------------------------------------------------------------
# Khach hang
# ---------------------------------------------------------------------------
def _own_account(cur, user_id: int, lock: bool = False):
    sql = "SELECT account_no, balance, currency, updated_at FROM accounts WHERE user_id = %s"
    if lock:
        sql += " FOR UPDATE"
    cur.execute(sql, (user_id,))
    return cur.fetchone()


@app.get("/api/my-account")
def my_account(request: Request, user: dict = Depends(require_roles(["customer"]))):
    with db() as conn, conn.cursor() as cur:
        acc = _own_account(cur, user["id"])
    if not acc:
        raise HTTPException(404, "Không tìm thấy tài khoản thanh toán.")
    audit(user["username"], "VIEW_ACCOUNT", "SUCCESS", client_ip(request), acc["account_no"])
    return acc


@app.get("/api/my-transactions")
def my_transactions(limit: int = 20, user: dict = Depends(require_roles(["customer"]))):
    limit = max(1, min(limit, 100))
    with db() as conn, conn.cursor() as cur:
        acc = _own_account(cur, user["id"])
        if not acc:
            return {"items": []}
        cur.execute(
            """
            SELECT t.id, t.created_at, t.amount, t.note,
                   CASE WHEN t.from_account = %(acc)s THEN 'OUT' ELSE 'IN' END AS direction,
                   CASE WHEN t.from_account = %(acc)s THEN t.to_account ELSE t.from_account END AS counterpart,
                   u.full_name AS counterpart_name
            FROM transactions t
            JOIN accounts a ON a.account_no =
                 CASE WHEN t.from_account = %(acc)s THEN t.to_account ELSE t.from_account END
            JOIN users u ON u.id = a.user_id
            WHERE t.from_account = %(acc)s OR t.to_account = %(acc)s
            ORDER BY t.created_at DESC
            LIMIT %(limit)s
            """,
            {"acc": acc["account_no"], "limit": limit},
        )
        return {"items": cur.fetchall()}


@app.get("/api/accounts/lookup")
def lookup_account(account_no: str, user: dict = Depends(require_roles(["customer"]))):
    if not account_no.isdigit():
        raise HTTPException(400, "Số tài khoản không hợp lệ.")
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            """SELECT a.account_no, u.full_name FROM accounts a JOIN users u ON u.id = a.user_id
               WHERE a.account_no = %s AND u.is_active = TRUE""",
            (account_no,),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(404, "Không tìm thấy tài khoản nhận.")
    return {"account_no": row["account_no"], "holder": row["full_name"].upper()}


@app.post("/api/transfer")
def transfer(data: TransferIn, request: Request, user: dict = Depends(require_roles(["customer"]))):
    ip = client_ip(request)
    with db() as conn, conn.cursor() as cur:
        src = _own_account(cur, user["id"])
        if not src:
            raise HTTPException(404, "Không tìm thấy tài khoản nguồn.")
        if src["account_no"] == data.to_account:
            raise HTTPException(400, "Không thể chuyển tiền đến chính tài khoản nguồn.")
        # Khoa CA HAI tai khoan trong cung 1 cau lenh, theo thu tu so tai khoan tang dan.
        # Neu khoa lan luot "nguon roi dich", hai giao dich chuyen cheo A->B va B->A
        # se khoa nguoc thu tu nhau va gay deadlock.
        cur.execute(
            "SELECT account_no, balance FROM accounts WHERE account_no IN (%s, %s) ORDER BY account_no FOR UPDATE",
            (src["account_no"], data.to_account),
        )
        locked = {row["account_no"]: row for row in cur.fetchall()}
        if data.to_account not in locked:
            raise HTTPException(404, "Không tìm thấy tài khoản nhận.")
        src["balance"] = locked[src["account_no"]]["balance"]  # so du moi nhat sau khi da khoa
        if src["balance"] < data.amount:
            audit(user["username"], "TRANSFER", "FAILED", ip, "so du khong du")
            raise HTTPException(400, "Số dư không đủ để thực hiện giao dịch.")

        cur.execute("UPDATE accounts SET balance = balance - %s, updated_at = now() WHERE account_no = %s",
                    (data.amount, src["account_no"]))
        cur.execute("UPDATE accounts SET balance = balance + %s, updated_at = now() WHERE account_no = %s",
                    (data.amount, data.to_account))
        cur.execute(
            """INSERT INTO transactions (from_account, to_account, amount, note)
               VALUES (%s, %s, %s, %s) RETURNING id, created_at""",
            (src["account_no"], data.to_account, data.amount, data.note.strip() or None),
        )
        tx = cur.fetchone()
        cur.execute("SELECT balance FROM accounts WHERE account_no = %s", (src["account_no"],))
        new_balance = cur.fetchone()["balance"]

    audit(user["username"], "TRANSFER", "SUCCESS", ip,
          f"{src['account_no']} -> {data.to_account} amount={data.amount}")
    return {"transaction_id": tx["id"], "created_at": tx["created_at"], "balance": new_balance}


# ---------------------------------------------------------------------------
# Nhan vien / Quan tri
# ---------------------------------------------------------------------------
@app.get("/api/accounts")
def list_accounts(request: Request, user: dict = Depends(require_roles(STAFF_ROLES))):
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            """SELECT a.account_no, u.username, u.full_name, u.is_active, a.balance, a.currency, a.updated_at
               FROM accounts a JOIN users u ON u.id = a.user_id ORDER BY a.account_no"""
        )
        rows = cur.fetchall()
    audit(user["username"], "LIST_ACCOUNTS", "SUCCESS", client_ip(request), f"{len(rows)} rows")
    return {"items": rows}


@app.get("/api/admin/users")
def list_users(user: dict = Depends(require_roles(["admin"]))):
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            """SELECT u.id, u.username, u.full_name, u.role, u.is_active, u.created_by, u.created_at,
                      a.account_no
               FROM users u LEFT JOIN accounts a ON a.user_id = u.id ORDER BY u.id"""
        )
        return {"items": cur.fetchall()}


@app.post("/api/admin/users", status_code=201)
def create_user(data: CreateUserIn, request: Request, user: dict = Depends(require_roles(["admin"]))):
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT 1 FROM users WHERE username = %s", (data.username,))
        if cur.fetchone():
            raise HTTPException(409, "Tên đăng nhập đã tồn tại.")
        cur.execute(
            """INSERT INTO users (username, password_hash, full_name, role, created_by)
               VALUES (%s, %s, %s, %s, %s) RETURNING id""",
            (data.username, pwd_context.hash(data.password), data.full_name, data.role, user["username"]),
        )
        uid = cur.fetchone()["id"]
        account_no = None
        if data.role == "customer":
            account_no = f"19008888{uid:02d}"
            cur.execute("INSERT INTO accounts (account_no, user_id, balance) VALUES (%s, %s, %s)",
                        (account_no, uid, data.initial_balance))
    audit(user["username"], "CREATE_USER", "SUCCESS", client_ip(request),
          f"user={data.username} role={data.role} account={account_no}")
    return {"username": data.username, "role": data.role, "account_no": account_no}


@app.patch("/api/admin/users/{username}/status")
def set_user_status(username: str, data: UserStatusIn, request: Request,
                    user: dict = Depends(require_roles(["admin"]))):
    if username == user["username"]:
        raise HTTPException(400, "Không thể tự khóa tài khoản đang đăng nhập.")
    with db() as conn, conn.cursor() as cur:
        cur.execute("UPDATE users SET is_active = %s WHERE username = %s RETURNING username",
                    (data.is_active, username))
        if not cur.fetchone():
            raise HTTPException(404, "Không tìm thấy người dùng.")
    audit(user["username"], "LOCK_USER" if not data.is_active else "UNLOCK_USER", "SUCCESS",
          client_ip(request), f"user={username}")
    return {"username": username, "is_active": data.is_active}


@app.get("/api/admin/audit-logs")
def audit_logs(request: Request, limit: int = 50, result: Optional[str] = None,
               user: dict = Depends(require_roles(["admin"]))):
    limit = max(1, min(limit, 500))
    sql = "SELECT id, event_time, username, action, status, client_ip, details FROM audit_logs"
    params: list = []
    if result in ("SUCCESS", "FAILED", "DENIED"):
        sql += " WHERE status = %s"
        params.append(result)
    sql += " ORDER BY event_time DESC LIMIT %s"
    params.append(limit)
    with db() as conn, conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
    return {"items": rows}
