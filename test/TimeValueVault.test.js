const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Time-Value Ecosystem (The 4 Pillars Test)", function () {
  let timeVault, coinX;
  let owner, userAlice, hunterBob;

  beforeEach(async function () {
    [owner, userAlice, hunterBob] = await ethers.getSigners();

    // 1. Deploy Token Coin X
    const TVEEToken = await ethers.getContractFactory("TVEEToken");
    coinX = await TVEEToken.deploy(owner.address);
    await coinX.waitForDeployment();

    // 2. Deploy TimeValueVault
    const TimeValueVault = await ethers.getContractFactory("TimeValueVault");
    timeVault = await TimeValueVault.deploy(await coinX.getAddress(), ethers.ZeroAddress);
    await timeVault.waitForDeployment();
  });

  it("เสาหลักที่ 1: Dynamic Unbonding - ยืดเวลาหน่วงถอนอัตโนมัติเมื่อราคา Coin X ร่วง", async function () {
    const basePrice = ethers.parseEther("1.0");

    // ภาวะปกติ (ราคา 1.0 USD) -> เวลาหน่วง = 7 วัน (604,800 วินาที)
    const normalPeriod = await timeVault.calculateUnbondingPeriod(basePrice);
    expect(normalPeriod).to.equal(7n * 86400n);

    // ราคาร่วง 50% (เหลือ 0.5 USD) -> เวลาหน่วงยืดขึ้นเป็น ~36 วัน (> 30 วัน)
    const drop50Price = ethers.parseEther("0.5");
    const panicPeriod = await timeVault.calculateUnbondingPeriod(drop50Price);
    expect(panicPeriod).to.be.gt(30n * 86400n);

    // ราคาร่วง 90% (เหลือ 0.1 USD) -> เวลาหน่วงยืดขึ้นเป็น ~77 วัน (> 75 วัน)
    const crashPrice = ethers.parseEther("0.1");
    const severeCrashPeriod = await timeVault.calculateUnbondingPeriod(crashPrice);
    expect(severeCrashPeriod).to.be.gt(75n * 86400n);

    // ราคาดิ่งถึงศูนย์ (0 USD) -> ชนเพดานแช่แข็งสมบูรณ์ที่ 90 วัน
    const zeroPrice = 0n;
    const maxFreezePeriod = await timeVault.calculateUnbondingPeriod(zeroPrice);
    expect(maxFreezePeriod).to.equal(90n * 86400n);
  });

  it("เสาหลักที่ 3: Negative Interest Demurrage Tax - คำนวณอัตราเผาเหรียญยามเงินล้นตลาด", async function () {
    // ปริมาณ Supply ปลอดภัย (10M เหรียญ) -> ภาษีติดลบ = 0%
    const safeSupply = ethers.parseEther("10000000");
    const taxZero = await timeVault.calculateDailyDemurrageTax(safeSupply);
    expect(taxZero).to.equal(0n);

    // ปริมาณ Supply ล้นถึงจุดวิกฤต (20M เหรียญ) -> ภาษีติดลบแตะเพดาน 5% ต่อวัน
    const crisisSupply = ethers.parseEther("20000000");
    const maxTax = await timeVault.calculateDailyDemurrageTax(crisisSupply);
    expect(maxTax).to.equal(ethers.parseEther("0.05")); // 5% ต่อวัน
  });
});
