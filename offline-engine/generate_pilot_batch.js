const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const COLOR_PALETTES = {
  ORANGE: { name: "Amber Orange", value: 1, hex: "#FF6F00" },
  GREEN: { name: "Emerald Green", value: 5, hex: "#00897B" },
  BLUE: { name: "Cobalt Blue", value: 20, hex: "#1565C0" },
  PURPLE: { name: "Imperial Purple", value: 100, hex: "#6A1B9A" }
};

const JAB_COLORS = ["#00FFFF", "#FF00FF", "#FFFF00", "#000000", "#FF0000", "#00FF00", "#0000FF", "#FFFFFF"];

function generateJabCells(tokenHashHex, matrixSize = 16) {
  const hash = crypto.createHash('sha256').update(tokenHashHex).digest();
  const expanded = crypto.createHash('sha512').update(hash).digest();
  const cells = [];
  let idx = 0;
  for (let r = 0; r < matrixSize; r++) {
    for (let c = 0; c < matrixSize; c++) {
      const colorIdx = expanded[idx % expanded.length] % JAB_COLORS.length;
      cells.push({ r, c, color: JAB_COLORS[colorIdx] });
      idx++;
    }
  }
  return cells;
}

function generatePilotBatch() {
  const outDir = path.join(__dirname, "..", "pilot_batch");
  if (!fs.existsSync(outDir)) {
    fs.mkdirSync(outDir, { recursive: true });
  }

  const batchManifest = [];
  const vaultOrigin = "0x71C6619082269E7e8e788e01083416F8C39D5514";
  let serialCounter = 10001;

  console.log("Generating Pilot Batch (20 Scratch Notes for Community Trial)...");

  // วนลูปสร้าง 4 สี สีละ 5 ใบ = รวม 20 ใบ
  Object.keys(COLOR_PALETTES).forEach(denomKey => {
    const spec = COLOR_PALETTES[denomKey];
    for (let i = 1; i <= 5; i++) {
      const serialNo = `PILOT-${denomKey.substring(0, 3)}-${serialCounter++}`;
      const payload = `TVEE|${vaultOrigin}|${spec.value}|${serialNo}|${Date.now()}`;
      const tokenHash = "0x" + crypto.createHash('sha256').update(payload).digest('hex');
      const cells = generateJabCells(tokenHash, 16);

      const cellPx = 11;
      const jabStartX = 60;
      const jabStartY = 95;

      const jabSvgCells = cells.map(cell => 
        `<rect x="${jabStartX + cell.c * cellPx}" y="${jabStartY + cell.r * cellPx}" width="${cellPx}" height="${cellPx}" fill="${cell.color}" />`
      ).join('\n    ');

      // SVG ด้านหน้าแบบพร้อมพิมพ์ (Base Print File - รหัส JAB Code จะอยู่ใต้แถบขูด)
      const frontPrintSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 380" width="800" height="380">
  <!-- ขอบการ์ดตัดตก (Cut Line) -->
  <rect x="5" y="5" width="790" height="370" rx="16" fill="${spec.hex}" stroke="#333333" stroke-width="1" stroke-dasharray="4 2"/>
  <rect x="15" y="15" width="770" height="350" rx="12" fill="${spec.hex}" stroke="#FFFFFF" stroke-width="2"/>

  <!-- จุดพิมพ์ JAB Code ที่ต้องติดสติกเกอร์ฟอยล์ขูดทับขนาด 50x50 mm -->
  <rect x="${jabStartX - 6}" y="${jabStartY - 6}" width="${16 * cellPx + 12}" height="${16 * cellPx + 12}" rx="6" fill="#FFFFFF"/>
  <g>${jabSvgCells}</g>
  
  <!-- กรอบเส้นประระบุพื้นที่ติดสติกเกอร์ฟอยล์สีเงินทับ -->
  <rect x="${jabStartX - 10}" y="${jabStartY - 10}" width="${16 * cellPx + 20}" height="${16 * cellPx + 20}" rx="8" fill="none" stroke="#FFEB3B" stroke-width="2" stroke-dasharray="6 3"/>
  <text x="${jabStartX - 5}" y="${jabStartY + 210}" font-family="Arial, sans-serif" font-weight="bold" font-size="11" fill="#FFEB3B">[ ติดแถบฟอยล์สีเงินทับตรงนี้ 50x50 มม. ]</text>

  <!-- รายละเอียดบัตร -->
  <text x="280" y="80" font-family="Arial, sans-serif" font-weight="900" font-size="28" fill="#FFFFFF">T-VEE COMMUNITY PILOT</text>
  <text x="280" y="110" font-family="Arial, sans-serif" font-weight="bold" font-size="15" fill="#FFF59D">SCRATCH-TO-SYNC • BATCH #001</text>
  
  <rect x="280" y="130" width="480" height="35" rx="6" fill="rgba(0,0,0,0.25)"/>
  <text x="295" y="153" font-family="Arial, sans-serif" font-weight="bold" font-size="14" fill="#FFFFFF">ชนิดราคา: <tspan fill="#80D8FF">${spec.name} (${spec.value} T-VEE)</tspan></text>

  <text x="280" y="200" font-family="Arial, sans-serif" font-size="14" fill="#FFFFFF">Serial Number: <tspan font-family="monospace" font-weight="bold" fill="#FFE082">${serialNo}</tspan></text>
  <text x="280" y="230" font-family="monospace" font-size="12" fill="#E0E0E0">Token Hash:   ${tokenHash.substring(0, 32)}...</text>
  <text x="280" y="255" font-family="monospace" font-size="12" fill="#E0E0E0">Vault Origin: ${vaultOrigin}</text>

  <line x1="280" y1="285" x2="740" y2="285" stroke="#FFFFFF" stroke-width="1" opacity="0.4"/>
  <text x="280" y="315" font-family="Arial, sans-serif" font-weight="bold" font-size="12" fill="#FFF9C4">คำเตือน: หากแถบฟอยล์ยังไม่ถูกขูด สามารถใช้หมุนเวียนซื้อของในตลาดได้เต็มมูลค่า</text>
  <text x="280" y="335" font-family="Arial, sans-serif" font-size="11" fill="#FFFFFF">เมื่อขูดแล้ว ให้สแกนเข้าแอปเพื่อรับเหรียญดิจิทัล (บัตรจะสิ้นสภาพออฟไลน์ทันที)</text>
</svg>`;

      const fileName = `print_${serialNo.toLowerCase()}.svg`;
      fs.writeFileSync(path.join(outDir, fileName), frontPrintSvg, 'utf-8');

      batchManifest.push({
        serialNo: serialNo,
        denomination: spec.name,
        targetValue: spec.value,
        tokenHash: tokenHash,
        file: fileName
      });
    }
  });

  // บันทึก Manifest สรุปชุดพิมพ์
  const manifestPath = path.join(outDir, "pilot_manifest.json");
  fs.writeFileSync(manifestPath, JSON.stringify(batchManifest, null, 2), 'utf-8');
  console.log(`\n🎉 Pilot Batch (20 Notes) successfully generated into: ${outDir}`);
  console.log(`Manifest created: ${manifestPath}`);
}

generatePilotBatch();
