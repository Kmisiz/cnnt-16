# Phiếu giao đề 16 — Thiết kế hạ tầng CNTT an toàn cho ngân hàng số

> Chép nguyên văn từ ảnh [phieu-de-16.png](CNNT_Final_project/cnnt-16/yeu-cau-goc/phieu-de-16.png) (ảnh chụp file "Phieu giao de tai.docx" do giảng viên phát). Không sửa tay nội dung. Đoạn văn của đề trước ở đầu ảnh và tiêu đề "Phiếu giao đề 17" ở cuối ảnh không thuộc đề này, đã bỏ.
> Cột "Mã" do nhóm gán để các tài liệu khác trích dẫn; phần còn lại là nguyên văn.

Lớp: .................. Nhóm: .................. Hạn nộp: ..................

## 1. Bài toán và phạm vi

Ngân hàng số giả định; chỉ nghiên cứu hạ tầng và dữ liệu giả, không triển khai giao dịch tài chính thật.

## 2. Yêu cầu bắt buộc

| Mã | Nguyên văn |
|---|---|
| B1 | Vẽ kiến trúc nhiều lớp gồm khách hàng, vùng công khai, ứng dụng, dữ liệu và quản trị; liệt kê ít nhất 4 nguy cơ. |
| B2 | Thiết kế xác thực, phân quyền theo vai trò, mã hóa, sao lưu và giám sát; chỉ rõ biện pháp cho từng nguy cơ. |
| B3 | Dựng mô hình nhỏ với Web, vùng dữ liệu và máy quản trị; áp dụng chính sách mặc định hạn chế, chỉ mở luồng cần thiết. |
| B4 | Minh họa xác thực, từ chối truy cập và ghi log; phục hồi dữ liệu mẫu. Phân biệt biện pháp đã demo với biện pháp chỉ đề xuất. |

## 3. Kiểm thử nghiệm thu tối thiểu

| Mã | Nguyên văn |
|---|---|
| KT1 | Khách hợp lệ dùng được chức năng được cấp. |
| KT2 | Máy vùng công khai không kết nối trực tiếp đến cổng dữ liệu bị chặn. |
| KT3 | Đăng nhập sai có bằng chứng log; phục hồi dữ liệu và kiểm tra quyền. |

## 4. Phân công và minh chứng cá nhân

| Mã | Nguyên văn |
|---|---|
| SV1 | Kiến trúc và phân tích nguy cơ. Nộp file hoặc số liệu kèm giải thích phần thực hiện. |
| SV2 | Cấu hình phân vùng, lọc truy cập. Nộp file hoặc số liệu kèm giải thích phần thực hiện. |
| SV3 | Dựng xác thực, dữ liệu và sao lưu. Nộp file hoặc số liệu kèm giải thích phần thực hiện. |
| SV4 | Kiểm thử chính sách và nhật ký. Nộp file hoặc số liệu kèm giải thích phần thực hiện. |

## 5. Sản phẩm và bảo vệ

Nộp hồ sơ chung ở đầu tài liệu, kèm toàn bộ cấu hình/mô hình và bằng chứng KT1–KT3 của phiếu này. Nhóm 5 người áp dụng phần việc SV5 trong hướng dẫn chung.

### Câu hỏi chuẩn bị

Nếu Web bị chiếm quyền, lớp nào giúp hạn chế truy cập kho dữ liệu?

### Mở rộng tự chọn

Triển khai và kiểm thử một phương án thay thế cho một thành phần của đề; so sánh bằng cùng tiêu chí và số liệu.
