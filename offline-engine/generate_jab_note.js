const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// นิยามพาเลทสีมาตรฐาน T-VEE
const COLOR_PALETTES = {
  ORANGE: {
    name: "Amber Orange",
    value: 1,
    hex: "#FF6F00",
    bgRgb: "rgb(255, 111, 0)",
    useCase: "Basic produce, chilies, eggs, local transit"
  },
  GREEN: {
    name: "Emerald Green",
    value: 5,
    hex: "#00897B",
    bgRgb: "rgb(0, 137, 123)",
    useCase: "Community meals, street food, daily lunch"
  },
  BLUE: {
    name: "Cobalt Blue",
    value: 20,
    hex: "#1565C0",
    bgRgb: "rgb(21, 101, 192)",
    useCase: "Medicine, bulk grocery, farm tools"
  },
  PURPLE: {
    name: "Imperial Purple",
    value: 100,
    hex: "#6A1B9A",
    bgRgb: "rgb(106, 27, 154)",
    useCase: "Wholesale trade, fertilizer, daily farm wages"
  }
};

// 8 แม่สีสำหรับ JAB Code Color Matrix
const JAB_COLORS = [
  "#00FFFF", // Cyan
  "#FF00FF", // Magenta
  "#FFFF00", // Yellow
  "#000000", // Black
  "#FF0000", // Red
  "#00FF00", // Green
  "#0000FF", // Blue
  "#FFFFFF"  // White
];

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

function renderSvgNote(denomKey, vaultAddress, nonce, outDir) {
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

  // SVG ด้านหน้า
  const frontSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 380" width="800" height="380">
  <defs>
    <filter id="shadow" x="-5%" y="-5%" width="110%" height="110%">
      <feDropShadow dx="0" dy="4" stdDeviation="6" flood-opacity="0.25"/>
    </filter>
  </defs>

  <!-- พื้นหลังธนบัตรสี -->
  <rect x="10" y="10" width="780" height="360" rx="16" fill="${spec.hex}" filter="url(#shadow)" stroke="#FFFFFF" stroke-width="3"/>
  <rect x="22" y="22" width="756" height="336" rx="12" fill="none" stroke="#FFFFFF" stroke-dasharray="8 6" stroke-width="1.5" opacity="0.8"/>

  <!-- JAB Code Matrix Box -->
  <rect x="${jabStartX - 6}" y="${jabStartY - 6}" width="${16 * cellPx + 12}" height="${16 * cellPx + 12}" rx="6" fill="#FFFFFF"/>
  <g>
    ${jabSvgCells}
  </g>

  <!-- Typography & Decentered Information (ไร้ตัวเลขมูลค่าเงิน) -->
  <text x="280" y="90" font-family="Arial, sans-serif" font-weight="900" font-size="28" fill="#FFFFFF" letter-spacing="2">T-VEE PROTOCOL</text>
  <text x="280" y="125" font-family="Arial, sans-serif" font-weight="bold" font-size="15" fill="#FFF59D" letter-spacing="1">NUMBERLESS COLOR-CODED CASH TOKEN</text>
  
  <text x="280" y="170" font-family="Arial, sans-serif" font-size="15" fill="#FFFFFF">Color Grade: <tspan font-weight="bold">${spec.name}</tspan></text>
  <text x="280" y="200" font-family="Arial, sans-serif" font-size="14" fill="#EEEEEE">Universal Unit: <tspan font-weight="bold">${spec.value} T-VEE</tspan> (${spec.useCase})</text>
  
  <text x="280" y="240" font-family="monospace" font-size="12" fill="#E0E0E0">Vault Origin: ${vaultAddress}</text>
  <text x="280" y="265" font-family="monospace" font-size="12" fill="#E0E0E0">Token Hash:   ${tokenHash.substring(0, 34)}...</text>

  <!-- Footer Seal -->
  <line x1="280" y1="290" x2="740" y2="290" stroke="#FFFFFF" stroke-width="1" opacity="0.4"/>
  <text x="280" y="325" font-family="Arial, sans-serif" font-weight="bold" font-size="13" fill="#FFF9C4">IMMUTABLE CODE IS LAW • FIRST-TO-SYNC WINS • 10X SLASHING</text>
</svg>`;

  const frontPath = path.join(outDir, `tvee_note_${denomKey.toLowerCase()}_front.svg`);
  fs.writeFileSync(frontPath, frontSvg, 'utf-8');

  // SVG ด้านหลัง (Transfer Chain)
  const backSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 380" width="800" height="380">
  <rect x="10" y="10" width="780" height="360" rx="16" fill="#F8F9FA" stroke="${spec.hex}" stroke-width="3"/>
  <rect x="22" y="22" width="756" height="336" rx="12" fill="none" stroke="#B0BEC5" stroke-dasharray="6 4" stroke-width="1"/>

  <text x="45" y="60" font-family="Arial, sans-serif" font-weight="bold" font-size="20" fill="#263238">OFFLINE TRANSFER CHAIN (PROOF OF HANDOVER)</text>
  <text x="45" y="85" font-family="Arial, sans-serif" font-size="12" fill="#546E7A">Record physical transactions to claim 10x Slashing Bounty if counterfeit double-spending is detected.</text>

  <!-- Table Headers -->
  <rect x="45" y="110" width="710" height="35" fill="${spec.hex}" rx="4"/>
  <text x="65" y="133" font-family="Arial, sans-serif" font-weight="bold" font-size="13" fill="#FFFFFF">Seq</text>
  <text x="135" y="133" font-family="Arial, sans-serif" font-weight="bold" font-size="13" fill="#FFFFFF">Sender ID / Signature</text>
  <text x="375" y="133" font-family="Arial, sans-serif" font-weight="bold" font-size="13" fill="#FFFFFF">Receiver ID / Signature</text>
  <text x="605" y="133" font-family="Arial, sans-serif" font-weight="bold" font-size="13" fill="#FFFFFF">Date &amp; Location</text>

  <!-- Rows -->
  ${[1, 2, 3, 4].map((r, i) => `
  <rect x="45" y="${145 + i * 40}" width="710" height="40" fill="${i % 2 === 0 ? '#FFFFFF' : '#F1F3F4'}" stroke="#CFD8DC"/>
  <text x="70" y="${170 + i * 40}" font-family="Arial, sans-serif" font-size="13" fill="#455A64">#${r}</text>
  `).join('\n')}

  <text x="45" y="335" font-family="monospace" font-size="11" fill="#78909C">Anchor Hash: ${tokenHash}</text>
</svg>`;

  const backPath = path.join(outDir, `tvee_note_${denomKey.toLowerCase()}_back.svg`);
  fs.writeFileSync(backPath, backSvg, 'utf-8');

  console.log(`Generated [${spec.name}]: ${frontPath}`);
}

const outDir = path.join(__dirname, "..", "sample_notes");
if (!fs.existsSync(outDir)) {
  fs.mkdirSync(outDir, { recursive: true });
}

const mockVault = "0x71C6619082269E7e8e788e01083416F8C39D5514";
Object.keys(COLOR_PALETTES).forEach((key, idx) => {
  renderSvgNote(key, mockVault, 202600 + idx, outDir);
});

console.log(`\n🎉 All 4 Denomination SVG Notes created successfully in: ${outDir}`);
