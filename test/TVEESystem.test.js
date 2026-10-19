const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("T-VEE & T-AAM Protocol Core Tests", function () {
  let tveeToken, offlineSync, marketplace;
  let owner, oracle, vault, alice, bob;

  beforeEach(async function () {
    [owner, oracle, vault, alice, bob] = await ethers.getSigners();

    // 1. Deploy TVEEToken
    const TVEETokenFactory = await ethers.getContractFactory("TVEEToken");
    tveeToken = await TVEETokenFactory.deploy(oracle.address);
    await tveeToken.waitForDeployment();

    // 2. Deploy OfflineNoteSync
    const OfflineNoteSyncFactory = await ethers.getContractFactory("OfflineNoteSync");
    offlineSync = await OfflineNoteSyncFactory.deploy(await tveeToken.getAddress());
    await offlineSync.waitForDeployment();

    // 3. Link Sync Contract
    await tveeToken.setSyncContract(await offlineSync.getAddress());

    // 4. Deploy TAAMMarketplace
    const TAAMMarketplaceFactory = await ethers.getContractFactory("TAAMMarketplace");
    marketplace = await TAAMMarketplaceFactory.deploy(await tveeToken.getAddress());
    await marketplace.waitForDeployment();

    // Transfer some funds to vault & alice
    await tveeToken.transfer(vault.address, ethers.parseEther("50000")); // Capitalist Vault
    await tveeToken.transfer(alice.address, ethers.parseEther("500"));   // Retail Alice
  });

  it("Should protect retail users from Demurrage Tax (Retail Threshold)", async function () {
    // Alice มี 500 TVEE ซึ่งต่ำกว่าเกณฑ์คุ้มครอง 1,000 TVEE
    const lambdaAlice = await tveeToken.calculateLambda(alice.address);
    expect(lambdaAlice).to.equal(0n);

    // Vault มี 50,000 TVEE ซึ่งสูงกว่าเกณฑ์
    const lambdaVault = await tveeToken.calculateLambda(vault.address);
    expect(lambdaVault).to.be.gt(0n);
  });

  it("Should allow First-To-Sync and trigger 10x Slashing on double spending fraud", async function () {
    const tokenHash = ethers.keccak256(ethers.toUtf8Bytes("GREEN_NOTE_SERIES_001"));
    const noteValue = ethers.parseEther("5"); // 5 TVEE (Green Note)

    // 1. Vault ฝากหลักประกัน 1,000 TVEE
    await tveeToken.connect(vault).approve(await offlineSync.getAddress(), ethers.parseEther("1000"));
    await offlineSync.connect(vault).depositCollateral(ethers.parseEther("1000"));

    // 2. Vault ลงทะเบียนพิมพ์ธนบัตรสี
    await offlineSync.connect(vault).registerPhysicalNote(tokenHash, noteValue);

    // 3. Alice สแกนเป็นคนแรก (First-To-Sync Wins)
    await offlineSync.connect(alice).firstSyncWinsAndSlash(tokenHash, alice.address);
    const aliceBalAfterSync = await tveeToken.balanceOf(alice.address);
    expect(aliceBalAfterSync).to.equal(ethers.parseEther("505")); // 500 + 5

    // 4. Bob นำใบก๊อปปี้มาสแกนซ้ำ -> ระบบตรวจพบ Double Spend และริบทรัพย์ Vault 10 เท่าให้ Bob ทันที
    const bobInitialBal = await tveeToken.balanceOf(bob.address);
    await offlineSync.connect(bob).firstSyncWinsAndSlash(tokenHash, bob.address);

    const bobBalAfterSlash = await tveeToken.balanceOf(bob.address);
    const expectedBounty = noteValue * 10n; // 50 TVEE
    expect(bobBalAfterSlash - bobInitialBal).to.equal(expectedBounty);
  });
});
