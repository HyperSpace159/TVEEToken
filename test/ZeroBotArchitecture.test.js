const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Zero-Bot Architecture & 3-in-5 Treasury Tests", function () {
  let gatekeeper, vault3of5;
  let owner, retailAlice, whaleBob, signer1, signer2, signer3, signer4, signer5;

  beforeEach(async function () {
    [owner, retailAlice, whaleBob, signer1, signer2, signer3, signer4, signer5] = await ethers.getSigners();

    // 1. Deploy TieredRebaseGatekeeper
    const GatekeeperFactory = await ethers.getContractFactory("TieredRebaseGatekeeper");
    gatekeeper = await GatekeeperFactory.deploy();
    await gatekeeper.waitForDeployment();

    // ยืนยันตัวตนให้ Alice เป็นมนุษย์จริง (Proof of Humanity)
    await gatekeeper.verifyHuman(retailAlice.address);

    // 2. Deploy InstitutionalVault3of5
    const VaultFactory = await ethers.getContractFactory("InstitutionalVault3of5");
    const signersArray = [signer1.address, signer2.address, signer3.address, signer4.address, signer5.address];
    vault3of5 = await VaultFactory.deploy(signersArray);
    await vault3of5.waitForDeployment();

    // ส่ง ETH จำลองเข้าคลังหลวง 10 ETH
    await owner.sendTransaction({
      to: await vault3of5.getAddress(),
      value: ethers.parseEther("10.0")
    });
  });

  it("🧮 1. Live Dynamic Rebase Test: ค่า globalK และการอุ้มชูรายย่อยตามตาราง Stress Test", async function () {
    const rawAlice = ethers.parseEther("50000");   // 50,000 Coins (คนเงินน้อย)
    const rawWhale = ethers.parseEther("1000000"); // 1,000,000 Coins (ปลาวาฬ)

    // กรณี A: Supply = 8M Coins (ปกติ) -> globalK = 1.0
    await gatekeeper.updateMarketSupply(ethers.parseEther("8000000"));
    let aliceBal = await gatekeeper.getEffectiveBalance(retailAlice.address, rawAlice);
    let whaleBal = await gatekeeper.getEffectiveBalance(whaleBob.address, rawWhale);
    expect(aliceBal).to.equal(rawAlice);
    expect(whaleBal).to.equal(rawWhale);

    // กรณี B: Supply = 15M Coins (ล้น 50%) -> globalK = 0.9875 (ฝ่อลง 1.25%)
    await gatekeeper.updateMarketSupply(ethers.parseEther("15000000"));
    aliceBal = await gatekeeper.getEffectiveBalance(retailAlice.address, rawAlice);
    whaleBal = await gatekeeper.getEffectiveBalance(whaleBob.address, rawWhale);
    
    // คนเงินน้อยต้องได้เต็ม 50,000 เสมอ (ระบบอุ้ม 100%)
    expect(aliceBal).to.equal(rawAlice);
    // ปลาวาฬโดนปรับลดเหลือ 987,500 Coins
    expect(whaleBal).to.equal(ethers.parseEther("987500"));

    // กรณี C: Supply = 20M Coins (วิกฤตสูงสุด) -> globalK = 0.9500 (ฝ่อลง 5%)
    await gatekeeper.updateMarketSupply(ethers.parseEther("20000000"));
    aliceBal = await gatekeeper.getEffectiveBalance(retailAlice.address, rawAlice);
    whaleBal = await gatekeeper.getEffectiveBalance(whaleBob.address, rawWhale);
    
    expect(aliceBal).to.equal(rawAlice); // รายย่อยยังคงได้ 50,000 เต็ม!
    expect(whaleBal).to.equal(ethers.parseEther("950000")); // ปลาวาฬหายไป 50,000 Coins
  });

  it("🥷 2. Gatekeeper Armor Test: สกัดกั้น Flash-Mob Swarm ด้วย Velocity Limit", async function () {
    // โอน 30,000 Coins (ผ่าน)
    await gatekeeper.checkVelocityLimit(retailAlice.address, ethers.parseEther("30000"));

    // พยายามโอนอีก 25,000 Coins (เกินเพดาน 50,000 Coins ต่อวัน) -> ต้องโดนบล็อกทันที
    await expect(
      gatekeeper.checkVelocityLimit(retailAlice.address, ethers.parseEther("25000"))
    ).to.be.revertedWith("Gatekeeper: Daily velocity limit breached (Flash-Mob Protection)");
  });

  it("🏛️ 3. 3-in-5 Multi-Sig Test: ต้องได้ 3 ใน 5 เสียงจึงจะถอนเงินค้ำประกันได้", async function () {
    const dest = retailAlice.address;
    const withdrawAmount = ethers.parseEther("2.0");

    // Signer 1 สร้างข้อเสนอ (ได้ 1 เสียง)
    const tx = await vault3of5.connect(signer1).createProposal(dest, withdrawAmount, "Liquidity Support");
    await tx.wait();

    let proposal = await vault3of5.proposals(1);
    expect(proposal.approvalCount).to.equal(1n);
    expect(proposal.isExecuted).to.be.false;

    // Signer 2 ลงนาม (ได้ 2 เสียง - ยังไม่พอ)
    await vault3of5.connect(signer2).approveProposal(1);
    proposal = await vault3of5.proposals(1);
    expect(proposal.approvalCount).to.equal(2n);
    expect(proposal.isExecuted).to.be.false;

    // Signer 3 ลงนาม (ครบ 3 เสียง! -> อนุมัติและโอนเงินทันที)
    const initialAliceBal = await ethers.provider.getBalance(dest);
    await vault3of5.connect(signer3).approveProposal(1);

    proposal = await vault3of5.proposals(1);
    expect(proposal.approvalCount).to.equal(3n);
    expect(proposal.isExecuted).to.be.true;

    const finalAliceBal = await ethers.provider.getBalance(dest);
    expect(finalAliceBal - initialAliceBal).to.equal(withdrawAmount);
  });
});
