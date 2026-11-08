# HƯỚNG DẪN NHIỆM VỤ & KỊCH BẢN THUYẾT TRÌNH: ĐỨC (SV4)
**Đề tài 16: Thiết kế hạ tầng CNTT an toàn cho Ngân hàng số — Ngân hàng Số Mười Sáu (Mười Sáu Bank)**  
**Chuyên trách:** Phân hệ Nhật ký an ninh (Audit Logging), Giám sát an toàn thông tin & Chống chối bỏ (Non-repudiation).

---

## PHẦN 1: TỔNG QUAN VAI TRÒ CỦA ĐỨC TRONG NHÓM

Trong đề tài Ngân hàng Số Mười Sáu, nhiệm vụ của Đức tập trung vào **"Tính Toàn vẹn (Integrity) và Tính Chống chối bỏ (Non-repudiation)"** — một trong những tiêu chuẩn an toàn thông tin khắt khe nhất của ngành tài chính ngân hàng (theo Thông tư 09/2020/TT-NHNN và PCI-DSS).

Hệ thống ghi nhận mọi biến động từ người dùng và tự động lưu vết tại 3 tầng:
1. **Tầng Cơ sở dữ liệu (`vps3-data-db` - PostgreSQL 16):** Bảng `audit_logs` được phân quyền **Đặc quyền tối thiểu (Least Privilege)**: Ứng dụng chỉ được phép ghi (`INSERT`) và đọc (`SELECT`), tuyệt đối **không có quyền xóa (`DELETE`) hay sửa (`UPDATE`)**. Dù hacker có chiếm được quyền điều khiển web server cũng không thể xóa nhật ký để phi tang dấu vết.
2. **Tầng Xử lý nghiệp vụ (`vps2-app-api` - FastAPI):** Mỗi khi có sự kiện (Đăng nhập, Đăng xuất, Chuyển tiền, Khóa tài khoản, Nhập sai mật khẩu, Truy cập trái phép), backend tự động lưu lại: thời gian thực, tên người dùng, hành động, kết quả (`SUCCESS`, `FAILED`, `DENIED`), IP gọi đến và chi tiết giao dịch.
3. **Tầng Giao diện hiển thị (`vps0-web-public` - Web Admin):** Cung cấp Dashboard **"Nhật ký an ninh"** trực quan tại `/admin/` cho phép lọc nhanh các vi phạm an toàn theo thời gian thực.

---

### 1.1. Lệnh PowerShell dành cho Đức (kết nối vào Database `vps3` từ máy tính ở nhà)
Đức mở **PowerShell** trên máy tính cá nhân ở nhà và copy paste lệnh sau:
```powershell
ssh -J duc@34.87.139.11 duc@10.10.10.30
```
Khi vào được `vps3-data-db`, Đức có thể xem trực tiếp bảng `audit_logs` trong CSDL bằng lệnh:
```bash
sudo -u postgres psql -d digital_bank -c "SELECT event_time, username, action, status, details FROM audit_logs ORDER BY event_time DESC LIMIT 10;"
```

---

## PHẦN 2: BẢNG CÁC SỰ KIỆN AN NINH ĐỨC CẦN NẮM RÕ

Khi giảng viên nhìn vào màn hình Nhật ký an ninh, Đức cần giải thích được ý nghĩa của các dòng sự kiện:

| Hành động (`Action`) | Kết quả (`Status`) | Màu sắc | Ý nghĩa nghiệp vụ trong ngân hàng |
| :--- | :--- | :--- | :--- |
| **`LOGIN`** | `SUCCESS` | Xanh lá | Đăng nhập thành công vào hệ thống (ghi nhận rõ vai trò `customer` hay `admin`). |
| **`LOGIN`** | `FAILED` | Vàng cam | Đăng nhập thất bại do nhập sai mật khẩu (dùng để phát hiện tấn công dò mật khẩu Brute-force). |
| **`LOGIN`** | `LOCKED` | Đỏ | Tài khoản đã bị quản trị viên khóa nhưng vẫn cố tình đăng nhập. |
| **`TRANSFER`** | `SUCCESS` | Xanh lá | Giao dịch chuyển tiền nội bộ thành công (ghi nhận số tiền và tài khoản nhận để chống chối bỏ). |
| **`RBAC`** | `DENIED` | Đỏ | **Cảnh báo an ninh nghiêm trọng:** Người dùng phân quyền thấp (ví dụ `user1`) cố tình dùng công cụ gọi trộm vào API quản trị (`/api/admin/users`). |
| **`LOCK_USER`** / **`UNLOCK_USER`** | `SUCCESS` | Xanh lá | Quản trị viên thực hiện khóa khẩn cấp hoặc mở lại tài khoản cho nhân sự/khách hàng. |
| **`CREATE_USER`** | `SUCCESS` | Xanh lá | Quản trị viên cấp mới một tài khoản nhân viên hoặc khách hàng vào hệ thống. |
| **`LOGOUT`** | `SUCCESS` | Xanh lá | Người dùng kết thúc phiên làm việc an toàn. |

---

## PHẦN 3: KỊCH BẢN 3 BƯỚC THUYẾT TRÌNH & DEMO CỦA ĐỨC

Khi đến lượt Đức trình bày trước giảng viên, Đức đứng trước màn hình máy chiếu và thực hiện tuần tự 3 bước sau:

