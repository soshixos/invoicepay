// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title InvoicePayments — pay invoices in a stablecoin on Aevum Testnet
/// @notice A minimal, auditable invoice-payment flow for the QDay Aevum
///         Builder Challenge #1 (Invoice Payments track).
///         A biller creates an invoice denominated in tUSD8 (or any ERC-20);
///         the designated payer — or anyone, for an open invoice — pays it
///         by approving the contract, which moves the tokens payer -> payee
///         and marks the invoice Paid. No admin, no upgradeability, no
///         backdoors: the contract can only move tokens that a payer has
///         explicitly approved, and only to settle an invoice they owe.
/// @dev    Safety properties:
///         - ReentrancyGuard + checks-effects-interactions on payInvoice.
///         - SafeERC20 for all token movements (handles non-standard ERC-20s).
///         - Funds can only flow payer -> payee of a Pending invoice.
///         - The payee is always the invoice creator (msg.sender); nobody
///           can create an invoice that pays a third party.
///         - Overdue is informational only: an overdue invoice can still be
///           paid (late payment), it just displays as Overdue.
contract InvoicePayments is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The stablecoin invoices are settled in (tUSD8 on Aevum Testnet).
    IERC20 public immutable token;

    enum Status {
        Pending,
        Paid,
        Cancelled
    }

    struct Invoice {
        uint256 id;
        address payee; // invoice creator; receives the payment
        address payer; // who must pay; address(0) = anyone may pay (open invoice)
        uint256 amount; // in token base units (tUSD8 has 6 decimals)
        uint256 dueDate; // unix timestamp; 0 = no due date
        string memo; // description of what the invoice is for
        Status status;
        uint256 createdAt;
        uint256 paidAt; // 0 until paid
        address paidBy; // address(0) until paid
    }

    /// @notice Max memo length, to keep invoices readable and bound gas.
    uint256 public constant MAX_MEMO_LENGTH = 500;

    uint256 public nextInvoiceId;
    mapping(uint256 => Invoice) private _invoices;

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

    error ZeroAmount();
    error DueDateInPast();
    error MemoTooLong();
    error InvoiceNotFound();
    error InvoiceNotPending();
    error NotPayer();
    error NotPayee();

    constructor(address token_) {
        require(token_ != address(0), "token is zero address");
        token = IERC20(token_);
    }

    /// @notice Create an invoice payable to the caller.
    /// @param payer The address that must pay, or address(0) for an open
    ///        invoice that anyone may pay.
    /// @param amount Amount in token base units; must be > 0.
    /// @param dueDate Unix timestamp the invoice is due, or 0 for no due date.
    ///        A non-zero due date must be in the future.
    /// @param memo Human-readable description (max 500 bytes).
    /// @return id The new invoice id.
    function createInvoice(
        address payer,
        uint256 amount,
        uint256 dueDate,
        string calldata memo
    ) external returns (uint256 id) {
        if (amount == 0) revert ZeroAmount();
        if (dueDate != 0 && dueDate <= block.timestamp) revert DueDateInPast();
        if (bytes(memo).length > MAX_MEMO_LENGTH) revert MemoTooLong();

        id = nextInvoiceId++;
        _invoices[id] = Invoice({
            id: id,
            payee: msg.sender,
            payer: payer,
            amount: amount,
            dueDate: dueDate,
            memo: memo,
            status: Status.Pending,
            createdAt: block.timestamp,
            paidAt: 0,
            paidBy: address(0)
        });

        emit InvoiceCreated(id, msg.sender, payer, amount, dueDate, memo);
    }

    /// @notice Pay a Pending invoice. The caller must have approved this
    ///         contract for at least `amount` of the token first.
    ///         Moves `amount` from the payer to the payee and marks Paid.
    /// @param id The invoice id.
    function payInvoice(uint256 id) external nonReentrant {
        Invoice storage inv = _invoices[id];
        if (inv.payee == address(0)) revert InvoiceNotFound();
        if (inv.status != Status.Pending) revert InvoiceNotPending();
        if (inv.payer != address(0) && msg.sender != inv.payer) revert NotPayer();

        // Effects before interactions.
        inv.status = Status.Paid;
        inv.paidAt = block.timestamp;
        inv.paidBy = msg.sender;

        token.safeTransferFrom(msg.sender, inv.payee, inv.amount);

        emit InvoicePaid(id, msg.sender, inv.amount, block.timestamp);
    }

    /// @notice Cancel a Pending invoice. Only the payee (creator) may cancel.
    /// @param id The invoice id.
    function cancelInvoice(uint256 id) external {
        Invoice storage inv = _invoices[id];
        if (inv.payee == address(0)) revert InvoiceNotFound();
        if (inv.status != Status.Pending) revert InvoiceNotPending();
        if (msg.sender != inv.payee) revert NotPayee();

        inv.status = Status.Cancelled;

        emit InvoiceCancelled(id, msg.sender);
    }

    /// @notice Fetch a single invoice. Reverts if the id does not exist.
    function getInvoice(uint256 id) external view returns (Invoice memory) {
        Invoice memory inv = _invoices[id];
        if (inv.payee == address(0)) revert InvoiceNotFound();
        return inv;
    }

    /// @notice Total number of invoices ever created.
    function invoiceCount() external view returns (uint256) {
        return nextInvoiceId;
    }

    /// @notice Fetch a page of invoices, newest last. Returns fewer than
    ///         `limit` entries when the end is reached.
    function getInvoices(uint256 offset, uint256 limit) external view returns (Invoice[] memory) {
        uint256 total = nextInvoiceId;
        if (offset >= total) return new Invoice[](0);
        uint256 end = offset + limit > total ? total : offset + limit;
        Invoice[] memory page = new Invoice[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = _invoices[i];
        }
        return page;
    }

    /// @notice True when a Pending invoice has passed its due date.
    ///         dueDate == 0 means no due date, never overdue.
    function isOverdue(uint256 id) external view returns (bool) {
        Invoice memory inv = _invoices[id];
        if (inv.payee == address(0)) revert InvoiceNotFound();
        return inv.status == Status.Pending && inv.dueDate != 0 && block.timestamp > inv.dueDate;
    }
}
