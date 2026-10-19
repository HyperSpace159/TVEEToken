// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TVEEToken
 * @notice Global Open-Source Financial Protocol (Freigeld / Gesell Demurrage Core)
 * @dev รองรับ Dynamic Demurrage Tax, Retail Protection Threshold, และ Global Elastic Rebase
 */
contract TVEEToken {
    string public name = "T-VEE Currency";
    string public symbol = "TVEE";
    uint8 public constant decimals = 18;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 31536000;

    // อุปทานเงินรวมที่ปรับฐานแล้ว
    uint256 private _totalRawSupply;
    uint256 public rebaseFactor = 1e18; // alpha factor (เริ่มต้น 1.0)

    // ข้อมูลกระเป๋าเงินแต่ละบัญชี
    struct AccountInfo {
        uint256 rawBalance;         // ยอดคงเหลือก่อนหัก Demurrage
        uint256 lastSyncTimestamp;  // เวลาซิงค์ล่าสุด
        bool isExempt;              // บัญชีระบบหรือพูลสภาพคล่องที่ยกเว้น
    }

    mapping(address => AccountInfo) public accounts;
    mapping(address => mapping(address => uint256)) public allowance;

    // พารามิเตอร์ของระบบ (Oracle & Governance/Protocol Locked)
    address public protocolAdmin;
    address public oracleAddress;
    address public syncContract;

    uint256 public baseLambda = 5e16;           // อัตรา Demurrage เริ่มต้น 5% ต่อปี (สเกล 1e18)
    uint256 public balanceTarget = 10000 * 1e18; // ยอดเป้าหมาย B_target (10,000 TVEE)
    uint256 public retailThreshold = 1000 * 1e18; // เกณฑ์คุ้มครองรายย่อย (ต่ำกว่านี้ Demurrage = 0)
    
    // อัตราการไหลเข้าออกของ TVL เพื่อป้องกัน Bank Run
    uint256 public tvlOutRatio = 1e18;          // ΔTVL_out / ΔTVL_in (Default = 1.0)
    uint256 public velocityRatio = 1e18;        // v_target / v_actual (Default = 1.0)

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event RebaseExecuted(uint256 indexed timestamp, uint256 newRebaseFactor);
    event DemurrageBurned(address indexed account, uint256 burnedAmount);
    event RetailThresholdUpdated(uint256 newThreshold);

    modifier onlyAdmin() {
        require(msg.sender == protocolAdmin, "Only admin");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracleAddress, "Only oracle");
        _;
    }

    modifier onlySyncContract() {
        require(msg.sender == syncContract, "Only sync contract");
        _;
    }

    constructor(address _oracle) {
        protocolAdmin = msg.sender;
        oracleAddress = _oracle;
        
        // Mint Initial Supply 100,000,000 TVEE
        uint256 initialSupply = 100_000_000 * 1e18;
        _totalRawSupply = initialSupply;
        accounts[msg.sender].rawBalance = initialSupply;
        accounts[msg.sender].lastSyncTimestamp = block.timestamp;
        
        emit Transfer(address(0), msg.sender, initialSupply);
    }

    function setSyncContract(address _sync) external onlyAdmin {
        syncContract = _sync;
    }

    /**
     * @notice คำนวณสัมประสิทธิ์ Demurrage λ(B)
     * λ(B) = λ0 * (B / B_target)^gamma * (1 + ΔTVL_out/ΔTVL_in) * (v_target / v_actual)
     */
    function calculateLambda(address account) public view returns (uint256) {
        uint256 bal = accounts[account].rawBalance;
        
        // คุ้มครองรายย่อย: ต่ำกว่าเกณฑ์ ไม่เสีย Demurrage เลย (λ = 0)
        if (bal <= retailThreshold || accounts[account].isExempt) {
            return 0;
        }

        // คำนวณแบบก้าวหน้าตามความมั่งคั่ง
        uint256 wealthRatio = (bal * PRECISION) / balanceTarget;
        uint256 tvlMultiplier = PRECISION + tvlOutRatio;
        
        uint256 lambda = (baseLambda * wealthRatio) / PRECISION;
        lambda = (lambda * tvlMultiplier) / PRECISION;
        lambda = (lambda * velocityRatio) / PRECISION;

        return lambda;
    }

    /**
     * @notice คำนวณส่วนลดมูลค่าตามสูตร e^(-λ * Δt) โดยใช้ Taylor series 1st order approximation
     */
    function computeDecayedBalance(address account) public view returns (uint256) {
        AccountInfo memory acc = accounts[account];
        if (acc.rawBalance == 0) return 0;
        
        uint256 deltaT = block.timestamp - acc.lastSyncTimestamp;
        if (deltaT == 0) return (acc.rawBalance * rebaseFactor) / PRECISION;

        uint256 lambda = calculateLambda(account);
        if (lambda == 0) {
            return (acc.rawBalance * rebaseFactor) / PRECISION;
        }

        // λ * Δt / SECONDS_PER_YEAR
        uint256 decayExponent = (lambda * deltaT) / SECONDS_PER_YEAR;

        // Approximating e^(-x) as 1 - x (for small interval updates) or clamped if decay is heavy
        uint256 factor;
        if (decayExponent >= PRECISION) {
            factor = 0; // สูญมูลค่าทั้งหมดหากดองเงินทิ้งไว้นานเกินไป
        } else {
            factor = PRECISION - decayExponent;
        }

        uint256 decayedRaw = (acc.rawBalance * factor) / PRECISION;
        return (decayedRaw * rebaseFactor) / PRECISION;
    }

    /**
     * @notice ปรับยอดเงินจริงของบัญชีให้เป็นปัจจุบัน (Apply Demurrage Sync)
     */
    function syncAccount(address account) public returns (uint256) {
        AccountInfo storage acc = accounts[account];
        uint256 currentBalance = computeDecayedBalance(account);
        uint256 oldEffective = (acc.rawBalance * rebaseFactor) / PRECISION;

        if (oldEffective > currentBalance) {
            uint256 burned = oldEffective - currentBalance;
            emit DemurrageBurned(account, burned);
        }

        // แปลงกลับเป็น Raw Balance
        acc.rawBalance = (currentBalance * PRECISION) / rebaseFactor;
        acc.lastSyncTimestamp = block.timestamp;

        return currentBalance;
    }

    /**
     * @notice ปรับฐานอุปทานเงินรวม Global Rebase ผ่าน Oracle: Vt = Vt-1 * alpha(t)
     */
    function executeRebase(
        uint256 qt,
        uint256 pTarget,
        uint256 mt,
        uint256 vActual
    ) external onlyOracle {
        require(mt > 0 && vActual > 0, "Invalid denominator");
        
        // alpha(t) = (Q_t * P_target) / (M_t * v_actual)
        uint256 numerator = qt * pTarget;
        uint256 denominator = mt * vActual;
        uint256 alpha = (numerator * PRECISION) / denominator;

        rebaseFactor = (rebaseFactor * alpha) / PRECISION;
        emit RebaseExecuted(block.timestamp, rebaseFactor);
    }

    function balanceOf(address account) external view returns (uint256) {
        return computeDecayedBalance(account);
    }

    function totalSupply() external view returns (uint256) {
        return (_totalRawSupply * rebaseFactor) / PRECISION;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        require(currentAllowance >= amount, "Allowance exceeded");
        allowance[from][msg.sender] = currentAllowance - amount;

        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero");
        require(to != address(0), "Transfer to zero");

        // Sync ยอดทั้งสองบัญชีก่อนโอน
        syncAccount(from);
        syncAccount(to);

        uint256 rawAmount = (amount * PRECISION) / rebaseFactor;
        require(accounts[from].rawBalance >= rawAmount, "Insufficient balance");

        accounts[from].rawBalance -= rawAmount;
        accounts[to].rawBalance += rawAmount;

        emit Transfer(from, to, amount);
    }

    /**
     * @dev ฟังก์ชันสำหรับ Sync Contract เพื่อเพิ่ม/ลดโทเคนจากการแลกธนบัตรสีออฟไลน์
     */
    function creditFromOffline(address to, uint256 amount) external onlySyncContract {
        syncAccount(to);
        uint256 rawAmount = (amount * PRECISION) / rebaseFactor;
        accounts[to].rawBalance += rawAmount;
        _totalRawSupply += rawAmount;
        emit Transfer(address(0), to, amount);
    }

    function slashDebit(address rogueVault, uint256 amount) external onlySyncContract {
        syncAccount(rogueVault);
        uint256 rawAmount = (amount * PRECISION) / rebaseFactor;
        require(accounts[rogueVault].rawBalance >= rawAmount, "Vault bankrupt");
        accounts[rogueVault].rawBalance -= rawAmount;
        _totalRawSupply -= rawAmount;
    }
}
