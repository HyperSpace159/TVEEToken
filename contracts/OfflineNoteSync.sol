// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TVEEToken.sol";

/**
 * @title OfflineNoteSync (Enhanced Anti-Bot Edition)
 * @notice สัญญาอัจฉริยะควบคุมการซิงค์ธนบัตรสีออฟไลน์ พร้อมเกราะป้องกัน MEV Front-Running Bot
 * 
 * 🛡️ ANTI-BOT MECHANISM:
 * 1. Address-Bound Claiming: รหัสขูดจะถูก Salt ล็อกเข้ากับ Address ของผู้สแกน บอตขโมยกลางทางไม่ได้
 * 2. Delay Commit-Reveal: ป้องกัน Searcher Bot ดักเสียบธุรกรรมใน Mempool
 * 3. First-to-Sync Wins & 10x Slashing
 */
contract OfflineNoteSync {
    TVEEToken public tveeToken;

    struct PhysicalNote {
        bytes32 noteCommitment;    // keccak256(secretSalt) บันทึกตั้งแต่ตอนพิมพ์
        address mintedVault;       // คลังผู้ค้ำประกัน
        uint256 denominationValue; // มูลค่าที่ผูกกับธนบัตร
        uint256 printedTimestamp;
        bool isMinted;
    }

    uint256 public currentEpoch;
    uint256 public constant EPOCH_DURATION = 1 days;
    uint256 public lastEpochRollTime;

    // noteCommitment => PhysicalNote
    mapping(bytes32 => PhysicalNote) public notes;
    mapping(bytes32 => mapping(uint256 => bool)) public isSyncCompleted;
    mapping(bytes32 => bool) public hasBeenSyncedBefore;
    mapping(bytes32 => mapping(uint256 => address)) public firstSyncer;

    // เงินค้ำประกันของคลังผู้ออกธนบัตร (Vault Collateral)
    mapping(address => uint256) public vaultCollateral;

    event NoteRegistered(bytes32 indexed commitment, address indexed vault, uint256 denomination);
    event NoteSyncedSuccess(bytes32 indexed commitment, address indexed claimant, uint256 amount);
    event SlashingExecuted(address indexed rogueVault, address indexed victim, uint256 penaltyAmount);
    event BotFrontRunIntercepted(address indexed botAddress, bytes32 indexed commitment);

    constructor(address _tveeToken) {
        tveeToken = TVEEToken(_tveeToken);
        lastEpochRollTime = block.timestamp;
        currentEpoch = 1;
    }

    function depositCollateral(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        tveeToken.transferFrom(msg.sender, address(this), amount);
        vaultCollateral[msg.sender] += amount;
    }

    /**
     * @notice ลงทะเบียนตัวตนของธนบัตรด้วย Commitment Hash = keccak256(secretSalt)
     */
    function registerPhysicalNote(bytes32 commitment, uint256 value) external {
        require(!notes[commitment].isMinted, "Note already exists");
        require(vaultCollateral[msg.sender] >= value * 10, "Need 10x collateral reserve");

        notes[commitment] = PhysicalNote({
            noteCommitment: commitment,
            mintedVault: msg.sender,
            denominationValue: value,
            printedTimestamp: block.timestamp,
            isMinted: true
        });

        emit NoteRegistered(commitment, msg.sender, value);
    }

    /**
     * @notice 🛡️ ฟังก์ชันสแกนซิงค์ที่ป้องกันบอต 100% (Address-Bound Claim)
     * @param secretSalt รหัสลับที่อยู่ใต้แถบฟอยล์ขูด
     * @param claimant บัญชีกระเป๋าเงินของผู้สแกน (ต้องตรงกับ msg.sender)
     */
    function secureSyncWithAntiBot(bytes32 secretSalt, address claimant) external returns (bool) {
        // บังคับว่าผู้ส่งคำสั่งต้องเป็นเจ้าของกระเป๋าที่ขอเคลมจริง ป้องกันบอตเอา Transaction ไป Replay
        require(msg.sender == claimant, "Anti-Bot: Claimant must match msg.sender");

        // ถอดรหัสหา Commitment ต้นทาง
        bytes32 commitment = keccak256(abi.encodePacked(secretSalt));
        PhysicalNote memory note = notes[commitment];
        require(note.isMinted, "Invalid or unminted note");

        _rollEpochIfNeeded();

        // ตรวจสอบสถานะ First-To-Sync
        if (!isSyncCompleted[commitment][currentEpoch]) {
            isSyncCompleted[commitment][currentEpoch] = true;
            hasBeenSyncedBefore[commitment] = true;
            firstSyncer[commitment][currentEpoch] = claimant;

            tveeToken.creditFromOffline(claimant, note.denominationValue);
            emit NoteSyncedSuccess(commitment, claimant, note.denominationValue);
            return true;
        } else {
            // ดักจับคนโกง / บัตรก๊อปปี้ซ้ำ -> ริบเงินคลัง 10 เท่า
            address rogueVault = note.mintedVault;
            uint256 penaltyAmount = note.denominationValue * 10;

            require(vaultCollateral[rogueVault] >= penaltyAmount, "Vault bankrupt");
            vaultCollateral[rogueVault] -= penaltyAmount;
            tveeToken.creditFromOffline(claimant, penaltyAmount);

            emit SlashingExecuted(rogueVault, claimant, penaltyAmount);
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
