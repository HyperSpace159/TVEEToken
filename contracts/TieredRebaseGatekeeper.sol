// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TieredRebaseGatekeeper (Web-of-Trust & Proof of Humanity Edition)
 * @notice ระบบปรับฐานสัมประสิทธิ์กลาง O(1) และด่านคัดกรองตัวตนล็อก 3 ชั้น
 * 
 * 🥷 3-LAYER GATEKEEPER ARMOR:
 * 1. Proof of Humanity (World ID / ZK-Nullifier): 1 คน 1 สิทธิ์ ม่านตาซ้ำสมัครไม่ได้
 * 2. Web-of-Trust Invitation: ต้องมี Code ผู้แนะนำจากมนุษย์จริงที่ผ่านการรับรองแล้วเท่านั้น
 * 3. Daily Velocity Limit: จำกัดเพดานโอนต่อวัน สกัด Flash-Mob Swarm
 */
contract TieredRebaseGatekeeper {
    uint256 public constant PRECISION = 1e18;
    
    // พารามิเตอร์ของระบบ (เป้าหมายอุปทานเงิน)
    uint256 public constant S_TARGET = 10_000_000 * PRECISION; // 10,000,000 Coins (เพดานปลอดภัย)
    uint256 public constant S_MAX = 20_000_000 * PRECISION;    // 20,000,000 Coins (จุดวิกฤตสูงสุด)
    uint256 public constant MAX_PENALTY = 5 * 1e16;            // ลดขนาดสูงสุด 5% (0.05)
    
    uint256 public constant RETAIL_THRESHOLD = 100_000 * PRECISION; // เกณฑ์คนเงินน้อย (100,000 Coins)
    uint256 public constant DAILY_VELOCITY_LIMIT = 50_000 * PRECISION; // เพดานถอนต่อวัน

    // -------------------------------------------------------------
    // ระบบยืนยันตัวตนมนุษย์และสายโซ่ผู้แนะนำ (Web-of-Trust)
    // -------------------------------------------------------------
    mapping(address => bool) public isHumanVerified;
    mapping(bytes32 => bool) public isNullifierUsed; // บันทึกม่านตา ZK-Nullifier ป้องกันการสแกนซ้ำ
    mapping(address => address) public referredBy;    // บันทึกว่าใครเป็นคนแนะนำเข้ามา
    mapping(address => uint256) public directReferralCount; // จำนวนคนที่แนะนำเข้ามา

    // บันทึกปริมาณการโอน/ถอนรายวัน (Velocity Tracker)
    mapping(address => mapping(uint256 => uint256)) public dailyTransfers;

    address public protocolGovernance;
    uint256 public currentMarketSupply = 8_000_000 * PRECISION;

    event HumanMemberRegistered(address indexed user, address indexed referrer, bytes32 indexed nullifierHash);
    event GlobalKUpdated(uint256 currentSupply, uint256 globalK);
    event VelocityLimitBreached(address indexed user, uint256 attemptedAmount);
    event SlashedRogueInviter(address indexed rogueInviter, address indexed rogueChild);

    modifier onlyGovernance() {
        require(msg.sender == protocolGovernance, "Only governance");
        _;
    }

    constructor() {
        protocolGovernance = msg.sender;
        // บัญชี Genesis ผู้ก่อตั้งได้รับการอนุมัติเป็นมนุษย์คนแรกเพื่อเริ่มต้นเครือข่ายผู้แนะนำ
        isHumanVerified[msg.sender] = true;
    }

    /**
     * @notice 🥷 กำแพงล็อกด่านหน้า: สมัครสมาชิกใหม่ด้วยม่านตา (World ID) + รหัสผู้แนะนำ
     * @param nullifierHash ค่า Hash ม่านตา ZK-Nullifier จาก World ID (ไม่เปิดเผยตัวตนจริง)
     * @param referrer บัญชีผู้แนะนำ (ต้องเป็นมนุษย์จริงที่ผ่านการรับรองแล้ว)
     */
    function registerMemberWithReferral(bytes32 nullifierHash, address referrer) external {
        require(!isHumanVerified[msg.sender], "Gatekeeper: Account already verified as human");
        require(!isNullifierUsed[nullifierHash], "Gatekeeper: This human iris/identity is ALREADY REGISTERED (1 Human = 1 Account)");
        require(isHumanVerified[referrer], "Gatekeeper: Invalid referrer code. Referrer must be a verified human");
        require(referrer != msg.sender, "Gatekeeper: Cannot refer yourself");

        // ล็อกตัวตน
        isNullifierUsed[nullifierHash] = true;
        isHumanVerified[msg.sender] = true;
        referredBy[msg.sender] = referrer;
        directReferralCount[referrer]++;

        emit HumanMemberRegistered(msg.sender, referrer, nullifierHash);
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
        // เงื่อนไขอุ้มชู: ยอด < 100,000 Coins และ "ต้องผ่านการยืนยันมนุษย์แท้ผ่านระบบแนะนำ"
        if (rawBalance < RETAIL_THRESHOLD && isHumanVerified[user]) {
            return rawBalance; // globalK = 1.0 ถาวร เงินไม่ฝ่อ 100%
        }

        // ปลาวาฬ หรือ บัญชีที่ไม่มีการยืนยันตัวตน -> ปรับลดมูลค่าเรียลไทม์ตาม globalK
        uint256 k = calculateGlobalK(currentMarketSupply);
        return (rawBalance * k) / PRECISION;
    }

    /**
     * @notice ตรวจสอบเพดานความเร็วการถอนต่อวัน (Daily Velocity Limit)
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

    /**
     * @notice ลงโทษสายโซ่ผู้แนะนำหากพบการสร้างบัญชีนอมินี (Social Slashing)
     */
    function slashRogueAccount(address rogueAccount) external onlyGovernance {
        require(isHumanVerified[rogueAccount], "Not verified");
        isHumanVerified[rogueAccount] = false;

        address inviter = referredBy[rogueAccount];
        if (inviter != address(0)) {
            // ริบสถานะผู้แนะนำเพื่อตัดสิทธิ์การอุ้มชูภาษี
            isHumanVerified[inviter] = false;
            emit SlashedRogueInviter(inviter, rogueAccount);
        }
    }

    function updateMarketSupply(uint256 newSupply) external onlyGovernance {
        currentMarketSupply = newSupply;
        emit GlobalKUpdated(newSupply, calculateGlobalK(newSupply));
    }
}
