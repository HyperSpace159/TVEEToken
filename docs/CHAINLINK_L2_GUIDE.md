# Chainlink Data Feeds & Arbitrum Sepolia Deployment Guide 🌐
> **คู่มือการเชื่อมต่อ Chainlink Oracle และการขอรับ Testnet ETH เพื่อ Deploy สู่ Arbitrum Sepolia**
> Protocol Edition: Chainlink AggregatorV3 Integrated (Version 2.1)

---

## 1. ข้อมูลเครือข่าย Arbitrum Sepolia (Network Configuration)

หากต้องการเพิ่มเครือข่ายลงในกระเป๋า Metamask:
* **Network Name:** Arbitrum Sepolia
* **RPC URL:** `https://sepolia-rollup.arbitrum.io/rpc`
* **Chain ID:** `421614`
* **Currency Symbol:** `ETH`
* **Block Explorer:** `https://sepolia.arbiscan.io/`

---

## 2. แหล่งรับเหรียญทดสอบฟรี (Free Testnet Faucets)

คุณสามารถกดรับเหรียญฟรีเพื่อใช้เป็นค่าแก๊สในการ Deploy ได้จากลิงก์เหล่านี้ (แนะนำ Chainlink เป็นหลัก):

1. **🔗 Chainlink Official Faucet (แนะนำที่สุด):**
   * ลิงก์: 👉 **[https://faucets.chain.link/](https://faucets.chain.link/)**
   * วิธีการ: เชื่อมต่อกระเป๋า Metamask -> เลือกเครือข่าย **Arbitrum Sepolia** -> ติ๊กรับ **0.1 Arbitrum Sepolia ETH** และ **20 Test LINK** -> กด "Send request"
2. **🦊 QuickNode Arbitrum Sepolia Faucet:**
   * ลิงก์: [https://faucet.quicknode.com/arbitrum/sepolia](https://faucet.quicknode.com/arbitrum/sepolia)
3. **⚡ Alchemy Arbitrum Sepolia Faucet:**
   * ลิงก์: [https://www.alchemy.com/faucets/arbitrum-sepolia](https://www.alchemy.com/faucets/arbitrum-sepolia)

---

## 3. พิกัด Chainlink Data Feed Contracts บน Arbitrum Sepolia

สัญญาของเราจะดึงราคาแบบเรียลไทม์จาก Chainlink Contract Addresses เหล่านี้:

| คู่เหรียญ (Asset Pair) | Decimals | Chainlink Contract Address (Arbitrum Sepolia) |
|---|---|---|
| **ETH / USD** | 8 | `0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165` |
| **BTC / USD** | 8 | `0x56a43EB56Da12C0dc180F83e0Be3041451a7b6A8` |
| **LINK / USD** | 8 | `0xb113F5A928BCfF189C998ab20d753a47F9dE5A61` |

---

## 4. วิธีการสั่ง Deploy ขึ้น Arbitrum Sepolia จริง

เมื่อมีเหรียญในกระเป๋าแล้ว:
1. ใส่ Private Key ในไฟล์ `.env`:
   ```env
   PRIVATE_KEY=รหัส_Private_Key_ของคุณ
   ARBITRUM_SEPOLIA_RPC=https://sepolia-rollup.arbitrum.io/rpc
   ```
2. รันคำสั่งยิง Deploy:
   ```bash
   npx hardhat run scripts/deploy_l2.js --network arbitrumSepolia
   ```
