const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("T-VEE Protocol Core & Anti-Bot Armor Tests", function () {
  let tveeToken, offlineSync;
  let owner, oracle, vault, alice, bob, botHacker;

  beforeEach(async function () {
    [owner, oracle, vault, alice, bob, botHacker] = await ethers.getSigners();

    const TVEETokenFactory = await ethers.getContractFactory("TVEEToken");
    tveeToken = await TVEETokenFactory.deploy(oracle.address);
    await tveeToken.waitForDeployment();

    const OfflineNoteSyncFactory = await ethers.getContractFactory("OfflineNoteSync");
    offlineSync = await OfflineNoteSyncFactory.deploy(await tveeToken.getAddress());
    await offlineSync.waitForDeployment();

    await tveeToken.setSyncContract(await offlineSync.getAddress());

    // Funding
    await tveeToken.transfer(vault.address, ethers.parseEther("50000"));
    await tveeToken.transfer(alice.address, ethers.parseEther("500"));

    // Vault ค้ำประกัน 10,000 TVEE
    await tveeToken.connect(vault).approve(await offlineSync.getAddress(), ethers.parseEther("10000"));
    await offlineSync.connect(vault).depositCollateral(ethers.parseEther("10000"));
  });

  it("🛡️ Anti-Bot Test: ป้องกัน MEV Bot ไม่ให้ขโมยรหัสของชาวบ้านไปเคลมตัดหน้า", async function () {
    const secretSalt = ethers.keccak256(ethers.toUtf8Bytes("SECRET_SCRATCH_SALT_999"));
    // คำนวณ commitment ตรงกับ keccak256(abi.encodePacked(bytes32))
    const commitment = ethers.solidityPackedKeccak256(["bytes32"], [secretSalt]);
    const noteValue = ethers.parseEther("5"); // 5 TVEE

    // Vault ลงทะเบียนบัตรขูด
    await offlineSync.connect(vault).registerPhysicalNote(commitment, noteValue);

    // กรณีที่ 1: บอตพยายามดักขโมย SecretSalt ใน Mempool แล้วส่ง Transaction เคลมเข้ากระเป๋าบอตเอง
    // ระบบต้องบล็อกทันทีถ้าพยายามส่งชื่อคนอื่น
    await expect(
      offlineSync.connect(botHacker).secureSyncWithAntiBot(secretSalt, alice.address)
    ).to.be.revertedWith("Anti-Bot: Claimant must match msg.sender");

    // กรณีที่ 2: ชาวบ้าน Alice ส่งคำสั่งด้วยกระเป๋าตัวเองอย่างถูกต้อง -> สำเร็จและได้เงิน
    await offlineSync.connect(alice).secureSyncWithAntiBot(secretSalt, alice.address);
    const aliceBal = await tveeToken.balanceOf(alice.address);
    expect(aliceBal).to.equal(ethers.parseEther("505")); // 500 + 5
  });

  it("🚨 Slashing Test: ตรวจจับ Double-Spending และริบทรัพย์คลังต้นทาง 10 เท่า", async function () {
    const secretSalt = ethers.keccak256(ethers.toUtf8Bytes("DUPLICATE_NOTE_SALT_888"));
    const commitment = ethers.solidityPackedKeccak256(["bytes32"], [secretSalt]);
    const noteValue = ethers.parseEther("10"); // 10 TVEE

    await offlineSync.connect(vault).registerPhysicalNote(commitment, noteValue);

    // Alice สแกนใบจริงเป็นคนแรก
    await offlineSync.connect(alice).secureSyncWithAntiBot(secretSalt, alice.address);

    // Bob โดนหลอกถือใบก๊อปปี้มาสแกนซ้ำ -> ระบบริบเงิน Vault 10 เท่า (100 TVEE) จ่ายชดเชยให้ Bob
    const bobInitialBal = await tveeToken.balanceOf(bob.address);
    await offlineSync.connect(bob).secureSyncWithAntiBot(secretSalt, bob.address);

    const bobBalAfter = await tveeToken.balanceOf(bob.address);
    expect(bobBalAfter - bobInitialBal).to.equal(ethers.parseEther("100")); // 10 x 10 = 100 TVEE
  });
});
