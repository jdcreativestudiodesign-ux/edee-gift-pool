// SPDX-License-Identifier: LicenseRef-AllRightsReserved
// Portfolio sample by jdcreative.studiodesign. Demo only: deploy to a public testnet, never with real funds.
pragma solidity 0.8.39;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BusinessDays} from "./BusinessDays.sol";

/// @title EdeeGiftPool
/// @author jdcreative.studiodesign
/// @notice Friends chip in towards one gift, in ETH or in a stablecoin such as USDC.
///         - Goal reached: the money goes to the recipient.
///         - Goal missed by the closing date, or the organiser calls it off: everyone takes their own money back.
///         - Safety net: if the goal was met but the gift still hasn't been delivered 5 business days
///           (Monday to Friday, UTC) after the closing date, everyone can take their money back.
///         The money can only ever go to the recipient or back to the people who paid it in.
contract EdeeGiftPool is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Status {
        Open, // taking contributions, or waiting to be released or refunded
        Released, // the money was sent to the recipient
        Cancelled // the organiser called it off; contributors can take their money back
    }

    /// @notice How many business days after the closing date the safety net waits.
    uint256 public constant SAFETY_NET_BUSINESS_DAYS = 5;

    /// @notice Who set the gift up. Can release it early or call it off, but can never take the money.
    address public immutable ORGANISER;
    /// @notice Who receives the gift.
    address public immutable RECIPIENT;
    /// @notice The stablecoin used, or address(0) when the gift is in ETH.
    IERC20 public immutable TOKEN;
    /// @notice Target amount, in wei for ETH or in the token's smallest unit.
    uint256 public immutable GOAL;
    /// @notice Closing date for contributions (Unix time, seconds).
    uint256 public immutable DEADLINE;
    /// @notice When the safety net opens refunds if the gift hasn't been delivered.
    uint256 public immutable SAFETY_NET_AT;

    /// @notice Open, Released or Cancelled.
    Status public status;
    /// @notice Everything paid in so far (refunds don't reduce it).
    uint256 public totalRaised;
    /// @notice What each person has paid in and not yet taken back.
    mapping(address contributor => uint256 amount) public contributionOf;

    /// @notice Someone chipped in.
    /// @param contributor Who paid.
    /// @param amount How much arrived.
    /// @param totalRaised The new total.
    event Contributed(address indexed contributor, uint256 amount, uint256 totalRaised);
    /// @notice The gift was delivered.
    /// @param recipient Who received it.
    /// @param amount How much was sent.
    event Released(address indexed recipient, uint256 amount);
    /// @notice The organiser called the gift off.
    event Cancelled();
    /// @notice Someone took their money back.
    /// @param contributor Who was refunded.
    /// @param amount How much they received.
    event Refunded(address indexed contributor, uint256 amount);

    error InvalidSetup();
    error NotOrganiser();
    error NotOpen();
    error DeadlinePassed();
    error ZeroAmount();
    error WrongPayment();
    error GoalNotReached();
    error SafetyNetOpen();
    error RefundsNotAvailable();
    error NothingToRefund();
    error TransferFailed();

    /// @notice Sets up a new group gift. The caller becomes the organiser.
    /// @param recipient_ Who receives the gift.
    /// @param goal_ Target amount, in wei for ETH or in the token's smallest unit (USDC has 6 decimals).
    /// @param deadline_ Closing date for contributions (Unix time, seconds).
    /// @param token_ Stablecoin address, or address(0) for ETH.
    constructor(address recipient_, uint256 goal_, uint256 deadline_, IERC20 token_) {
        if (recipient_ == address(0) || goal_ == 0 || deadline_ <= block.timestamp) revert InvalidSetup();
        if (address(token_) != address(0) && address(token_).code.length == 0) revert InvalidSetup();
        ORGANISER = msg.sender;
        RECIPIENT = recipient_;
        TOKEN = token_;
        GOAL = goal_;
        DEADLINE = deadline_;
        SAFETY_NET_AT = BusinessDays.addWeekdays(deadline_, SAFETY_NET_BUSINESS_DAYS);
    }

    /// @notice Chip in, until the closing date. For ETH, send exactly `amount` as the transaction value.
    ///         For a stablecoin, approve this contract for `amount` first and send no ETH.
    /// @param amount How much to chip in.
    function contribute(uint256 amount) external payable nonReentrant {
        if (status != Status.Open) revert NotOpen();
        if (block.timestamp >= DEADLINE) revert DeadlinePassed();
        if (amount == 0) revert ZeroAmount();

        uint256 received;
        if (address(TOKEN) == address(0)) {
            if (msg.value != amount) revert WrongPayment();
            received = amount;
        } else {
            if (msg.value != 0) revert WrongPayment();
            // Count what actually arrived, so tokens that take a fee on transfer can't inflate the total.
            uint256 before = TOKEN.balanceOf(address(this));
            TOKEN.safeTransferFrom(msg.sender, address(this), amount);
            received = TOKEN.balanceOf(address(this)) - before;
            if (received == 0) revert ZeroAmount();
        }

        contributionOf[msg.sender] += received;
        totalRaised += received;
        emit Contributed(msg.sender, received, totalRaised);
    }

    /// @notice Send everything raised to the recipient, once the goal is met. Before the closing date only
    ///         the organiser can do this; after it, anyone can, until the safety net opens.
    function release() external nonReentrant {
        if (msg.sender != ORGANISER && block.timestamp < DEADLINE) revert NotOrganiser();
        if (status != Status.Open) revert NotOpen();
        if (totalRaised < GOAL) revert GoalNotReached();
        if (block.timestamp >= SAFETY_NET_AT) revert SafetyNetOpen();

        status = Status.Released; // effects before the transfer (checks-effects-interactions)
        uint256 amount = _balance();
        emit Released(RECIPIENT, amount);
        _send(RECIPIENT, amount);
    }

    /// @notice Call the gift off at any time before it is released. Everyone can then take their money back.
    function cancel() external {
        if (msg.sender != ORGANISER) revert NotOrganiser();
        if (status != Status.Open) revert NotOpen();
        status = Status.Cancelled;
        emit Cancelled();
    }

    /// @notice Take your own contribution back, when refunds are open (see `refundsOpen`).
    /// @dev Pull payment: each person withdraws their own share; the contract never loops over contributors.
    function refund() external nonReentrant {
        if (!refundsOpen()) revert RefundsNotAvailable();
        uint256 amount = contributionOf[msg.sender];
        if (amount == 0) revert NothingToRefund();

        contributionOf[msg.sender] = 0; // zero first, so a re-entering caller finds nothing left
        emit Refunded(msg.sender, amount);
        _send(msg.sender, amount);
    }

    /// @notice True when contributors may take their money back: the gift was called off, the goal was
    ///         missed by the closing date, or the safety net has opened.
    function refundsOpen() public view returns (bool) {
        if (status == Status.Cancelled) return true;
        if (status != Status.Open || block.timestamp < DEADLINE) return false;
        return totalRaised < GOAL || block.timestamp >= SAFETY_NET_AT;
    }

    function _balance() private view returns (uint256) {
        return address(TOKEN) == address(0) ? address(this).balance : TOKEN.balanceOf(address(this));
    }

    /// @dev ETH uses a full-gas call (not `transfer`), so smart-contract wallets such as a Safe can receive it.
    function _send(address to, uint256 amount) private {
        if (address(TOKEN) == address(0)) {
            // Reviewed: `to` is only ever the fixed RECIPIENT, or a contributor taking back their own share.
            // forge-lint: disable-next-line(arbitrary-send-eth)
            (bool ok,) = to.call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            TOKEN.safeTransfer(to, amount);
        }
    }
}
