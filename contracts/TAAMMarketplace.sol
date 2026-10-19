// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TVEEToken.sol";

/**
 * @title TAAMMarketplace
 * @notice ตลาดแลกเปลี่ยนสภาพคล่องสากล (Universal Liquidity Exchange) 
 * แปลง Credit Term / Invoice เป็นสินทรัพย์ให้ทุนใหญ่มาช้อนซื้อเพื่อหลบเลี่ยง Demurrage Tax
 */
contract TAAMMarketplace {
    TVEEToken public tveeToken;

    enum InvoiceStatus { Listed, Funded, Settled, Defaulted }

    struct CreditInvoice {
        uint256 id;
        address payable sellerSME; // บริษัท SME หรือผู้ขายที่ต้องการสภาพคล่องด่วน
        address investor;          // ทุนใหญ่ผู้เข้ามาซื้อสิทธิ์
        uint256 faceValue;         // มูลค่าหน้าตั๋วเมื่อครบกำหนด (เช่น 10,000 TVEE)
        uint256 salePrice;         // ราคาขายลดส่วน (เช่น 9,500 TVEE เพื่อจูงใจทุนใหญ่)
        uint256 maturityDate;      // วันครบกำหนดชำระเงิน
        InvoiceStatus status;
        string invoiceUri;         // ลิงก์เก็บเอกสารใบแจ้งหนี้ผ่าน IPFS
    }

    uint256 public nextInvoiceId = 1;
    mapping(uint256 => CreditInvoice) public invoices;

    event InvoiceListed(uint256 indexed id, address indexed seller, uint256 faceValue, uint256 salePrice, uint256 maturityDate);
    event InvoiceFunded(uint256 indexed id, address indexed investor, uint256 fundedAmount);
    event InvoiceSettled(uint256 indexed id, uint256 settlementAmount);

    constructor(address _tveeToken) {
        tveeToken = TVEEToken(_tveeToken);
    }

    /**
     * @notice SME นำเครดิตเทอมมาลิสต์ขายในตลาด
     */
    function listInvoice(
        uint256 faceValue,
        uint256 salePrice,
        uint256 termDays,
        string calldata uri
    ) external returns (uint256) {
        require(salePrice < faceValue, "Sale price must be discounted");
        require(termDays > 0, "Invalid term days");

        uint256 id = nextInvoiceId++;
        invoices[id] = CreditInvoice({
            id: id,
            sellerSME: payable(msg.sender),
            investor: address(0),
            faceValue: faceValue,
            salePrice: salePrice,
            maturityDate: block.timestamp + (termDays * 1 days),
            status: InvoiceStatus.Listed,
            invoiceUri: uri
        });

        emit InvoiceListed(id, msg.sender, faceValue, salePrice, block.timestamp + (termDays * 1 days));
        return id;
    }

    /**
     * @notice ทุนใหญ่เข้าซื้อสิทธิ์เพื่อหนีภาษีติดลบ (Demurrage Avoidance)
     */
    function buyInvoice(uint256 id) external {
        CreditInvoice storage invoice = invoices[id];
        require(invoice.status == InvoiceStatus.Listed, "Invoice not available");

        invoice.investor = msg.sender;
        invoice.status = InvoiceStatus.Funded;

        // โอนเงินสด T-VEE จากทุนใหญ่ตรงให้ SME ทันที
        tveeToken.transferFrom(msg.sender, invoice.sellerSME, invoice.salePrice);

        emit InvoiceFunded(id, msg.sender, invoice.salePrice);
    }

    /**
     * @notice ชำระคืนเงินเมื่อครบกำหนด (Settlement)
     */
    function settleInvoice(uint256 id) external {
        CreditInvoice storage invoice = invoices[id];
        require(invoice.status == InvoiceStatus.Funded, "Cannot settle");
        require(block.timestamp >= invoice.maturityDate, "Not yet mature");

        invoice.status = InvoiceStatus.Settled;
        // ชำระคืนเต็มจำนวนหน้าตั๋วแก่นักลงทุน
        tveeToken.transferFrom(msg.sender, invoice.investor, invoice.faceValue);

        emit InvoiceSettled(id, invoice.faceValue);
    }
}
