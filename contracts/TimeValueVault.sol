// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TVEEToken.sol";

/**
 * @title TimeValueVault
 * @notice The Time-Value Ecosystem: ระบบนิเวศการเงินปิดเชิงเวลาและกลไกพยุงชีพ 4 เสาหลัก
 * 
 * เสาหลักที่ 1: Dynamic Unbonding Period (ระบบหน่วงเวลาแปรผันตามราคา Exponential Circuit Breaker)
 * เสาหลักที่ 2: Yield Boost & Debt-Cancellation (เร่งดอกเบี้ยปลอบใจ และสิทธิ์นำ Coin X มาล้างหนี้)
 * เสาหลักที่ 3: Negative Interest Rate Tax (Demurrage Tax เผาเหรียญที่อยู่นอกระบบเมื่อ Supply ล้น)
 * เสาหลักที่ 4: Time Tokenization & Voucher Exchange (แปลงเวลาหน่วงเป็น Time Voucher เทรดหักส่วนลดได้)
 */
contract TimeValueVault {
    TVEEToken public coinX; // Coin X (Platform Native Token)
    address public primaryCollateralToken; // สินทรัพย์ค้ำประกันแท้ (เช่น BTC/ETH หรือ Stablecoin)

    uint256 public constant PRECISION = 1e18;
    uint256 public constant BASE_PRICE = 1 * PRECISION; // ราคากลางอ้างอิง P_base = 1.00 USD
    uint256 public constant MIN_UNBONDING = 7 days;       // เวลาหน่วงขั้นต่ำ T_min = 7 วัน
    uint256 public constant MAX_UNBONDING = 90 days;      // เวลาหน่วงสูงสุด T_max = 90 วัน

    // -------------------------------------------------------------
    // โครงสร้างข้อมูลตั๋วเวลา (Time Voucher / Unbonding Request)
    // -------------------------------------------------------------
    struct TimeVoucher {
        uint256 id;
        address owner;
        uint256 collateralAmount; // จำนวนสินทรัพย์ค้ำประกันที่ขอยกเลิกการล็อก
        uint256 requestTimestamp; // เวลาที่เริ่มส่งคำขอถอน
        uint256 unlockTimestamp;  // เวลาที่จะปลดล็อกจริง (คำนวณผ่าน Dynamic Unbonding)
        uint256 accumulatedYield; // Yield ปลอบใจที่ได้รับระหว่างรอ
        bool isClaimed;           // ถอนเงินค้ำประกันไปแล้วหรือยัง
        bool isListedForSale;     // ตั้งขายในกระดานเทรดเวลาหรือไม่
        uint256 discountSalePrice; // ราคาเสนอขายลดส่วน
    }

    uint256 public nextVoucherId = 1;
    mapping(uint256 => TimeVoucher) public vouchers;
    
    // บันทึกยอดหนี้ค้ำประกันของผู้ใช้แต่ละคน (User Debt)
    mapping(address => uint256) public userCollateralDebt;
    mapping(address => uint256) public lockedCollateral;

    // ออราเคิลราคา Coin X และปริมาณเหรียญหมุนเวียน
    uint256 public currentPriceCoinX = 1 * PRECISION; // ราคาปัจจุบันของ Coin X
    uint256 public safeSupplyThreshold = 10_000_000 * PRECISION; // เพดาน Supply ปลอดภัย
    uint256 public maxSupplyCrisis = 20_000_000 * PRECISION;     // จุดวิกฤต Supply ล้น

    address public oracleAdmin;

    event CollateralDeposited(address indexed user, uint256 amount);
    event UnbondingRequested(uint256 indexed voucherId, address indexed user, uint256 collateral, uint256 unbondingDays);
    event DebtCancelledWithCoinX(address indexed user, uint256 debtPaid, uint256 coinXBurned);
    event VoucherListedOnExchange(uint256 indexed voucherId, uint256 salePrice);
    event VoucherBoughtByHunter(uint256 indexed voucherId, address indexed buyer, address indexed seller, uint256 price);
    event CollateralClaimed(uint256 indexed voucherId, address indexed owner, uint256 amount);

    modifier onlyOracle() {
        require(msg.sender == oracleAdmin, "Only oracle admin");
        _;
    }

    constructor(address _coinX, address _collateral) {
        coinX = TVEEToken(_coinX);
        primaryCollateralToken = _collateral;
        oracleAdmin = msg.sender;
    }

    // =============================================================
    // ➡️ เสาหลักที่ 1: Dynamic Unbonding Period (ระบบหน่วงเวลาแปรผันตามราคา)
    // =============================================================
    /**
     * @notice คำนวณระยะเวลาหน่วงถอน: T(P) = T_min + (T_max - T_min) * (1 - P/P_base)^1.5
     */
    function calculateUnbondingPeriod(uint256 price) public pure returns (uint256) {
        if (price >= BASE_PRICE) {
            return MIN_UNBONDING; // สภาวะปกติ หน่วงแค่ 7 วัน
        }

        // สัดส่วนราคาที่ร่วงลงมา (1 - P / P_base)
        uint256 priceDropRatio = BASE_PRICE - price; 
        
        // Approx (dropRatio / BASE_PRICE)^1.5 ด้วย fixed point
        // drop^1.5 = drop * sqrt(drop)
        uint256 dropFrac = (priceDropRatio * PRECISION) / BASE_PRICE;
        uint256 sqrtDrop = sqrt(dropFrac * PRECISION);
        uint256 powerResult = (dropFrac * sqrtDrop) / PRECISION;

        uint256 extraTime = ((MAX_UNBONDING - MIN_UNBONDING) * powerResult) / PRECISION;
        uint256 totalPeriod = MIN_UNBONDING + extraTime;

        if (totalPeriod > MAX_UNBONDING) {
            totalPeriod = MAX_UNBONDING; // ชนเพดาน 90 วัน
        }
        return totalPeriod;
    }

    /**
     * @notice ผู้ใช้ส่งคำขอถอนเงินค้ำประกัน -> ระบบจะออก Time Voucher และคิดเวลาหน่วงแปรผันตามราคาตลาด
     */
    function requestUnbonding(uint256 collateralAmount) external returns (uint256) {
        require(lockedCollateral[msg.sender] >= collateralAmount, "Insufficient locked collateral");
        lockedCollateral[msg.sender] -= collateralAmount;

        uint256 unbondingDelay = calculateUnbondingPeriod(currentPriceCoinX);
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
    // ➡️ เสาหลักที่ 2: Yield Boost & Debt-Cancellation (ดอกเบี้ยปลอบใจและล้างหนี้)
    // =============================================================
    /**
     * @notice ระหว่างติดล็อก ระบบเร่งจ่าย Yield เป็น Coin X เพิ่มขึ้นตามระยะเวลาที่ถูกหน่วง
     */
    function claimYieldBoost(uint256 voucherId) external {
        TimeVoucher storage v = vouchers[voucherId];
        require(msg.sender == v.owner, "Not voucher owner");
        require(!v.isClaimed, "Already claimed");

        uint256 delayDuration = v.unlockTimestamp - v.requestTimestamp;
        // ยิ่งหน่วงนาน ดอกเบี้ยยิ่งทวีคูณ (ชดเชยความเสี่ยง)
        uint256 boostRate = (delayDuration * 100) / MAX_UNBONDING; // 0% - 100% Boost
        uint256 rewardAmount = (v.collateralAmount * boostRate) / 1000;

        v.accumulatedYield += rewardAmount;
        // จ่ายเป็น Coin X เข้ากระเป๋าผู้ใช้
        coinX.transfer(msg.sender, rewardAmount);
    }

    /**
     * @notice นำ Coin X ที่ช้อนซื้อมาจากตลาดภายนอก มา "หักล้างหนี้ค้ำประกัน" ในระบบได้ทันที
     * ก่อให้เกิดแรงซื้อคืน (Buying Pressure) ช่วยพยุงราคา Coin X
     */
    function cancelDebtWithCoinX(uint256 coinXAmount) external {
        require(coinXAmount > 0, "Invalid amount");
        require(userCollateralDebt[msg.sender] >= coinXAmount, "Amount exceeds debt");

        // เผาทำลายหรือดึง Coin X ออกจากกระเป๋าเพื่อหักลบหนี้
        coinX.transferFrom(msg.sender, address(this), coinXAmount);
        userCollateralDebt[msg.sender] -= coinXAmount;

        emit DebtCancelledWithCoinX(msg.sender, coinXAmount, coinXAmount);
    }

    // =============================================================
    // ➡️ เสาหลักที่ 3: Negative Interest Rate Tax (Demurrage Tax ยามเงินล้น)
    // =============================================================
    /**
     * @notice คำนวณอัตราภาษีติดลบรายวัน Tax(S) = MaxTax * ((S - S_thresh) / (S_max - S_thresh))^2
     */
    function calculateDailyDemurrageTax(uint256 circulatingSupply) public view returns (uint256) {
        if (circulatingSupply <= safeSupplyThreshold) {
            return 0; // Supply ยังปลอดภัย ไม่เก็บภาษี
        }

        if (circulatingSupply >= maxSupplyCrisis) {
            return 5 * PRECISION / 100; // วิกฤตเงินล้น เพดานภาษีติดลบ 5% ต่อวัน
        }

        uint256 overflow = circulatingSupply - safeSupplyThreshold;
        uint256 maxRange = maxSupplyCrisis - safeSupplyThreshold;
        uint256 ratio = (overflow * PRECISION) / maxRange;

        // ratio^2 (ความชันเร่งตัวแบบทวีคูณ)
        uint256 squaredRatio = (ratio * ratio) / PRECISION;
        uint256 dailyTax = (5 * PRECISION / 100 * squaredRatio) / PRECISION;

        return dailyTax;
    }

    // =============================================================
    // ➡️ เสาหลักที่ 4: Time Tokenization & Voucher Exchange (กระดานเทรดเวลา)
    // =============================================================
    /**
     * @notice คนใจร้อน นำตั๋วเวลามาตั้งขายในกระดานแบบหักส่วนลด (Discount Sale) เพื่อแลกเงินสดไปใช้ก่อน
     */
    function listVoucherOnExchange(uint256 voucherId, uint256 discountPrice) external {
        TimeVoucher storage v = vouchers[voucherId];
        require(msg.sender == v.owner, "Not owner");
        require(!v.isClaimed, "Already claimed");
        require(discountPrice < v.collateralAmount, "Price must be at discount");

        v.isListedForSale = true;
        v.discountSalePrice = discountPrice;

        emit VoucherListedOnExchange(voucherId, discountPrice);
    }

    /**
     * @notice คนใจเย็น / กองทุน 200,000 บาท เข้ามาเป็น Discount Hunter ช้อนซื้อตั๋วราคาถูก
     * จ่ายเงินสดให้คนใจร้อนทันที แล้วรอรับเงินค้ำประกันเต็มจำนวนเมื่อครบกำหนด
     */
    function buyVoucherFromExchange(uint256 voucherId) external payable {
        TimeVoucher storage v = vouchers[voucherId];
        require(v.isListedForSale, "Voucher not listed");
        require(!v.isClaimed, "Already claimed");

        address seller = v.owner;
        uint256 salePrice = v.discountSalePrice;

        // เปลี่ยนเจ้าของตั๋วเวลาเป็นผู้ซื้อคนใหม่
        v.owner = msg.sender;
        v.isListedForSale = false;

        // จ่ายเงินให้คนขาย (หักค่าธรรมเนียมแพลตฟอร์ม 0.3%)
        uint256 fee = (salePrice * 3) / 1000;
        uint256 sellerProceeds = salePrice - fee;

        payable(seller).transfer(sellerProceeds);

        emit VoucherBoughtByHunter(voucherId, msg.sender, seller, salePrice);
    }

    /**
     * @notice เมื่อครบกำหนดเวลาหน่วง ผู้ถือตั๋วสามารถถอนเงินค้ำประกันแท้ออกไปได้เต็ม 100%
     */
    function claimUnlockedCollateral(uint256 voucherId) external {
        TimeVoucher storage v = vouchers[voucherId];
        require(msg.sender == v.owner, "Not voucher owner");
        require(!v.isClaimed, "Already claimed");
        require(block.timestamp >= v.unlockTimestamp, "Still in unbonding period");

        v.isClaimed = true;
        payable(msg.sender).transfer(v.collateralAmount);

        emit CollateralClaimed(voucherId, msg.sender, v.collateralAmount);
    }

    // ฟังก์ชันอัปเดตราคาตลาดจาก Oracle
    function updateOracleState(uint256 newPrice) external onlyOracle {
        currentPriceCoinX = newPrice;
    }

    // Helper คำนวณ Square Root
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
