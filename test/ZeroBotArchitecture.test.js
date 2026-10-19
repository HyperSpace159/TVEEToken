const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Zero-Bot Architecture & Web-of-Trust Gatekeeper Tests", function () {
  let gatekeeper, vault3of5;
  let genesisOwner, retailAlice, whaleBob, strangerEve, signer1, signer2, signer3, signer4, signer5;

  beforeEach(async function () {
    [genesisOwner, retailAlice, whaleBob, strangerEve, signer1, signer2, signer3, signer4, signer5] = await ethers.getSigners();

    // 1. Deploy TieredRebaseGatekeeper
    const GatekeeperFactory = await ethers.getContractFactory("TieredRebaseGatekeeper");
    gatekeeper = await GatekeeperFactory.deploy();
    await gatekeeper.waitForDeployment();

    // 2. Deploy InstitutionalVault3of5
    const VaultFactory = await ethers.getContractFactory("InstitutionalVault3of5");
    const signersArray = [signer1.address, signer2.address, signer3.address, signer4.address, signer5.address];
    vault3of5 = await VaultFactory.deploy(signersArray);
    await vault3of5.waitForDeployment();
  });

  it("🥷 1. Web-of-Trust Test: สมัครสมาชิกด้วยม่านตา (Proof of Humanity) + Code ผู้แนะนำ", async function () {
    const irisAlice = ethers.keccak256(ethers.toUtf8Bytes("ALICE_IRIS_SCAN_001"));

    // กรณี A: Stranger Eve พยายามใช้กระเป๋าตัวเองเป็นผู้แนะนำทั้งที่ยังไม่ได้รับการรับรอง -> ติด Gatekeeper บล็อกทันที
    await expect(
      gatekeeper.connect(strangerEve).registerMemberWithReferral(irisAlice, strangerEve.address)
    ).to.be.revertedWith("Gatekeeper: Invalid referrer code. Referrer must be a verified human");

    // กรณี B: Alice มี Genesis Owner เป็นผู้แนะนำที่ถูกต้อง -> สมัครผ่านฉลุย
    await gatekeeper.connect(retailAlice).registerMemberWithReferral(irisAlice, genesisOwner.address);
    expect(await gatekeeper.isHumanVerified(retailAlice.address)).to.be.true;
    expect(await gatekeeper.referredBy(retailAlice.address)).to.equal(genesisOwner.address);

    // กรณี C: ปลาวาฬพยายามนำรหัสม่านตาของ Alice มาแอบสมัครกระเป๋าที่ 2 -> ระบบดีดทิ้งทันที
    await expect(
      gatekeeper.connect(whaleBob).registerMemberWithReferral(irisAlice, genesisOwner.address)
    ).to.be.revertedWith("Gatekeeper: This human iris/identity is ALREADY REGISTERED (1 Human = 1 Account)");
  });

  it("🧮 2. Rebase Stress Test: เฉพาะมนุษย์จริงที่ผ่านการรับรองเท่านั้นที่ได้รับการคุ้มครอง", async function () {
    const irisAlice = ethers.keccak256(ethers.toUtf8Bytes("ALICE_IRIS_SCAN_001"));
    await gatekeeper.connect(retailAlice).registerMemberWithReferral(irisAlice, genesisOwner.address);

    const rawAlice = ethers.parseEther("50000");   // 50,000 Coins (คนเงินน้อย ยืนยันตัวตนแล้ว)
    const rawWhale = ethers.parseEther("1000000"); // 1,000,000 Coins (ปลาวาฬ)
    const rawUnverified = ethers.parseEther("50000"); // 50,000 Coins แต่ไม่ยืนยันตัวตน

    // เงินล้นวิกฤต 20M Coins -> globalK = 0.9500
    await gatekeeper.updateMarketSupply(ethers.parseEther("20000000"));

    const aliceBal = await gatekeeper.getEffectiveBalance(retailAlice.address, rawAlice);
    const whaleBal = await gatekeeper.getEffectiveBalance(whaleBob.address, rawWhale);
    const unverifiedBal = await gatekeeper.getEffectiveBalance(strangerEve.address, rawUnverified);

    // Alice มนุษย์จริงที่มีคนแนะนำ: ได้เต็ม 50,000 Coins 100%
    expect(aliceBal).to.equal(rawAlice);
    // ปลาวาฬ: หายไป 50,000 Coins (เหลือ 950,000)
    expect(whaleBal).to.equal(ethers.parseEther("950000"));
    // คนเงินน้อยแต่ไม่ยืนยันตัวตน: ไม่ได้สิทธิ์อุ้มชู โดนลดขนาดเหลือ 47,500 Coins
    expect(unverifiedBal).to.equal(ethers.parseEther("47500"));
  });

  it("⛓️ 3. Social Slashing Test: ริบสิทธิ์ผู้แนะนำหากพบบัญชีนอมินีโกงระบบ", async function () {
    const irisAlice = ethers.keccak256(ethers.toUtf8Bytes("ALICE_IRIS_001"));
    await gatekeeper.connect(retailAlice).registerMemberWithReferral(irisAlice, genesisOwner.address);

    // เมื่อพบว่า Alice ทำผิดกฎ -> รัฐบาลสั่ง Slash
    await gatekeeper.slashRogueAccount(retailAlice.address);
    expect(await gatekeeper.isHumanVerified(retailAlice.address)).to.be.false;
    // ผู้แนะนำ (Genesis Owner) โดนริบสิทธิ์อุ้มชูด้วย
    expect(await gatekeeper.isHumanVerified(genesisOwner.address)).to.be.false;
  });
});
