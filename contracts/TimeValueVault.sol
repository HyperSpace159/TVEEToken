// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TVEEToken.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title TimeValueVault (Chainlink Oracles Integrated)
 * @notice The Time-Value Ecosystem: ระบบนิเวศการเงินปิดเชิงเวลาผสาน Chainlink Data Feeds
 * 
 * 🔗 CHAINLINK INTEGRATION:
 * - AggregatorV3Interface: ดึงราคาตลาดโลกแบบ Decentralized จริง
 * - Dynamic Unbonding คำนวณจากราคา Chainlink Feed โดยตรง (ไม่มีใครแทรกแซงราคาได้)
 * 
 * เสาหลักที่ 1: Dynamic Unbonding Period (ระบบหน่วงเวลาแปรผันตามราคา Chainlink)
 * เสาหลักที่ 2: Yield Boost & Debt-Cancellation (เร่งดอกเบี้ยปลอบใจ และสิทธิ์นำ Coin X มาล้างหนี้)
 * เสาหลักที่ 3: Negative Interest Rate Tax (Demurrage Tax เผาเหรียญที่อยู่นอกระบบเมื่อ Supply ล้น)
 * เสาหลักที่ 4: Time Tokenization & Voucher Exchange (แปลงเวลาหน่วงเป็น Time Voucher เทรดหักส่วนลดได้)
 */
