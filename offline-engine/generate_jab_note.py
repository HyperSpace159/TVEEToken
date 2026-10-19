#!/usr/bin/env python3
"""
T-VEE Offline Cash Note & JAB Code Generator
สร้างภาพจำลองธนบัตรสีไร้ตัวเลข (Color-Coded Physical Token)
พร้อมเมทริกซ์รหัสสี JAB Code และตารางส่งมอบด้านหลังบัตร
"""

import os
import hashlib
import json
import time
from PIL import Image, ImageDraw, ImageFont

# กำหนดพาเลทสีมาตรฐาน T-VEE ตามสเปก JAB_CODE_SPEC.md
COLOR_PALETTES = {
    "ORANGE": {
        "name": "Amber Orange",
        "value": 1,
        "hex": "#FF6F00",
        "bg_rgb": (255, 111, 0),
        "text_color": (255, 255, 255)
    },
    "GREEN": {
        "name": "Emerald Green",
        "value": 5,
        "hex": "#00897B",
        "bg_rgb": (0, 137, 123),
        "text_color": (255, 255, 255)
    },
    "BLUE": {
        "name": "Cobalt Blue",
        "value": 20,
        "hex": "#1565C0",
        "bg_rgb": (21, 101, 192),
        "text_color": (255, 255, 255)
    },
    "PURPLE": {
        "name": "Imperial Purple",
        "value": 100,
        "hex": "#6A1B9A",
        "bg_rgb": (106, 27, 154),
        "text_color": (255, 255, 255)
    }
}

# แม่สีสำหรับสร้างพิกเซลใน JAB Code Matrix (CMYK-like 4/8 Colors)
JAB_PALETTE = [
    (0, 255, 255),   # Cyan
    (255, 0, 255),   # Magenta
    (255, 255, 0),   # Yellow
    (0, 0, 0),       # Black
    (255, 0, 0),     # Red
    (0, 255, 0),     # Green
    (0, 0, 255),     # Blue
    (255, 255, 255)  # White
]

def generate_jab_matrix(token_hash_hex, matrix_size=16):
    """
    สร้างเมทริกซ์พิกเซลสี JAB Code 16x16 จากชุด Hash
    """
    matrix = []
    hash_bytes = hashlib.sha256(token_hash_hex.encode()).digest()
    expanded = hashlib.sha512(hash_bytes).digest() * 4  # ขยายขนาดให้พอดี 256 cells
    
    idx = 0
    for r in range(matrix_size):
        row = []
        for c in range(matrix_size):
            # ดึงค่าสีจาก Palette 8 สี
            color_idx = expanded[idx] % len(JAB_PALETTE)
            row.append(JAB_PALETTE[color_idx])
            idx += 1
        matrix.append(row)
    return matrix