### Bước 1: Mở đầu giới thiệu (Đọc mẫu tự tin)
> *"Kính thưa thầy/cô, em là Đức, phụ trách phân hệ **Nhật ký an ninh (Audit Logging) và Giám sát an toàn** của Ngân hàng Số Mười Sáu. Mục tiêu của phân hệ này là đảm bảo mọi thao tác quan trọng từ tài chính đến quản trị đều được ghi vết chính xác theo thời gian thực, phục vụ công tác giám sát, điều tra số (Forensics) và chống chối bỏ trách nhiệm."*

---

### Bước 2: Thao tác trực tiếp trên giao diện Web Admin
Đức mở trình duyệt tại địa chỉ: 👉 **`https://34.124.217.241/admin/`** (đăng nhập tài khoản `admin` / `Admin@123`), bấm vào mục **"Nhật ký an ninh"**:

1. **Demo bộ lọc an ninh thông minh:**
   * Tại ô **"Kết quả:"**, Đức bấm chọn **`Bị từ chối (DENIED)`**:
     * *Đức chỉ vào màn hình và nói:* *"Thưa thầy cô, khi lọc theo DENIED, hệ thống hiển thị ngay các cảnh báo màu đỏ. Ví dụ tại đây, tài khoản `user1` là khách hàng cá nhân nhưng đã cố tình gửi request can thiệp vào đường dẫn `/api/admin/users`. Hệ thống kiểm soát truy cập RBAC đã chặn đứng lại và ghi vết địa chỉ IP để xử lý."*
   * Đức chọn tiếp **`Thất bại (FAILED)`**:
     * *Đức nói:* *"Đây là các lần đăng nhập sai mật khẩu, giúp trung tâm an ninh phát hiện sớm các cuộc tấn công dò quét mật khẩu."*
   * Đức chọn lại **`Tất cả`**.

2. **Demo tính năng ghi vết thời gian thực (Real-time Audit):**
   * Đức nhờ bạn Khánh (hoặc bạn Hiếu) ở máy bên cạnh mở tab khách hàng bấm chuyển tiền thử 500.000 VND (hoặc cố tình gõ sai mật khẩu 1 lần).
   * Sau đó tại màn hình của mình, Đức bấm nút **"Làm mới"**.
   * Dòng giao dịch vừa thực hiện lập tức nhảy lên đầu danh sách kèm đúng giây, đúng IP và chi tiết số tiền!
   * *Đức kết luận:* *"Như thầy cô thấy, hệ thống ghi nhận tức thời từng hành vi của người dùng mà không có độ trễ."*

---

### Bước 3: Chứng minh tính bất biến trong Cơ sở dữ liệu (Ăn trọn điểm 10)
Giảng viên có thể sẽ hỏi: *"Nếu kẻ tấn công xâm nhập được vào máy chủ ứng dụng thì chúng có xóa được dữ liệu nhật ký này đi để phi tang dấu vết không?"*

Đức tự tin trả lời:
> *"Dạ thưa thầy/cô, hoàn toàn không thể xóa được ạ! Hệ thống của nhóm em áp dụng nguyên tắc **Đặc quyền tối thiểu (Least Privilege)** trên PostgreSQL."*

Để chứng minh, Đức mở cửa sổ dòng lệnh (Terminal) và chạy lệnh thử xóa bảng `audit_logs` bằng tài khoản của ứng dụng (`bank_app`):
```bash
PGPASSWORD='AppSecretPass_2026!' psql -h 10.10.10.30 -U bank_app -d digital_bank -c "DELETE FROM audit_logs;"
```
$\rightarrow$ **Kết quả trên terminal hiển thị:**
```text
ERROR:  permission denied for table audit_logs
```
*Đức dõng dạc chốt lại:*
> *"Tài khoản của backend chỉ có quyền `INSERT` và `SELECT`. Lệnh `DELETE`, `UPDATE` hay `TRUNCATE` đều bị CSDL từ chối triệt để. Do đó lịch sử nhật ký của ngân hàng được bảo vệ bất biến 100% ạ!"*

---

## PHẦN 4: BỘ CÂU HỎI PHỤ GIẢNG VIÊN HAY HỎI & CÂU TRẢ LỜI SẴN

**Câu hỏi 1: Tại sao trong bảng nhật ký lại cần lưu cả địa chỉ IP của người dùng?**
* **Đức trả lời:** Dạ thưa thầy/cô, việc lưu IP giúp xác định chính xác thiết bị thực hiện giao dịch. Nếu cùng một tài khoản mà trong 5 phút đăng nhập từ 2 địa chỉ IP khác nhau (ví dụ một IP ở Hà Nội, một IP ở nước ngoài), hệ thống sẽ cảnh báo tài khoản có nguy cơ bị lộ thông tin hoặc bị chiếm quyền.

**Câu hỏi 2: Nhật ký lưu nhiều thì có sợ làm chậm database hay hết ổ cứng không?**
* **Đức trả lời:** Dạ thưa thầy/cô:
  1. Nhóm đã đánh chỉ mục (Index) trên cột `event_time DESC` nên việc truy vấn và hiển thị trên web luôn đạt tốc độ dưới 10 mili-giây.
  2. Định kỳ hàng tháng, hệ thống có chính sách lưu trữ lạnh (Cold Storage): các bản ghi cũ sẽ được kết xuất, nén mã hóa lưu vào kho lưu trữ riêng, đảm bảo CSDL hoạt động nhẹ nhàng.
