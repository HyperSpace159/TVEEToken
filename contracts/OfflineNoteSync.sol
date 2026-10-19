// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TVEEToken.sol";

/**
 * @title OfflineNoteSync
 * @notice สัญญาอัจฉริยะควบคุมการซิงค์ธนบัตรสีออฟไลน์ First-to-Sync และระบบริบทรัพย์คลังคนโกง (Slashing)
 */
contract OfflineNoteSync {
    TVEEToken public tveeToken;

    // ข้อมูลของธนบัตรกระดาษแต่ละใบ (JAB Code Note)
    struct PhysicalNote {
        bytes32 tokenHash;         // รหัส Hash ประจำใบจาก JAB Code
        address mintedVault;       // คลังทุนใหญ่ผู้ค้ำประกันการพิมพ์
        uint256 denominationValue; // มูลค่าที่ผูกกับธนบัตรสี (เช่น สีเขียว = 10 TVEE)
        uint256 printedTimestamp;  // วันเวลาที่พิมพ์
        bool isMinted;             // สถานะการลงทะเบียน
    }

    // ข้อมูลรอบการซิงค์ (Epoch Period)
    uint256 public currentEpoch;
    uint256 public constant EPOCH_DURATION = 1 days;
    uint256 public lastEpochRollTime;

    // tokenHash => PhysicalNote
    mapping(bytes32 => PhysicalNote) public notes;

    // tokenHash => epoch => ซิงค์ไปแล้วหรือยัง
    mapping(bytes32 => mapping(uint256 => bool)) public isSyncCompleted;

    // ตรวจสอบว่าเคยซิงค์ในประวัติศาสตร์ระบบหรือไม่
    mapping(bytes32 => bool) public hasBeenSyncedBefore;

    // บัญชีผู้ชนะในการซิงค์แต่ละรอบ
    mapping(bytes32 => mapping(uint256 => address)) public firstSyncer;

    // เงินค้ำประกันของคลังผู้ออกธนบัตร (Vault Collateral)
    mapping(address => uint256) public vaultCollateral;

    event NoteRegistered(bytes32 indexed tokenHash, address indexed vault, uint256 denomination);
    event NoteSyncedSuccess(bytes32 indexed tokenHash, address indexed claimant, uint256 amount, uint256 epoch);
    event SlashingExecuted(address indexed rogueVault, address indexed victim, uint256 penaltyAmount, bytes32 indexed tokenHash);
    event CollateralDeposited(address indexed vault, uint256 amount);

    constructor(address _tveeToken) {
        tveeToken = TVEEToken(_tveeToken);
        lastEpochRollTime = block.timestamp;
        currentEpoch = 1;
    }

    /**
     * @notice ฝากเงินค้ำประกันเพื่อเปิดสิทธิ์พิมพ์ธนบัตรสีออฟไลน์
     */
    function depositCollateral(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        tveeToken.transferFrom(msg.sender, address(this), amount);
        vaultCollateral[msg.sender] += amount;
        emit CollateralDeposited(msg.sender, amount);
    }

    /**
     * @notice ลงทะเบียน Token Hash ของธนบัตรสีที่พิมพ์ออกจากคลัง
     */
    function registerPhysicalNote(bytes32 tokenHash, uint256 value) external {
        require(!notes[tokenHash].isMinted, "Note already exists");
        require(vaultCollateral[msg.sender] >= value * 10, "Need 10x collateral reserve");

        notes[tokenHash] = PhysicalNote({
            tokenHash: tokenHash,
            mintedVault: msg.sender,
            denominationValue: value,
            printedTimestamp: block.timestamp,
            isMinted: true
        });

        emit NoteRegistered(tokenHash, msg.sender, value);
    }

    /**
     * @notice ฟังก์ชันซิงค์แรกชนะ และตรวจจับริบทรัพย์คนโกง (First-To-Sync Wins & Slashing Workflow)
     * @param tokenHash รหัส Hash จากการสแกน JAB Code หน้าธนบัตร
     * @param claimant กระเป๋าเงินของชาวบ้านหรือร้านค้าผู้สแกน
     */
    function firstSyncWinsAndSlash(
        bytes32 tokenHash,
        address claimant
    ) public returns (bool) {
        _rollEpochIfNeeded();

        PhysicalNote memory note = notes[tokenHash];
        require(note.isMinted, "Invalid or unregistered token hash");

        // กรณีที่ 1: เป็นคนแรกที่นำมาสแกนซิงค์ในรอบปัจจุบัน
        if (!isSyncCompleted[tokenHash][currentEpoch]) {
            isSyncCompleted[tokenHash][currentEpoch] = true;
            hasBeenSyncedBefore[tokenHash] = true;
            firstSyncer[tokenHash][currentEpoch] = claimant;

            // โอนมูลค่าเงินดิจิทัลเข้ากระเป๋าผู้สแกน
            tveeToken.creditFromOffline(claimant, note.denominationValue);

            emit NoteSyncedSuccess(tokenHash, claimant, note.denominationValue, currentEpoch);
            return true;
        } 
        // กรณีที่ 2: มีคนส่งรหัสนี้ซ้ำในรอบเดียวกัน (ตรวจพบ Double-Spending หรือการก๊อปปี้กระดาษ)
        else {
            address rogueVault = note.mintedVault;
            uint256 penaltyAmount = note.denominationValue * 10; // บทลงโทษ 10 เท่า

            require(vaultCollateral[rogueVault] >= penaltyAmount, "Vault collateral depleted");

            // ริบเงินค้ำประกันของคลังต้นทาง โอนตรงเข้ากระเป๋าผู้เสียหายทันที
            vaultCollateral[rogueVault] -= penaltyAmount;
            tveeToken.creditFromOffline(claimant, penaltyAmount);

            emit SlashingExecuted(rogueVault, claimant, penaltyAmount, tokenHash);
            return true;
        }
    }

    function _rollEpochIfNeeded() internal {
        if (block.timestamp >= lastEpochRollTime + EPOCH_DURATION) {
            currentEpoch += 1;
            lastEpochRollTime = block.timestamp;
        }
    }
}
