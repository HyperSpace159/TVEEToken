const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const network = hre.network.name;

  console.log("========================================================");
  console.log(`🌐 DEPLOYING T-VEE & THE TIME-VALUE ECOSYSTEM TO L2 [${network.toUpperCase()}]`);
  console.log("Deployer Address:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Account Balance: ", hre.ethers.formatEther(balance), "ETH");
  console.log("========================================================");

  // 1. Deploy TVEEToken (Coin X)
  console.log("\n[1/4] Deploying TVEEToken (Platform Utility & Rebase Currency)...");
  const TVEEToken = await hre.ethers.getContractFactory("TVEEToken");
  const tveeToken = await TVEEToken.deploy(deployer.address);
  await tveeToken.waitForDeployment();
  const tokenAddress = await tveeToken.getAddress();
  console.log("✅ TVEEToken deployed at:        ", tokenAddress);

  // 2. Deploy OfflineNoteSync (JAB Code & Slashing)
  console.log("\n[2/4] Deploying OfflineNoteSync (JAB Code & 10x Slashing)...");
  const OfflineNoteSync = await hre.ethers.getContractFactory("OfflineNoteSync");
  const offlineSync = await OfflineNoteSync.deploy(tokenAddress);
  await offlineSync.waitForDeployment();
  const syncAddress = await offlineSync.getAddress();
  console.log("✅ OfflineNoteSync deployed at:   ", syncAddress);

  // Link Sync Contract to Token
  await tveeToken.setSyncContract(syncAddress);
  console.log("🔗 TVEEToken successfully linked to OfflineNoteSync.");

  // 3. Deploy TAAMMarketplace (Invoice Factoring Exchange)
  console.log("\n[3/4] Deploying TAAMMarketplace (Credit Term Invoice Factoring)...");
  const TAAMMarketplace = await hre.ethers.getContractFactory("TAAMMarketplace");
  const marketplace = await TAAMMarketplace.deploy(tokenAddress);
  await marketplace.waitForDeployment();
  const marketAddress = await marketplace.getAddress();
  console.log("✅ TAAMMarketplace deployed at:   ", marketAddress);

  // 4. Deploy TimeValueVault (4 Pillars: Dynamic Unbonding, Yield Boost, Demurrage, Time Exchange)
  console.log("\n[4/4] Deploying TimeValueVault (The 4 Pillars Circuit Breaker)...");
  const TimeValueVault = await hre.ethers.getContractFactory("TimeValueVault");
  // ให้ ETH เป็น Collateral ตัวอย่าง (address 0)
  const timeVault = await TimeValueVault.deploy(tokenAddress, hre.ethers.ZeroAddress);
  await timeVault.waitForDeployment();
  const vaultAddress = await timeVault.getAddress();
  console.log("✅ TimeValueVault deployed at:    ", vaultAddress);

  console.log("\n========================================================");
  console.log("🎉 ALL 4 CORE CONTRACTS DEPLOYED SUCCESSFULLY ON L2!");
  console.log("========================================================");
  console.log(JSON.stringify({
    network: network,
    TVEEToken: tokenAddress,
    OfflineNoteSync: syncAddress,
    TAAMMarketplace: marketAddress,
    TimeValueVault: vaultAddress
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