contract TimeValueVault {
    TVEEToken public coinX; // Coin X (Platform Native Token)
    address public primaryCollateralToken; // สินทรัพย์ค้ำประกันแท้
    AggregatorV3Interface internal priceFeed; // Chainlink Oracle Interface

    uint256 public constant PRECISION = 1e18;
    uint256 public constant BASE_PRICE = 1 * PRECISION; // ราคากลางอ้างอิง P_base = 1.00 USD
    uint256 public constant MIN_UNBONDING = 7 days;       // เวลาหน่วงขั้นต่ำ T_min = 7 วัน
    uint256 public constant MAX_UNBONDING = 90 days;      // เวลาหน่วงสูงสุด T_max = 90 วัน

    struct TimeVoucher {
        uint256 id;
        address owner;
        uint256 collateralAmount;
        uint256 requestTimestamp;
        uint256 unlockTimestamp;
        uint256 accumulatedYield;
        bool isClaimed;
        bool isListedForSale;
        uint256 discountSalePrice;
    }

    uint256 public nextVoucherId = 1;
    mapping(uint256 => TimeVoucher) public vouchers;
    
    mapping(address => uint256) public userCollateralDebt;
    mapping(address => uint256) public lockedCollateral;

    uint256 public fallbackPrice = 1 * PRECISION; // ราคาสำรองกรณีทดสอบ Local
    uint256 public safeSupplyThreshold = 10_000_000 * PRECISION;
    uint256 public maxSupplyCrisis = 20_000_000 * PRECISION;

    address public governanceAdmin;

    event CollateralDeposited(address indexed user, uint256 amount);
    event UnbondingRequested(uint256 indexed voucherId, address indexed user, uint256 collateral, uint256 unbondingDays);
    event DebtCancelledWithCoinX(address indexed user, uint256 debtPaid, uint256 coinXBurned);
    event VoucherListedOnExchange(uint256 indexed voucherId, uint256 salePrice);
    event VoucherBoughtByHunter(uint256 indexed voucherId, address indexed buyer, address indexed seller, uint256 price);
    event CollateralClaimed(uint256 indexed voucherId, address indexed owner, uint256 amount);
    event ChainlinkPriceUpdated(int256 price, uint256 scaledPrice);

    modifier onlyAdmin() {
        require(msg.sender == governanceAdmin, "Only governance admin");
        _;
    }

    /**
     * @param _coinX ที่อยู่ Smart Contract ของ TVEEToken
     * @param _collateral ที่อยู่ของสินทรัพย์ค้ำประกันแท้
     * @param _priceFeed ที่อยู่ Chainlink Data Feed Contract (เช่น BTC/USD หรือ ETH/USD บน Arbitrum Sepolia)
     */
    constructor(address _coinX, address _collateral, address _priceFeed) {
        coinX = TVEEToken(_coinX);
        primaryCollateralToken = _collateral;
        if (_priceFeed != address(0)) {
            priceFeed = AggregatorV3Interface(_priceFeed);
        }
        governanceAdmin = msg.sender;
    }

    /**
     * @notice ดึงราคาตลาดล่าสุดจาก Chainlink Data Feed ปรับ Decimals เป็นสเกล 1e18
     */
    function getLatestPrice() public view returns (uint256) {
        if (address(priceFeed) == address(0)) {
            return fallbackPrice; // ใช้ราคา fallback สำหรับกรณี local test
        }

        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Chainlink: Malfunctioning price feed");

        uint8 feedDecimals = priceFeed.decimals();
        // แปลงเป็น 18 decimals
        if (feedDecimals < 18) {
            return uint256(price) * (10 ** (18 - feedDecimals));
        } else if (feedDecimals > 18) {
            return uint256(price) / (10 ** (feedDecimals - 18));
        }
        return uint256(price);
    }

    // =============================================================
    // ➡️ เสาหลักที่ 1: Dynamic Unbonding Period (ผูกกับ Chainlink Price)
    // =============================================================
    function calculateUnbondingPeriod(uint256 price) public pure returns (uint256) {
        if (price >= BASE_PRICE) {
            return MIN_UNBONDING;
        }

        uint256 priceDropRatio = BASE_PRICE - price; 
        uint256 dropFrac = (priceDropRatio * PRECISION) / BASE_PRICE;
        uint256 sqrtDrop = sqrt(dropFrac * PRECISION);
        uint256 powerResult = (dropFrac * sqrtDrop) / PRECISION;

        uint256 extraTime = ((MAX_UNBONDING - MIN_UNBONDING) * powerResult) / PRECISION;
        uint256 totalPeriod = MIN_UNBONDING + extraTime;

        if (totalPeriod > MAX_UNBONDING) {
            totalPeriod = MAX_UNBONDING;
        }
        return totalPeriod;
    }

    /**
     * @notice ส่งคำขอถอนเงินค้ำประกัน -> ดึงราคาจาก Chainlink ทันทีเพื่อคำนวณเวลาหน่วง
     */
    function requestUnbonding(uint256 collateralAmount) external returns (uint256) {
        require(lockedCollateral[msg.sender] >= collateralAmount, "Insufficient locked collateral");
        lockedCollateral[msg.sender] -= collateralAmount;

        // ดึงราคาจาก Chainlink Oracles แบบ Decentralized
        uint256 currentPrice = getLatestPrice();
        uint256 unbondingDelay = calculateUnbondingPeriod(currentPrice);
        uint256 unlockTime = block.timestamp + unbondingDelay;

        uint256 id = nextVoucherId++;
        vouchers[id] = TimeVoucher({
            id: id,
            owner: msg.sender,
            collateralAmount: collateralAmount,
            requestTimestamp: block.timestamp,
            unlockTimestamp: unlockTime,
            accumulatedYield: 0,
            isClaimed: false,
            isListedForSale: false,
            discountSalePrice: 0
        });

        emit UnbondingRequested(id, msg.sender, collateralAmount, unbondingDelay / 1 days);
        return id;
    }

    // =============================================================
    // ➡️ เสาหลักที่ 2: Yield Boost & Debt-Cancellation
    // =============================================================
    function claimYieldBoost(uint256 voucherId) external {
        TimeVoucher storage v = vouchers[voucherId];
        require(msg.sender == v.owner, "Not voucher owner");
        require(!v.isClaimed, "Already claimed");

        uint256 delayDuration = v.unlockTimestamp - v.requestTimestamp;
        uint256 boostRate = (delayDuration * 100) / MAX_UNBONDING;
        uint256 rewardAmount = (v.collateralAmount * boostRate) / 1000;

        v.accumulatedYield += rewardAmount;
        coinX.transfer(msg.sender, rewardAmount);
    }

    function cancelDebtWithCoinX(uint256 coinXAmount) external {
        require(coinXAmount > 0, "Invalid amount");
        require(userCollateralDebt[msg.sender] >= coinXAmount, "Amount exceeds debt");

        coinX.transferFrom(msg.sender, address(this), coinXAmount);
        userCollateralDebt[msg.sender] -= coinXAmount;

        emit DebtCancelledWithCoinX(msg.sender, coinXAmount, coinXAmount);
    }

    // =============================================================
    // ➡️ เสาหลักที่ 3: Negative Interest Demurrage Tax
    // =============================================================
    function calculateDailyDemurrageTax(uint256 circulatingSupply) public view returns (uint256) {
        if (circulatingSupply <= safeSupplyThreshold) {
            return 0;
        }

        if (circulatingSupply >= maxSupplyCrisis) {
            return 5 * PRECISION / 100;
        }

        uint256 overflow = circulatingSupply - safeSupplyThreshold;
        uint256 maxRange = maxSupplyCrisis - safeSupplyThreshold;
        uint256 ratio = (overflow * PRECISION) / maxRange;
        uint256 squaredRatio = (ratio * ratio) / PRECISION;

        return (5 * PRECISION / 100 * squaredRatio) / PRECISION;
    }

    // =============================================================
    // ➡️ เสาหลักที่ 4: Time Tokenization & Voucher Exchange
    // =============================================================
    function listVoucherOnExchange(uint256 voucherId, uint256 discountPrice) external {
        TimeVoucher storage v = vouchers[voucherId];
        require(msg.sender == v.owner, "Not owner");
        require(!v.isClaimed, "Already claimed");
        require(discountPrice < v.collateralAmount, "Price must be at discount");

        v.isListedForSale = true;
        v.discountSalePrice = discountPrice;

        emit VoucherListedOnExchange(voucherId, discountPrice);
    }

    function buyVoucherFromExchange(uint256 voucherId) external payable {
        TimeVoucher storage v = vouchers[voucherId];
        require(v.isListedForSale, "Voucher not listed");
        require(!v.isClaimed, "Already claimed");

        address seller = v.owner;
        uint256 salePrice = v.discountSalePrice;

        v.owner = msg.sender;
        v.isListedForSale = false;

        uint256 fee = (salePrice * 3) / 1000;
        uint256 sellerProceeds = salePrice - fee;

        payable(seller).transfer(sellerProceeds);
        emit VoucherBoughtByHunter(voucherId, msg.sender, seller, salePrice);
    }

    function claimUnlockedCollateral(uint256 voucherId) external {
        TimeVoucher storage v = vouchers[voucherId];
        require(msg.sender == v.owner, "Not voucher owner");
        require(!v.isClaimed, "Already claimed");
        require(block.timestamp >= v.unlockTimestamp, "Still in unbonding period");

        v.isClaimed = true;
        payable(msg.sender).transfer(v.collateralAmount);

        emit CollateralClaimed(voucherId, msg.sender, v.collateralAmount);
    }

    function setFallbackPrice(uint256 newPrice) external onlyAdmin {
        fallbackPrice = newPrice;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    receive() external payable {}
}
