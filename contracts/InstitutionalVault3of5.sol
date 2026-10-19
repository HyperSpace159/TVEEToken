// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title InstitutionalVault3of5
 * @notice สถาปัตยกรรมคุมคลังหลวงร่วมสถาบันข้ามขั้วภูมิรัฐศาสตร์ (3-in-5 Multi-Signature Vault)
 * 
 * 🔑 โครงสร้างกุญแจดิจิทัล 5 ดอก:
 * - Key 1 & 2: ผู้ก่อตั้งโปรโตคอล T-VEE (Technical Administration)
 * - Key 3 & 4: สถาบันการเงิน / ธนาคารผู้รับฝากสินทรัพย์กายภาพ (Custodial Banks)
 * - Key 5: ผู้ตรวจสอบบัญชีอิสระสากล / Big 4 Auditor (Independent Tie-Breaker)
 * 
 * ข้อบังคับ: การเคลื่อนย้ายสินทรัพย์ค้ำประกันแท้ (BTC, ทองคำ, Stablecoin) 
 * ต้องได้รับเสียงอนุมัติขั้นต่ำ 3 ใน 5 กุญแจเสมอ ป้องกันการโกงหรือหอบเงินหนี (Zero Rug-Pull Risk)
 */
contract InstitutionalVault3of5 {
    uint256 public constant REQUIRED_SIGNATURES = 3;
    uint256 public constant TOTAL_SIGNERS = 5;

    address[5] public signers;
    mapping(address => bool) public isSigner;

    struct Proposal {
        uint256 id;
        address payable destination;
        uint256 amount;
        string reason;
        uint256 approvalCount;
        bool isExecuted;
    }

    uint256 public proposalCounter = 1;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasApproved;

    event SignerRegistered(address indexed signer, uint256 index);
    event ProposalCreated(uint256 indexed id, address indexed destination, uint256 amount, string reason);
    event ProposalApproved(uint256 indexed id, address indexed signer);
    event ProposalExecuted(uint256 indexed id, address indexed destination, uint256 amount);
    event CollateralReceived(address indexed sender, uint256 amount);

    modifier onlySigner() {
        require(isSigner[msg.sender], "Vault: Caller is not an authorized institutional signer");
        _;
    }

    constructor(address[5] memory _signers) {
        for (uint256 i = 0; i < 5; i++) {
            require(_signers[i] != address(0), "Invalid signer address");
            require(!isSigner[_signers[i]], "Duplicate signer");
            signers[i] = _signers[i];
            isSigner[_signers[i]] = true;
            emit SignerRegistered(_signers[i], i + 1);
        }
    }

    /**
     * @notice สถาบันยื่นข้อเสนอขอถอนหรือจัดสรรสินทรัพย์ค้ำประกัน
     */
    function createProposal(address payable destination, uint256 amount, string calldata reason) external onlySigner returns (uint256) {
        require(amount <= address(this).balance, "Insufficient vault reserves");
        uint256 id = proposalCounter++;

        proposals[id] = Proposal({
            id: id,
            destination: destination,
            amount: amount,
            reason: reason,
            approvalCount: 1,
            isExecuted: false
        });

        hasApproved[id][msg.sender] = true;
        emit ProposalCreated(id, destination, amount, reason);
        emit ProposalApproved(id, msg.sender);
        return id;
    }

    /**
     * @notice กุญแจอื่น ๆ เข้ามาลงนามอนุมัติ (Sign Approval)
     */
    function approveProposal(uint256 proposalId) external onlySigner {
        Proposal storage p = proposals[proposalId];
        require(!p.isExecuted, "Proposal already executed");
        require(!hasApproved[proposalId][msg.sender], "Already approved by this signer");

        hasApproved[proposalId][msg.sender] = true;
        p.approvalCount++;
        emit ProposalApproved(proposalId, msg.sender);

        // หากแตะ 3 ใน 5 เสียง -> สัญญาจะประมวลผลการโอนสินทรัพย์ทันทีอัตโนมัติ
        if (p.approvalCount >= REQUIRED_SIGNATURES) {
            _executeProposal(proposalId);
        }
    }

    function _executeProposal(uint256 proposalId) internal {
        Proposal storage p = proposals[proposalId];
        p.isExecuted = true;
        p.destination.transfer(p.amount);
        emit ProposalExecuted(proposalId, p.destination, p.amount);
    }

    receive() external payable {
        emit CollateralReceived(msg.sender, msg.value);
    }
}
