# Hồ sơ chung — Yêu cầu báo cáo

> Bản sao nguyên văn Google Doc của giảng viên, lấy ngày 2026-11-02 qua export Markdown.
> Nguồn: https://docs.google.com/document/d/179gVMidB5ST0PVlBKUbF-zTi44sDv8CPaiyj_gCI2wI/edit
> Chỉ sửa định dạng: 5 ảnh mũi tên giữa các cột bảng test thay bằng `→`; heading lỗi ở mục III chuẩn hóa lại. Không sửa nội dung. Khi Doc gốc thay đổi, tải lại và ghi ngày mới; không chỉnh tay file này.

## I. Danh mục hồ sơ cần nộp

### 1. Báo cáo chính (Report)

- **Độ dài:** 12–18 trang cho phần nội dung chính (phụ lục cấu hình, log kỹ thuật được để riêng và không tính vào giới hạn trang này).
- **Các mục bắt buộc:**
  - Yêu cầu bài toán & Phạm vi
  - Giả định thiết kế
  - Kiến trúc hệ thống
  - Quá trình triển khai chi tiết
  - Kịch bản & Kết quả kiểm thử
  - Đánh giá kết quả
  - Tài liệu tham khảo

### 2. Tài liệu kỹ thuật & Mã nguồn

- **Thiết kế & Quy hoạch:** Sơ đồ hệ thống, bảng phân bổ tài nguyên, bảng chia IP, ma trận phân quyền.
- **File kỹ thuật:** File mô phỏng (.pkt), file cấu hình thiết bị (config files), scripts hoặc mã nguồn liên quan.
- **File README:**
  - Ghi rõ phiên bản phần mềm/công cụ sử dụng (Packet Tracer, OS, thư viện...).
  - Hướng dẫn từng bước cách dựng lại hệ thống từ đầu.
  - Hướng dẫn cách chạy các bài kiểm thử.

### 3. Bảng kiểm thử (Test Cases)

- **Cấu trúc bảng gồm 6 cột:** Đầu vào → Thao tác thực hiện → Kết quả mong đợi → Kết quả thực tế → Đánh giá (Đạt / Chưa đạt) → Bằng chứng xác thực.
- **Bằng chứng:** Ảnh chụp màn hình hoặc log lệnh bắt buộc phải có **dấu thời gian (timestamp)** rõ ràng.
- **Dữ liệu gốc:** Nộp kèm file log/dữ liệu đo thô nếu đề tài có phần đo lường hiệu năng.

### 4. Video Demo & Phân công công việc

- **Video demo:** Thời lượng giới hạn trong **5–7 phút**, quay rõ các tính năng chính và kết quả kiểm thử.
- **Phiếu đánh giá đóng góp cá nhân:** Mỗi thành viên phải kê khai:
  - Nhiệm vụ phụ trách.
  - Tên các file/sản phẩm cụ thể mình tạo ra.
  - Bằng chứng thực hiện công việc.
  - Các lỗi/sự cố phát sinh đã tự xử lý.
- **Yêu cầu bắt buộc:** Mỗi người phải có **sản phẩm kỹ thuật riêng**, không được nhận chung chung vào phần của người khác.

## II. Quy tắc triển khai & Trách nhiệm cá nhân

- **Dữ liệu & Môi trường:** Chỉ dùng dữ liệu giả lập (mock data) và môi trường thử nghiệm được phép. Không bắt buộc phải mua phần cứng thật, thuê Cloud có phí hay dựng trọn vẹn nghiệp vụ ứng dụng.
- **Minh bạch nguồn tham khảo:** Ghi rõ nguồn gốc mọi đoạn mã, cấu hình tham khảo từ bên ngoài và nêu rõ các phần có sự hỗ trợ của AI.
- **Khả năng giải trình:** Từng thành viên phải nắm vững phần việc của mình để sẵn sàng trả lời phản biện, trực tiếp chỉnh sửa và chạy lại cấu hình/code khi được yêu cầu.

## III. Tiến độ và đánh giá

### 1. Các mốc thực hiện

*(Mục này trống trong bản gốc.)*

### Rubric đề xuất cần giảng viên chốt

- Tỷ lệ bên dưới áp dụng bên trong điểm bài thi, khác với tỷ trọng cuối kỳ 50% của học phần. Chưa coi rubric là quy định đã phê duyệt.

| Tiêu chí | Điểm tối đa |
| :---- | :---- |
| Nhóm — yêu cầu, giả định và lựa chọn giải pháp | 10 |
| Nhóm — thiết kế kiến trúc và tính toán có căn cứ | 10 |
| Nhóm — mô hình triển khai, giải thích các thông số | 10 |
| Nhóm — kiểm thử, số liệu và đánh giá giới hạn | 10 |
| Nhóm — báo cáo, cấu hình và hồ sơ minh chứng | 10 |
| Cá nhân — hoàn thành phần kỹ thuật có bằng chứng | 15 |
| Cá nhân — giải thích và thao tác trực tiếp | 15 |
| Cá nhân — vấn đáp về kiến trúc và tình huống thay đổi | 20 |

- Điểm bài thi thang 10 = (điểm nhóm + điểm cá nhân) / 10. Phần đóng góp vào điểm học phần = điểm bài thi × 0,5. Chỉ thực hiện quy đổi này khi rubric trên được giảng viên chốt.

### 2. Bảo vệ và phân công

- Mỗi sinh viên trình bày phần việc, mở minh chứng và thực hiện một thao tác hoặc xử lý một thay đổi nhỏ. Giảng viên có thể hỏi cả kiến trúc chung. Câu hỏi trên phiếu là câu hỏi chuẩn bị, không phải toàn bộ câu hỏi bảo vệ.
- Các vai trò SV1–SV4 là khung phân công; nhóm điền họ tên và mã sinh viên vào README.
- Mọi thành viên cùng tham gia kiểm thử, không giao ai chỉ làm slide hoặc báo cáo.
- Lịch bảo vệ thông báo riêng. Mức nâng cao trên từng phiếu là lựa chọn sau khi hoàn thành yêu cầu bắt buộc, không thay thế minh chứng lõi và không tự động được cộng điểm.
- Bài tập của nhóm sẽ nộp lên file driver mà giảng viên cung cấp.
