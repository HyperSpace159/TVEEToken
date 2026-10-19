# T-VEE & T-AAM Protocol 🌐
> **Global Open-Source Financial Protocol: Decentralized Operating System & Numberless Offline Cash Architecture**
> Version: 1.0.0 (Immutable Code is Law)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-^0.8.20-blue.svg)](https://soliditylang.org/)
[![Layer 2](https://img.shields.io/badge/L2-Arbitrum%20%7C%20Optimism%20%7C%20ZK--Rollup-purple.svg)](#)

---

## 📖 สารบัญ (Table of Contents)
- [บทนำและปรัชญา (Introduction & Philosophy)](#-บทนำและปรัชญา)
- [สถาปัตยกรรมระบบ (System Architecture)](#-สถาปัตยกรรมระบบ)
- [โครงสร้างโปรเจกต์ (Repository Structure)](#-โครงสร้างโปรเจกต์)
- [Smart Contracts](#-smart-contracts)
- [คู่มือการพิมพ์ธนบัตรสีชุมชน (Community Local Printing Guide)](#-คู่มือการพิมพ์ธนบัตรสีชุมชน)
- [แนวทางการติดตั้งและทดสอบ (Getting Started)](#-แนวทางการติดตั้งและทดสอบ)
- [ร่วมพัฒนา (Contributing)](#-ร่วมพัฒนา)

---

## 🏛 บทนำและปรัชญา
**T-VEE Protocol** นำทฤษฎี **Freigeld (Free Money)** ของ Silvio Gesell มาผสานกับ **Decentralized Ledger & Cryptography** 
- **Dynamic Demurrage (ภาษีติดลบ):** บังคับให้เงินมีต้นทุนตามกาลเวลาเพื่อเร่งความเร็วในการหมุนเวียน (Velocity) สลายการกักตุนเก็งกำไร
- **Denomination-Free Color Cash:** ปฏิวัติเงินสดทางกายภาพด้วย "ธนบัตรสีพื้นไร้ตัวเลข" ร่วมกับเทคโนโลยี **JAB Code (CMYK Matrix)** เชื่อมต่อชาวบ้านเข้าสู่ระบบเศรษฐกิจเสรีแบบ Zero Tech Barrier
- **T-AAM Marketplace:** ตลาดแลกเปลี่ยนสภาพคล่องสากล ซื้อขาย Credit Term Invoice NFT เพื่อแก้ปัญหาเงินจมของ SME
- **Decentralized Slashing:** ระบบ First-to-sync ชนะ และริบทรัพย์ทุนใหญ่คนโกง 10 เท่าเข้ากระเป๋าชาวบ้านโดยตรง

---

## 📂 โครงสร้างโปรเจกต์
```tree
t-vee-protocol/
├── contracts/                  # Solidity Core Smart Contracts
│   ├── TVEEToken.sol           # โทเคนหลัก: Rebase, Demurrage & Retail Threshold
│   ├── OfflineNoteSync.sol     # ตัวคุมรหัส JAB Code, First-to-sync & 10x Slashing
│   ├── TAAMMarketplace.sol     # ตลาดซื้อขาย Credit Term Invoice NFT
│   └── interfaces/             # Interfaces ต่างๆ
├── docs/                       # เอกสารข้อกำหนดและสเปก
│   ├── JAB_CODE_SPEC.md        # มาตรฐานรหัสสี JAB Code และ Color Palette
│   └── PRINTING_GUIDE.md       # คู่มือการพิมพ์ธนบัตรสีสำหรับชุมชน
├── circuits/                   # ZK-Rollup Proofs (Layer 2 Batching)
├── scripts/                    # Deploy & Sync Automation Scripts
├── test/                       # Unit tests & Simulation
├── hardhat.config.js           # Hardhat Configuration
└── README.md
```

---

## 📜 การติดตั้งและเริ่มพัฒนา
```bash
git clone https://github.com/your-org/t-vee-protocol.git
cd t-vee-protocol
npm install
npx hardhat test
```
