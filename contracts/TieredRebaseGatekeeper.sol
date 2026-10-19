// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TieredRebaseGatekeeper
 * @notice ระบบปรับฐานสัมประสิทธิ์กลางเรียลไทม์ O(1) และด่านคัดกรองตัวตน (The Zero-Bot Architecture)
 * 
 * 🧮 1. Algorithmic Curve:
 *    - S_current <= S_target => globalK = 1.0 (ปกติ เงินไม่ฝ่อ)
 *    - S_current > S_target  => globalK = 1.0 - ((S_current - S_target)/(S_max - S_target))^2 * MaxPenalty
 * 
 * 🛡️ 2. Tiered Scaling:
 *    - Retail Tier (< 100,000 Coins) + Proof of Humanity => globalK = 1.0 ตลอดกาล
 *    - Whale Tier (>= 100,000 Coins) => ปรับลดมูลค่าเรียลไทม์ตาม globalK
 * 
 * 🥷 3. Gatekeeper Armor:
 *    - Proof of Humanity (World ID / SBT Gate)
 *    - Daily Velocity Limit สกัดกั้น Flash-Mob Swarm
 */
contract TieredRebaseGatekeeper {
    uint256 public constant PRECISION = 1e18;
    
    // พารามิเตอร์ของระบบ (เป้าหมายอุปทานเงิน)
    uint256 public constant S_TARGET = 10_000_000 * PRECISION; // 10,000,000 Coins (เพดานปลอดภัย)
    uint256 public constant S_MAX = 20_000_000 * PRECISION;    // 20,000,000 Coins (จุดวิกฤตสูงสุด)
    uint256 public constant MAX_PENALTY = 5 * 1e16;            // ลดขนาดสูงสุด 5% (0.05 * 1e18)
    
    uint256 public constant RETAIL_THRESHOLD = 100_000 * PRECISION; // เกณฑ์คนเงินน้อย (100,000 Coins)
    uint256 public constant DAILY_VELOCITY_LIMIT = 50_000 * PRECISION; // จำกัดเพดานการถอนต่อวันต่อคน

    // ทะเบียนยืนยันตัวตนมนุษย์จริง (Proof of Humanity / World ID Status)
    mapping(address => bool) public isHumanVerified;
    
    // บันทึกปริมาณการโอน/ถอนรายวัน (Velocity Tracker)
    mapping(address => mapping(uint256 => uint256)) public dailyTransfers;

    address public protocolGovernance;
    uint256 public currentMarketSupply = 8_000_000 * PRECISION; // เริ่มต้นที่ 8M Coins

    event GlobalKUpdated(uint256 currentSupply, uint256 globalK);
    event HumanVerified(address indexed user);
    event VelocityLimitBreached(address indexed user, uint256 attemptedAmount);

    modifier onlyGovernance() {
        require(msg.sender == protocolGovernance, "Only governance");
        _;
    }

    constructor() {
        protocolGovernance = msg.sender;
    }

    /**
     * @notice คำนวณค่าสัมประสิทธิ์ร่วมส่วนกลาง globalK แบบเรียลไทม์ O(1)
     */
    function calculateGlobalK(uint256 currentSupply) public pure returns (uint256) {
        if (currentSupply <= S_TARGET) {
            return PRECISION; // 1.0000 ปกติ
        }

        if (currentSupply >= S_MAX) {
            return PRECISION - MAX_PENALTY; // 0.9500 ชนเพดานลดขนาด 5%
        }

        // ((S_current - S_target) / (S_max - S_target))^2
        uint256 overflow = currentSupply - S_TARGET;
        uint256 range = S_MAX - S_TARGET;
        uint256 ratio = (overflow * PRECISION) / range;
        uint256 squaredRatio = (ratio * ratio) / PRECISION;

        uint256 penalty = (squaredRatio * MAX_PENALTY) / PRECISION;
        return PRECISION - penalty;
    }

    /**
     * @notice คำนวณยอดเงินจริงของผู้ใช้ตามเกณฑ์อุ้มชูรายย่อย (Tiered Scaling)
     */
    function getEffectiveBalance(address user, uint256 rawBalance) external view returns (uint256) {
        // กลุ่มที่ 1: รายย่อย (< 100,000 Coins) และเป็นมนุษย์จริง -> อุ้มชู 100% เงินไม่ฝ่อ
        if (rawBalance < RETAIL_THRESHOLD && isHumanVerified[user]) {
            return rawBalance; // globalK = 1.0 ถาวร
        }

        // กลุ่มที่ 2: ปลาวาฬ (>= 100,000 Coins) หรือไม่ผ่านการยืนยันตัวตน -> ปรับลดเรียลไทม์ตาม globalK
        uint256 k = calculateGlobalK(currentMarketSupply);
        return (rawBalance * k) / PRECISION;
    }

    /**
     * @notice ด่านคัดกรองตัวตน (Gatekeeper): ยืนยัน Proof of Humanity (World ID / Gitcoin)
     */
    function verifyHuman(address user) external onlyGovernance {
        isHumanVerified[user] = true;
        emit HumanVerified(user);
    }

    /**
     * @notice ด่านคัดกรองความเร็ว (Gatekeeper Velocity Limit): สกัดกั้นบอตฝูง Flash-Mob Swarm
     */
    function checkVelocityLimit(address user, uint256 amount) external returns (bool) {
        uint256 today = block.timestamp / 1 days;
        uint256 currentSpent = dailyTransfers[user][today];

        if (currentSpent + amount > DAILY_VELOCITY_LIMIT) {
            emit VelocityLimitBreached(user, amount);
            revert("Gatekeeper: Daily velocity limit breached (Flash-Mob Protection)");
        }

        dailyTransfers[user][today] += amount;
        return true;
    }

    function updateMarketSupply(uint256 newSupply) external onlyGovernance {
        currentMarketSupply = newSupply;
        emit GlobalKUpdated(newSupply, calculateGlobalK(newSupply));
    }
}
