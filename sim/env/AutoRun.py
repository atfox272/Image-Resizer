from PIL import Image
import subprocess
import shutil
import os

def to_hex(value, width_bits):
    """Chuyển số nguyên sang chuỗi hex với padding 0 theo số bit (width_bits)."""
    hex_width = width_bits // 4   # 4 bit = 1 hex digit
    return f"{value:0{hex_width}X}"

def process_image(input_path):
    # Đọc ảnh
    img = Image.open(input_path)

    # Lấy width và height
    width, height = img.size

    # Ghi ImgInfo.txt
    with open("env/ImgInfo.txt", "w") as f_info:
        f_info.write(to_hex(width, 16) + "\n")   # Width 16-bit hex
        f_info.write(to_hex(height, 16) + "\n")  # Height 16-bit hex

    # Convert sang grayscale
    gray_img = img.convert("L")  

    # Ghi pixel ra PxlInfo.txt
    with open("env/PxlInfo.txt", "w") as f_px:
        for y in range(height):
            for x in range(width):
                pixel_value = gray_img.getpixel((x, y))
                x_hex = to_hex(x, 16)
                y_hex = to_hex(y, 16)
                px_hex = to_hex(pixel_value, 8)
                f_px.write(f"{x_hex}{y_hex}{px_hex}\n")

def from_hex(hex_str):
    """Chuyển chuỗi hex sang số nguyên."""
    return int(hex_str, 16)

def reconstruct_image(px_file, output_image, write_imginfo=True):
    pixels = []

    # Đọc toàn bộ pixel từ file
    with open(px_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//"):  # bỏ qua comment và dòng trống
                continue
            # X: 4 hex, Y: 4 hex, Pixel: 2 hex
            x_hex = line[0:4]
            y_hex = line[4:8]
            px_hex = line[8:10]

            x = from_hex(x_hex)
            y = from_hex(y_hex)
            val = from_hex(px_hex)

            pixels.append((x, y, val))

    # Tìm width và height từ X_max, Y_max
    max_x = max(p[0] for p in pixels)
    max_y = max(p[1] for p in pixels)
    width = max_x + 1
    height = max_y + 1

    # Tạo ảnh grayscale
    img = Image.new("L", (width, height))

    # Đặt pixel
    for x, y, val in pixels:
        img.putpixel((x, y), val)

    # Lưu ảnh
    img.save(output_image)
    print(f"Image reconstructed: {output_image}, size = {width}x{height}")

    # Nếu muốn thì ghi thêm ImgInfo.txt
    if write_imginfo:
        with open("ImgInfo.txt", "w") as f_info:
            f_info.write(f"{width:04X}\n")
            f_info.write(f"{height:04X}\n")

if __name__ == "__main__":
    src_folder = "env/dataset/Au"
    dst_path = "env/InputImg.jpg"
    output_folder = "env/output"
    os.makedirs(output_folder, exist_ok=True)

    # Get the first 10 images
    src_files = sorted([f for f in os.listdir(src_folder) if f.lower().endswith(('.jpg', '.jpeg', '.png'))])[:7400]

    for src_file in src_files:
        src_path = os.path.join(src_folder, src_file)

        # Copy file và đổi tên
        shutil.copy(src_path, dst_path)

        # Thực thi hàm với ảnh mới
        process_image(dst_path)

        subprocess.run(["make"], check=True)

        # Tạo đường dẫn output
        output_image_path = os.path.join(output_folder, src_file)

        # Gọi reconstruct_image với file pixel đã resize
        reconstruct_image("env/RszPxlInfo.txt", output_image_path)
    