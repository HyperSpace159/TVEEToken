const hre = require("hardhat");

async function main() {
  const [deployer, oracle] = await hre.ethers.getSigners();
  console.log("=================================================");
  console.log("🚀 Deploying T-VEE & T-AAM Protocol Core Contracts");
  console.log("Deployer Address:", deployer.address);
  console.log("Oracle Address:  ", oracle.address);
  console.log("=================================================");

  // 1. Deploy TVEEToken
  const TVEEToken = await hre.ethers.getContractFactory("TVEEToken");
  const tveeToken = await TVEEToken.deploy(oracle.address);
  await tveeToken.waitForDeployment();
  const tokenAddress = await tveeToken.getAddress();
  console.log("✅ TVEEToken deployed to:        ", tokenAddress);

  // 2. Deploy OfflineNoteSync
  const OfflineNoteSync = await hre.ethers.getContractFactory("OfflineNoteSync");
  const offlineSync = await OfflineNoteSync.deploy(tokenAddress);
  await offlineSync.waitForDeployment();
  const syncAddress = await offlineSync.getAddress();
  console.log("✅ OfflineNoteSync deployed to:   ", syncAddress);

  // 3. Link Sync Contract into Token
  await tveeToken.setSyncContract(syncAddress);
  console.log("🔗 TVEEToken linked with Sync Contract.");

  // 4. Deploy TAAMMarketplace
  const TAAMMarketplace = await hre.ethers.getContractFactory("TAAMMarketplace");
  const marketplace = await TAAMMarketplace.deploy(tokenAddress);
  await marketplace.waitForDeployment();
  const marketAddress = await marketplace.getAddress();
  console.log("✅ TAAMMarketplace deployed to:   ", marketAddress);

  console.log("=================================================");
  console.log("🌟 Protocol Deployment Completed Successfully!");
  console.log("=================================================");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
