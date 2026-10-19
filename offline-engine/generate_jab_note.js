const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const COLOR_PALETTES = {
  ORANGE: { name: "Amber Orange", value: 1, hex: "#FF6F00", useCase: "Produce, local transit, eggs" },
  GREEN: { name: "Emerald Green", value: 5, hex: "#00897B", useCase: "Community meals, street food" },
  BLUE: { name: "Cobalt Blue", value: 20, hex: "#1565C0", useCase: "Medicine, bulk grocery, tools" },
  PURPLE: { name: "Imperial Purple", value: 100, hex: "#6A1B9A", useCase: "Wholesale trade, farm wages" }
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

function renderScratchCard(denomKey, vaultAddress, nonce, outDir) {
  const spec = COLOR_PALETTES[denomKey];
  const payload = `TVEE|${vaultAddress}|${spec.value}|${nonce}|${Date.now()}`;
  const tokenHash = "0x" + crypto.createHash('sha256').update(payload).digest('hex');
  const cells = generateJabCells(tokenHash, 16);

  const cellPx = 11;
  const jabStartX = 60;
  const jabStartY = 95;

  let jabSvgCells = cells.map(cell => 
    `<rect x="${jabStartX + cell.c * cellPx}" y="${jabStartY + cell.r * cellPx}" width="${cellPx}" height="${cellPx}" fill="${cell.color}" />`
  ).join('\n    ');

  // 1. ธนบัตรแบบก่อนขูด (Intact Foil - มีมูลค่าใช้หมุนเวียนออฟไลน์)
  const intactSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 380" width="800" height="380">
  <defs>
    <filter id="shadow" x="-5%" y="-5%" width="110%" height="110%">
      <feDropShadow dx="0" dy="4" stdDeviation="6" flood-opacity="0.25"/>
    </filter>
    <linearGradient id="silverFoil" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#E0E0E0"/>
      <stop offset="25%" stop-color="#F5F5F5"/>
      <stop offset="50%" stop-color="#BDBDBD"/>
      <stop offset="75%" stop-color="#EEEEEE"/>
      <stop offset="100%" stop-color="#9E9E9E"/>
    </linearGradient>
  </defs>

  <rect x="10" y="10" width="780" height="360" rx="16" fill="${spec.hex}" filter="url(#shadow)" stroke="#FFFFFF" stroke-width="3"/>
  <rect x="22" y="22" width="756" height="336" rx="12" fill="none" stroke="#FFFFFF" stroke-dasharray="8 6" stroke-width="1.5" opacity="0.8"/>

  <!-- แถบฟอยล์สีเงินปิดทับรหัส (SCRATCH-OFF FOIL LAYER) -->
  <rect x="${jabStartX - 6}" y="${jabStartY - 6}" width="${16 * cellPx + 12}" height="${16 * cellPx + 12}" rx="8" fill="url(#silverFoil)" stroke="#757575" stroke-width="2"/>
  
  <text x="${jabStartX + 20}" y="${jabStartY + 80}" font-family="Arial, sans-serif" font-weight="900" font-size="16" fill="#424242">SCRATCH HERE</text>
  <text x="${jabStartX + 15}" y="${jabStartY + 105}" font-family="Arial, sans-serif" font-weight="bold" font-size="11" fill="#616161">🔒 TO SYNC ON-CHAIN</text>
  <text x="${jabStartX + 22}" y="${jabStartY + 130}" font-family="Arial, sans-serif" font-size="10" fill="#757575">(DO NOT SCRATCH</text>
  <text x="${jabStartX + 20}" y="${jabStartY + 145}" font-family="Arial, sans-serif" font-size="10" fill="#757575">FOR CASH CIRCULATION)</text>

  <text x="280" y="85" font-family="Arial, sans-serif" font-weight="900" font-size="28" fill="#FFFFFF">T-VEE SCRATCH NOTE</text>
  <text x="280" y="115" font-family="Arial, sans-serif" font-weight="bold" font-size="14" fill="#FFF59D">VISUAL PROOF OF UNSPENT • OFFLINE CIRCULATION</text>
  
  <rect x="280" y="135" width="480" height="40" rx="6" fill="rgba(0,0,0,0.2)"/>
  <text x="295" y="160" font-family="Arial, sans-serif" font-weight="bold" font-size="14" fill="#FFFFFF">สถานะออฟไลน์: <tspan fill="#A7FFEB">พร้อมหมุนเวียน 100% (แถบฟอยล์ยังสมบูรณ์)</tspan></text>
  
  <text x="280" y="210" font-family="Arial, sans-serif" font-size="15" fill="#FFFFFF">Color Grade: <tspan font-weight="bold">${spec.name}</tspan> (${spec.useCase})</text>
  <text x="280" y="240" font-family="Arial, sans-serif" font-size="14" fill="#EEEEEE">Denomination: <tspan font-weight="bold">${spec.value} T-VEE</tspan></text>
  <text x="280" y="270" font-family="monospace" font-size="12" fill="#E0E0E0">Vault ID: ${vaultAddress}</text>

  <line x1="280" y1="295" x2="740" y2="295" stroke="#FFFFFF" stroke-width="1" opacity="0.4"/>
  <text x="280" y="325" font-family="Arial, sans-serif" font-weight="bold" font-size="12" fill="#FFF9C4">ตราบใดที่ฟอยล์ยังไม่ถูกขูด = มั่นใจได้ว่าไม่มีใครแอบสแกนซิงค์ไปก่อน</text>
</svg>`;

  fs.writeFileSync(path.join(outDir, `scratch_note_${denomKey.toLowerCase()}_intact.svg`), intactSvg, 'utf-8');

  // 2. ธนบัตรแบบหลังขูดแล้ว (Scratched - ซิงค์เข้าเชนแล้ว)
  const scratchedSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 380" width="800" height="380">
  <defs>
    <filter id="shadow2" x="-5%" y="-5%" width="110%" height="110%">
      <feDropShadow dx="0" dy="4" stdDeviation="6" flood-opacity="0.25"/>
    </filter>
  </defs>

  <rect x="10" y="10" width="780" height="360" rx="16" fill="${spec.hex}" filter="url(#shadow2)" stroke="#FFFFFF" stroke-width="3"/>
  <rect x="22" y="22" width="756" height="336" rx="12" fill="none" stroke="#FFFFFF" stroke-dasharray="8 6" stroke-width="1.5" opacity="0.8"/>

  <!-- เปิดเผย JAB Code หลังขูดฟอยล์ออก -->
  <rect x="${jabStartX - 6}" y="${jabStartY - 6}" width="${16 * cellPx + 12}" height="${16 * cellPx + 12}" rx="6" fill="#FFFFFF"/>
  <g>
    ${jabSvgCells}
  </g>

  <text x="280" y="85" font-family="Arial, sans-serif" font-weight="900" font-size="28" fill="#FFFFFF">T-VEE SCRATCH NOTE (REDEEMED)</text>
  <text x="280" y="115" font-family="Arial, sans-serif" font-weight="bold" font-size="14" fill="#FF8A80">STATUS: SCRATCHED &amp; SYNCED TO BLOCKCHAIN</text>
  
  <rect x="280" y="135" width="480" height="40" rx="6" fill="rgba(255,0,0,0.3)"/>
  <text x="295" y="160" font-family="Arial, sans-serif" font-weight="bold" font-size="14" fill="#FFCDD2">สิ้นสภาพออฟไลน์: <tspan fill="#FFFFFF">สแกนเข้าสู่กระเป๋าดิจิทัลแล้ว (ห้ามรับต่อ)</tspan></text>

  <text x="280" y="210" font-family="Arial, sans-serif" font-size="15" fill="#FFFFFF">Token Hash: <tspan font-family="monospace" font-size="12">${tokenHash.substring(0, 30)}...</tspan></text>
  <text x="280" y="240" font-family="Arial, sans-serif" font-size="14" fill="#EEEEEE">Redeemed Value: <tspan font-weight="bold">${spec.value} T-VEE</tspan></text>

  <line x1="280" y1="295" x2="740" y2="295" stroke="#FFFFFF" stroke-width="1" opacity="0.4"/>
  <text x="280" y="325" font-family="Arial, sans-serif" font-weight="bold" font-size="12" fill="#FFE082">Code is Law • First-To-Sync Wins • Slashing Active</text>
</svg>`;

  fs.writeFileSync(path.join(outDir, `scratch_note_${denomKey.toLowerCase()}_scratched.svg`), scratchedSvg, 'utf-8');
  console.log(`Rendered Scratch Note [${spec.name}]: Intact & Scratched SVGs.`);
}

const outDir = path.join(__dirname, "..", "sample_notes");
const mockVault = "0x71C6619082269E7e8e788e01083416F8C39D5514";
Object.keys(COLOR_PALETTES).forEach((key, idx) => {
  renderScratchCard(key, mockVault, 99000 + idx, outDir);
});
console.log("All Scratch Cards generated successfully!");
