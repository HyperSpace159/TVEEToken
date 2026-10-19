# JAB Code & Color Token Specification 🎨
> **ข้อกำหนดทางเทคนิค: ระบบบาร์โค้ดสีความจุสูง JAB Code และสเปกธนบัตรสีไร้ตัวเลข**
> เวอร์ชัน: 1.0.0 (สากล)

---

## 1. บทนำ (Overview)
เพื่อทำลายกำแพงเทคโนโลยี (Zero Tech Barrier) ระบบ T-VEE ปฏิเสธการใช้ตัวเลขระบุมูลค่าบนธนบัตร แต่ใช้ **"การแยกแยะด้วยเฉดสีจำเพาะ (Color Palette Differentiation)"** ผนวกกับ **JAB Code (Just Another Barcode - ISO/IEC 23634)** ซึ่งเป็นรหัสเมทริกซ์ 2 มิติหลายสี (Color 2D Barcode) ที่มีความจุสูงกว่า QR Code ขาวดำทั่วไป 3-5 เท่า และทนทานต่อการบิดเบี้ยวหรือเปื้อนในตลาดสด

---

## 2. ตารางเฉดสีมาตรฐานธนบัตรไร้ตัวเลข (Universal Color Palette)

| ชื่อสัญลักษณ์สี | โค้ดสี HEX | ค่าสี CMYK | มูลค่าตรึงระบบ (Target TVEE) | การใช้งานในชีวิตประจำวัน |
|---|---|---|---|---|
| **Amber Orange** 🟠 | `#FF6F00` | `C:0 M:70 Y:100 K:0` | **1 T-VEE** | ซื้อพริก, ไข่ไก่, ค่าวินมอเตอร์ไซค์ |
| **Emerald Green** 🟢 | `#00897B` | `C:85 M:10 Y:60 K:0` | **5 T-VEE** | อาหารจานเดียว, ข้าวแกง, ก๋วยเตี๋ยว |
| **Cobalt Blue** 🔵 | `#1565C0` | `C:95 M:60 Y:0 K:0` | **20 T-VEE** | วัตถุดิบทำกับข้าว, ค่ายา, สินค้าโชห่วย |
| **Imperial Purple** 🟣 | `#6A1B9A` | `C:70 M:95 Y:0 K:0` | **100 T-VEE** | ค้าส่ง, จ่ายค่าแรงรายวัน, ปุ๋ยเกษตร |

---

## 3. สถาปัตยกรรมเมทริกซ์ JAB Code (Matrix Payload & Cryptography)

JAB Code บนหน้าธนบัตรจะใช้รูปแบบ **4-Color หรือ 8-Color Matrix** โดยฝังชุดข้อมูลโครงสร้างไบนารีขนาดกะทัดรัด (Compact Binary Struct):

```
+-------------------------------------------------------+
| Field Name        | Type    | Size    | Description    |
+-------------------------------------------------------+
| Protocol_ID       | uint8   | 1 Byte  | 0xEE (T-VEE)   |
| Vault_Origin      | address | 20 Bytes| ผู้ค้ำประกันพิมพ์ |
| Denomination_ID   | uint8   | 1 Byte  | 1, 5, 20, 100  |
| Serial_Nonce      | uint64  | 8 Bytes | เลขสุ่มกันซ้ำ  |
| Signature_R_S     | bytes64 | 64 Bytes| ลายเซ็นดิจิทัล |
+-------------------------------------------------------+
```

### การคำนวณ Token Hash บน Smart Contract:
```solidity
bytes32 tokenHash = keccak256(
    abi.encodePacked(
        protocolId, 
        vaultOrigin, 
        denominationId, 
        serialNonce, 
        signature
    )
);
```

---

## 4. กลไกป้องกันการปลอมแปลงทางกายภาพ (Anti-Counterfeit Layers)
1. **Micro-Chroma Alignment:** รหัส JAB Code จะพิมพ์ที่ความละเอียดขั้นต่ำ 300-600 DPI การสแกนด้วยเครื่องถ่ายเอกสารทั่วไปจะไม่สามารถเก็บค่าความลึกสี (Color Gamut Spectrum) ได้ครบ ทำให้ Machine Learning บนสมาร์ตโฟนปฏิเสธการอ่านรหัสทันที
2. **First-to-Sync Wins Rule:** หากมีการคัดลอกรหัสซ้ำ กฎบล็อกเชนจะให้สิทธิ์เฉพาะผู้สแกนคนแรก คนที่ถือใบก๊อปปี้จะสามารถกดสืบสายโซ่ริบทรัพย์คลังต้นทางได้ 10 เท่าทันที!