def render_note(denomination_key, vault_address, serial_nonce, output_dir):
    spec = COLOR_PALETTES[denomination_key]
    val = spec["value"]
    
    # 1. คำนวณ Token Hash
    payload = f"TVEE|{vault_address}|{val}|{serial_nonce}|{time.time()}"
    token_hash = "0x" + hashlib.sha256(payload.encode()).hexdigest()

    # ขนาดบัตร 800 x 400 พิกเซล
    width, height = 800, 400
    
    # ------------------ สร้างด้านหน้า (FRONT SIDE) ------------------
    front = Image.new("RGB", (width, height), spec["bg_rgb"])
    draw = ImageDraw.Draw(front)

    # วาดกรอบเส้นประและลวดลายความปลอดภัย
    draw.rectangle([15, 15, width - 15, height - 15], outline=(255, 255, 255), width=3)
    draw.rectangle([25, 25, width - 25, height - 25], outline=(255, 255, 255), width=1)

    # เรนเดอร์ JAB Code Matrix ทางด้านซ้าย
    jab_matrix = generate_jab_matrix(token_hash, matrix_size=16)
    cell_px = 12
    jab_start_x, jab_start_y = 60, 100
    
    # พื้นหลังกรอบ JAB Code สีขาว
    draw.rectangle(
        [jab_start_x - 8, jab_start_y - 8, jab_start_x + 16 * cell_px + 8, jab_start_y + 16 * cell_px + 8],
        fill=(255, 255, 255)
    )
    
    for r in range(16):
        for c in range(16):
            color = jab_matrix[r][c]
            draw.rectangle(
                [jab_start_x + c * cell_px, jab_start_y + r * cell_px, 
                 jab_start_x + (c + 1) * cell_px, jab_start_y + (r + 1) * cell_px],
                fill=color
            )

    # ข้อความระบบบนบัตร (ไร้ตัวเลขมูลค่าเงิน)
    title_text = "T-VEE PROTOCOL"
    sub_text = "NUMBERLESS PHYSICAL COLOR TOKEN"
    motto = "Code is Law • First-To-Sync Wins"
    vault_info = f"Vault Origin: {vault_address[:8]}...{vault_address[-6:]}"
    hash_info = f"Hash: {token_hash[:18]}..."

    draw.text((290, 80), title_text, fill=(255, 255, 255))
    draw.text((290, 120), sub_text, fill=(255, 255, 255))
    draw.text((290, 160), f"Color Grade: {spec['name']}", fill=(255, 255, 255))
    draw.text((290, 200), vault_info, fill=(240, 240, 240))
    draw.text((290, 235), hash_info, fill=(240, 240, 240))
    draw.text((290, 300), motto, fill=(255, 255, 200))

    front_path = os.path.join(output_dir, f"note_{denomination_key.lower()}_front.png")
    front.save(front_path)

    # ------------------ สร้างด้านหลัง (BACK SIDE - TRANSFER CHAIN) ------------------
    back = Image.new("RGB", (width, height), (245, 245, 245))
    draw_back = ImageDraw.Draw(back)
    draw_back.rectangle([15, 15, width - 15, height - 15], outline=spec["bg_rgb"], width=3)

    draw_back.text((50, 40), "OFFLINE TRANSFER CHAIN (PROOF OF HANDOVER)", fill=(30, 30, 30))
    draw_back.text((50, 65), "Record physical handovers to claim 10x Slashing penalty against counterfeits", fill=(100, 100, 100))

    # วาดตาราง 4 ช่อง
    table_x, table_y = 50, 110
    col_widths = [80, 220, 220, 180]
    headers = ["Epoch", "Sender Signature", "Receiver ID", "Date / Location"]
    
    cur_x = table_x
    for i, h in enumerate(headers):
        draw_back.rectangle([cur_x, table_y, cur_x + col_widths[i], table_y + 35], fill=spec["bg_rgb"])
        draw_back.text((cur_x + 10, table_y + 10), h, fill=(255, 255, 255))
        cur_x += col_widths[i]

    for row in range(1, 5):
        cur_x = table_x
        row_y = table_y + row * 45
        for i, w in enumerate(col_widths):
            draw_back.rectangle([cur_x, row_y, cur_x + w, row_y + 45], outline=(180, 180, 180), width=1)
            if i == 0:
                draw_back.text((cur_x + 25, row_y + 15), f"#{row}", fill=(60, 60, 60))
            cur_x += w

    draw_back.text((50, 350), f"Digital Anchor: {token_hash}", fill=(120, 120, 120))

    back_path = os.path.join(output_dir, f"note_{denomination_key.lower()}_back.png")
    back.save(back_path)

    metadata = {
        "color": spec["name"],
        "targetValue": val,
        "tokenHash": token_hash,
        "vaultOrigin": vault_address,
        "serialNonce": serial_nonce,
        "frontImage": front_path,
        "backImage": back_path
    }

    meta_path = os.path.join(output_dir, f"note_{denomination_key.lower()}_meta.json")
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2, ensure_ascii=False)

    print(f"Generated {spec['name']} Note: {token_hash[:20]}...")
    return metadata

if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "..", "sample_notes")
    os.makedirs(out, exist_ok=True)
    
    mock_vault = "0x71C6619082269E7e8e788e01083416F8C39D5514"
    for idx, key in enumerate(COLOR_PALETTES.keys()):
        render_note(key, mock_vault, 1000 + idx, out)
    print(f"\nAll 4 Denomination Notes rendered into: {os.path.abspath(out)}")
