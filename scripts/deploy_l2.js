const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const network = hre.network.name;

  console.log("========================================================");
  console.log(`🌐 DEPLOYING COMPLETE T-VEE PROTOCOL TO L2 [${network.toUpperCase()}]`);
  console.log("Deployer Address:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Account Balance: ", hre.ethers.formatEther(balance), "ETH");
  console.log("========================================================");

  if (balance === 0n) {
    console.warn("⚠️ Warning: Deployer balance is 0 ETH. Please get testnet ETH from a faucet before deploying.");
    return;
  }

  // 1. Deploy TVEEToken
  console.log("\n[1/5] Deploying TVEEToken (Core Rebase Token)...");
  const TVEEToken = await hre.ethers.getContractFactory("TVEEToken");
  const tveeToken = await TVEEToken.deploy(deployer.address);
  await tveeToken.waitForDeployment();
  const tokenAddress = await tveeToken.getAddress();
  console.log("✅ TVEEToken deployed at:             ", tokenAddress);

  // 2. Deploy TieredRebaseGatekeeper
  console.log("\n[2/5] Deploying TieredRebaseGatekeeper (O(1) Rebase & Web-of-Trust)...");
  const Gatekeeper = await hre.ethers.getContractFactory("TieredRebaseGatekeeper");
  const gatekeeper = await Gatekeeper.deploy();
  await gatekeeper.waitForDeployment();
  const gatekeeperAddress = await gatekeeper.getAddress();
  console.log("✅ TieredRebaseGatekeeper deployed at: ", gatekeeperAddress);

  // 3. Deploy OfflineNoteSync
  console.log("\n[3/5] Deploying OfflineNoteSync (Scratch-To-Sync & 10x Slashing)...");
  const OfflineNoteSync = await hre.ethers.getContractFactory("OfflineNoteSync");
  const offlineSync = await OfflineNoteSync.deploy(tokenAddress);
  await offlineSync.waitForDeployment();
  const syncAddress = await offlineSync.getAddress();
  console.log("✅ OfflineNoteSync deployed at:        ", syncAddress);

  await tveeToken.setSyncContract(syncAddress);
  console.log("🔗 TVEEToken linked with OfflineNoteSync.");

  // 4. Deploy TimeValueVault (Integrated with Chainlink Feed)
  console.log("\n[4/5] Deploying TimeValueVault (Chainlink Oracles & Dynamic Unbonding)...");
  
  // Chainlink ETH/USD Data Feed บน Arbitrum Sepolia
  let chainlinkPriceFeed = hre.ethers.ZeroAddress;
  if (network === "arbitrumSepolia") {
    chainlinkPriceFeed = "0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165"; // Real Chainlink Feed Address
    console.log("🔗 Connecting to Live Chainlink Price Feed on Arbitrum Sepolia:", chainlinkPriceFeed);
  }

  const TimeValueVault = await hre.ethers.getContractFactory("TimeValueVault");
  const timeVault = await TimeValueVault.deploy(tokenAddress, hre.ethers.ZeroAddress, chainlinkPriceFeed);
  await timeVault.waitForDeployment();
  const vaultAddress = await timeVault.getAddress();
  console.log("✅ TimeValueVault deployed at:         ", vaultAddress);

  // 5. Deploy InstitutionalVault3of5
  console.log("\n[5/5] Deploying InstitutionalVault3of5 (3-in-5 Multi-Sig Treasury)...");
  const Vault3of5 = await hre.ethers.getContractFactory("InstitutionalVault3of5");
  const signers = [
    deployer.address,
    "0x71C6619082269E7e8e788e01083416F8C39D5514",
    "0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF",
    "0x6813Eb9362372EEF6200f3b1dbC3f819671cBA69",
    "0x1efF47bc3a10a45D4B230B5d10E37751FE6AA718"
  ];
  const instVault = await Vault3of5.deploy(signers);
  await instVault.waitForDeployment();
  const instVaultAddress = await instVault.getAddress();
  console.log("✅ InstitutionalVault3of5 deployed at: ", instVaultAddress);

  console.log("\n========================================================");
  console.log("🎉 ALL 5 CONTRACTS SUCCESSFULLY DEPLOYED TO L2!");
  console.log("========================================================");
  console.log(JSON.stringify({
    network: network,
    ChainlinkFeed: chainlinkPriceFeed,
    TVEEToken: tokenAddress,
    TieredRebaseGatekeeper: gatekeeperAddress,
    OfflineNoteSync: syncAddress,
    TimeValueVault: vaultAddress,
    InstitutionalVault3of5: instVaultAddress
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
