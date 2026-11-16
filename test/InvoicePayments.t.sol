// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {InvoicePayments} from "../src/InvoicePayments.sol";
import {MockToken} from "../src/MockToken.sol";

/// @notice A token whose transferFrom re-enters the invoice contract.
///         Used to prove payInvoice cannot be double-paid via reentrancy.
contract ReentrantToken is MockToken {
    InvoicePayments public target;
    uint256 public targetId;

    constructor() MockToken("Reentrant tUSD8", "rtUSD8", 6) {}

    function arm(address target_, uint256 id_) external {
        target = InvoicePayments(target_);
        targetId = id_;
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        override
        returns (bool)
    {
        // Attack: try to pay the same invoice again while it is mid-payment.
        target.payInvoice(targetId);
        return super.transferFrom(from, to, amount);
    }
}

contract InvoicePaymentsTest is Test {
    InvoicePayments public inv;
    MockToken public token;

    address public payee = makeAddr("payee");
    address public payer = makeAddr("payer");
    address public stranger = makeAddr("stranger");

    uint256 public constant AMOUNT = 25_000_000; // 25.00 tUSD8 (6 decimals)

    event InvoiceCreated(
        uint256 indexed id,
        address indexed payee,
        address indexed payer,
        uint256 amount,
        uint256 dueDate,
        string memo
    );
    event InvoicePaid(uint256 indexed id, address indexed paidBy, uint256 amount, uint256 paidAt);
    event InvoiceCancelled(uint256 indexed id, address indexed cancelledBy);

    function setUp() public {
        token = new MockToken("tUSD8", "tUSD8", 6);
        inv = new InvoicePayments(address(token));
        token.mint(payer, 1_000_000_000); // 1,000 tUSD8
        token.mint(stranger, 1_000_000_000);
        vm.prank(payer);
        token.approve(address(inv), type(uint256).max);
        vm.prank(stranger);
        token.approve(address(inv), type(uint256).max);
    }

    // ---- createInvoice ----

    function testCreateInvoice() public {
        vm.prank(payee);
        vm.expectEmit(true, true, true, true, address(inv));
        emit InvoiceCreated(0, payee, payer, AMOUNT, block.timestamp + 7 days, "Web design");
        uint256 id = inv.createInvoice(payer, AMOUNT, block.timestamp + 7 days, "Web design");
        assertEq(id, 0);

        InvoicePayments.Invoice memory got = inv.getInvoice(0);
        assertEq(got.payee, payee);
        assertEq(got.payer, payer);
        assertEq(got.amount, AMOUNT);
        assertEq(got.dueDate, block.timestamp + 7 days);
        assertEq(got.memo, "Web design");
        assertEq(uint256(got.status), uint256(InvoicePayments.Status.Pending));
        assertEq(got.createdAt, block.timestamp);
        assertEq(got.paidAt, 0);
        assertEq(inv.invoiceCount(), 1);
    }

    function testCreateOpenInvoice() public {
        vm.prank(payee);
        uint256 id = inv.createInvoice(address(0), AMOUNT, 0, "Open invoice");
        assertEq(inv.getInvoice(id).payer, address(0));
        assertEq(inv.getInvoice(id).dueDate, 0);
    }

    function testCreateRevertsZeroAmount() public {
        vm.prank(payee);
        vm.expectRevert(InvoicePayments.ZeroAmount.selector);
        inv.createInvoice(payer, 0, 0, "x");
    }

    function testCreateRevertsPastDueDate() public {
        vm.warp(1_000_000);
        vm.prank(payee);
        vm.expectRevert(InvoicePayments.DueDateInPast.selector);
        inv.createInvoice(payer, AMOUNT, 999_999, "x");
    }

    function testCreateRevertsMemoTooLong() public {
        string memory longMemo = new string(501);
        vm.prank(payee);
        vm.expectRevert(InvoicePayments.MemoTooLong.selector);
        inv.createInvoice(payer, AMOUNT, 0, longMemo);
    }

    // ---- payInvoice ----

    function _createInvoice() internal returns (uint256) {
        vm.prank(payee);
        return inv.createInvoice(payer, AMOUNT, block.timestamp + 7 days, "Web design");
    }

    function testPayInvoice() public {
        uint256 id = _createInvoice();
        uint256 payeeBefore = token.balanceOf(payee);
        uint256 payerBefore = token.balanceOf(payer);

        vm.prank(payer);
        vm.expectEmit(true, true, false, true, address(inv));
        emit InvoicePaid(id, payer, AMOUNT, block.timestamp);
        inv.payInvoice(id);

        InvoicePayments.Invoice memory got = inv.getInvoice(id);
        assertEq(uint256(got.status), uint256(InvoicePayments.Status.Paid));
        assertEq(got.paidBy, payer);
        assertEq(got.paidAt, block.timestamp);
        assertEq(token.balanceOf(payee), payeeBefore + AMOUNT);
        assertEq(token.balanceOf(payer), payerBefore - AMOUNT);
    }

    function testPayOpenInvoiceByAnyone() public {
        vm.prank(payee);
        uint256 id = inv.createInvoice(address(0), AMOUNT, 0, "Open");
        uint256 before = token.balanceOf(payee);
        vm.prank(stranger);
        inv.payInvoice(id);
        assertEq(token.balanceOf(payee), before + AMOUNT);
        assertEq(inv.getInvoice(id).paidBy, stranger);
    }

    function testPayRevertsWrongPayer() public {
        uint256 id = _createInvoice();
        vm.prank(stranger);
        vm.expectRevert(InvoicePayments.NotPayer.selector);
        inv.payInvoice(id);
    }

    function testPayRevertsAlreadyPaid() public {
        uint256 id = _createInvoice();
        vm.prank(payer);
        inv.payInvoice(id);
        vm.prank(payer);
        vm.expectRevert(InvoicePayments.InvoiceNotPending.selector);
        inv.payInvoice(id);
    }

    function testPayRevertsNonexistent() public {
        vm.prank(payer);
        vm.expectRevert(InvoicePayments.InvoiceNotFound.selector);
        inv.payInvoice(999);
    }

    function testPayRevertsWithoutAllowance() public {
        address poor = makeAddr("poor");
        token.mint(poor, AMOUNT);
        vm.prank(payee);
        uint256 id = inv.createInvoice(poor, AMOUNT, 0, "No approval");
        vm.prank(poor);
        vm.expectRevert();
        inv.payInvoice(id);
        assertEq(uint256(inv.getInvoice(id).status), uint256(InvoicePayments.Status.Pending));
    }

    function testPayRevertsInsufficientBalance() public {
        address poor = makeAddr("poor2");
        token.mint(poor, AMOUNT - 1);
        vm.prank(poor);
        token.approve(address(inv), type(uint256).max);
        vm.prank(payee);
        uint256 id = inv.createInvoice(poor, AMOUNT, 0, "Too big");
        vm.prank(poor);
        vm.expectRevert();
        inv.payInvoice(id);
    }

    function testPayOverdueInvoiceStillWorks() public {
        vm.prank(payee);
        uint256 id = inv.createInvoice(payer, AMOUNT, block.timestamp + 1 days, "Due soon");
        vm.warp(block.timestamp + 2 days);
        assertTrue(inv.isOverdue(id));
        vm.prank(payer);
        inv.payInvoice(id); // late payment is allowed
        assertEq(uint256(inv.getInvoice(id).status), uint256(InvoicePayments.Status.Paid));
    }

    // ---- cancelInvoice ----

    function testCancelInvoice() public {
        uint256 id = _createInvoice();
        vm.prank(payee);
        vm.expectEmit(true, true, false, true, address(inv));
        emit InvoiceCancelled(id, payee);
        inv.cancelInvoice(id);
        assertEq(uint256(inv.getInvoice(id).status), uint256(InvoicePayments.Status.Cancelled));
    }

    function testCancelRevertsNotPayee() public {
        uint256 id = _createInvoice();
        vm.prank(stranger);
        vm.expectRevert(InvoicePayments.NotPayee.selector);
        inv.cancelInvoice(id);
    }

    function testCancelRevertsAlreadyPaid() public {
        uint256 id = _createInvoice();
        vm.prank(payer);
        inv.payInvoice(id);
        vm.prank(payee);
        vm.expectRevert(InvoicePayments.InvoiceNotPending.selector);
        inv.cancelInvoice(id);
    }

    function testCannotPayCancelledInvoice() public {
        uint256 id = _createInvoice();
        vm.prank(payee);
        inv.cancelInvoice(id);
        vm.prank(payer);
        vm.expectRevert(InvoicePayments.InvoiceNotPending.selector);
        inv.payInvoice(id);
    }

    // ---- views ----

    function testIsOverdue() public {
        vm.prank(payee);
        uint256 id = inv.createInvoice(payer, AMOUNT, block.timestamp + 1 days, "Due");
        assertFalse(inv.isOverdue(id));
        vm.warp(block.timestamp + 1 days + 1);
        assertTrue(inv.isOverdue(id));
        vm.prank(payer);
        inv.payInvoice(id);
        assertFalse(inv.isOverdue(id)); // paid invoices are never overdue
    }

    function testIsOverdueNoDueDate() public {
        vm.prank(payee);
        uint256 id = inv.createInvoice(payer, AMOUNT, 0, "No due date");
        vm.warp(block.timestamp + 365 days);
        assertFalse(inv.isOverdue(id));
    }

    function testGetInvoicesPagination() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(payee);
            inv.createInvoice(payer, AMOUNT + i, 0, "inv");
        }
        InvoicePayments.Invoice[] memory page = inv.getInvoices(1, 2);
        assertEq(page.length, 2);
        assertEq(page[0].id, 1);
        assertEq(page[1].id, 2);
        assertEq(page[1].amount, AMOUNT + 2);

        InvoicePayments.Invoice[] memory tail = inv.getInvoices(4, 10);
        assertEq(tail.length, 1);
        assertEq(tail[0].id, 4);

        InvoicePayments.Invoice[] memory empty = inv.getInvoices(5, 10);
        assertEq(empty.length, 0);
    }

    function testGetInvoiceRevertsNonexistent() public {
        vm.expectRevert(InvoicePayments.InvoiceNotFound.selector);
        inv.getInvoice(42);
    }

    // ---- reentrancy ----

    function testReentrancyCannotDoublePay() public {
        ReentrantToken evil = new ReentrantToken();
        InvoicePayments evilInv = new InvoicePayments(address(evil));
        evil.mint(payer, 1_000_000_000);
        vm.prank(payer);
        evil.approve(address(evilInv), type(uint256).max);

        vm.prank(payee);
        uint256 id = evilInv.createInvoice(payer, AMOUNT, 0, "Reentrancy bait");
        evil.arm(address(evilInv), id);

        // The attack reverts (guard + CEI), the invoice stays Pending,
        // and no tokens move.
        vm.prank(payer);
        vm.expectRevert();
        evilInv.payInvoice(id);
        assertEq(uint256(evilInv.getInvoice(id).status), uint256(InvoicePayments.Status.Pending));
        assertEq(evil.balanceOf(payee), 0);
        assertEq(evil.balanceOf(payer), 1_000_000_000);
    }
}
