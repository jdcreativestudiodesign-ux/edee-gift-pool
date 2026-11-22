// SPDX-License-Identifier: LicenseRef-AllRightsReserved
pragma solidity 0.8.39;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EdeeGiftPool} from "../src/EdeeGiftPool.sol";
import {
    MockStablecoin,
    FeeOnTransferToken,
    HollowToken,
    SmartWallet,
    RejectingWallet
} from "./mocks/Mocks.sol";

/// @notice Every rule, tested once and run twice: with ETH (EdeeGiftPoolEthTest) and with a stablecoin
///         (EdeeGiftPoolTokenTest). Dates are real: "now" is Tue 1 Dec 2026 00:00 UTC, the closing date is
///         Fri 4 Dec 17:00 UTC, so the safety net opens 5 weekdays later, Fri 11 Dec 17:00 UTC.
abstract contract EdeeGiftPoolTestBase is Test {
    uint256 internal constant START = 1796083200; // Tue 1 Dec 2026 00:00 UTC
    uint256 internal constant DEADLINE = 1796403600; // Fri 4 Dec 2026 17:00 UTC
    uint256 internal constant SAFETY_NET = 1797008400; // Fri 11 Dec 2026 17:00 UTC (computed independently)

    address internal organiser = makeAddr("organiser");
    address internal recipient = makeAddr("recipient");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal stranger = makeAddr("stranger");

    EdeeGiftPool internal gift;

    // ---- per-currency hooks -------------------------------------------------------------------------
    function _token() internal view virtual returns (IERC20);
    function _unit() internal view virtual returns (uint256); // 1 ETH or 1 dollar
    function _fund(address who, uint256 amount) internal virtual; // give `who` money and approve if needed
    function _balance(address who) internal view virtual returns (uint256);
    function _contributeCall(address who, uint256 amount) internal virtual; // the raw call, no funding

    function _goal() internal view returns (uint256) {
        return 300 * _unit();
    }

    function setUp() public virtual {
        vm.warp(START);
        gift = _deploy(recipient);
    }

    function _deploy(address to) internal returns (EdeeGiftPool g) {
        vm.prank(organiser);
        g = new EdeeGiftPool(to, _goal(), DEADLINE, _token());
    }

    function _pay(address who, uint256 amount) internal {
        _fund(who, amount);
        _contributeCall(who, amount);
    }

    function _reachGoal() internal {
        _pay(alice, 100 * _unit());
        _pay(bob, 150 * _unit());
        _pay(carol, 50 * _unit());
    }

    // ---- setup --------------------------------------------------------------------------------------
    function test_setup_storesTheRules() public view {
        assertEq(gift.ORGANISER(), organiser);
        assertEq(gift.RECIPIENT(), recipient);
        assertEq(address(gift.TOKEN()), address(_token()));
        assertEq(gift.GOAL(), _goal());
        assertEq(gift.DEADLINE(), DEADLINE);
        assertEq(gift.SAFETY_NET_AT(), SAFETY_NET);
        assertEq(gift.SAFETY_NET_BUSINESS_DAYS(), 5);
        assertEq(uint256(gift.status()), uint256(EdeeGiftPool.Status.Open));
    }

    function test_setup_rejectsBadSettings() public {
        vm.expectRevert(EdeeGiftPool.InvalidSetup.selector);
        new EdeeGiftPool(address(0), _goal(), DEADLINE, _token());
        vm.expectRevert(EdeeGiftPool.InvalidSetup.selector);
        new EdeeGiftPool(recipient, 0, DEADLINE, _token());
        vm.expectRevert(EdeeGiftPool.InvalidSetup.selector);
        new EdeeGiftPool(recipient, _goal(), START, _token()); // closing date must be in the future
    }

    // ---- contribute ---------------------------------------------------------------------------------
    function test_contribute_recordsEachPersonAndTheTotal() public {
        _fund(alice, 40 * _unit());
        vm.expectEmit(address(gift));
        emit EdeeGiftPool.Contributed(alice, 40 * _unit(), 40 * _unit());
        _contributeCall(alice, 40 * _unit());
        _pay(alice, 10 * _unit());
        _pay(bob, 25 * _unit());

        assertEq(gift.contributionOf(alice), 50 * _unit());
        assertEq(gift.contributionOf(bob), 25 * _unit());
        assertEq(gift.totalRaised(), 75 * _unit());
        assertEq(_balance(address(gift)), 75 * _unit());
    }

    function test_contribute_overTheGoalIsAllowedUntilTheClosingDate() public {
        _reachGoal();
        _pay(stranger, 20 * _unit());
        assertEq(gift.totalRaised(), 320 * _unit());
    }

    function test_contribute_refusesZero() public {
        vm.expectRevert(EdeeGiftPool.ZeroAmount.selector);
        _contributeCall(alice, 0);
    }

    function test_contribute_closesExactlyAtTheClosingDate() public {
        _fund(alice, _unit());
        vm.warp(DEADLINE - 1);
        _contributeCall(alice, _unit() / 2);
        vm.warp(DEADLINE);
        vm.expectRevert(EdeeGiftPool.DeadlinePassed.selector);
        _contributeCall(alice, _unit() / 2);
    }

    function test_contribute_refusedAfterReleaseOrCancel() public {
        _reachGoal();
        vm.prank(organiser);
        gift.release();
        _fund(alice, _unit());
        vm.expectRevert(EdeeGiftPool.NotOpen.selector);
        _contributeCall(alice, _unit());

        EdeeGiftPool other = _deploy(recipient);
        vm.prank(organiser);
        other.cancel();
        gift = other;
        _fund(bob, _unit());
        vm.expectRevert(EdeeGiftPool.NotOpen.selector);
        _contributeCall(bob, _unit());
    }

    // ---- release ------------------------------------------------------------------------------------
    function test_release_organiserSendsEverythingOnceGoalIsMet() public {
        _reachGoal();
        _pay(stranger, 7 * _unit()); // extra goes to the gift too
        vm.expectEmit(address(gift));
        emit EdeeGiftPool.Released(recipient, 307 * _unit());
        vm.prank(organiser);
        gift.release();

        assertEq(_balance(recipient), 307 * _unit());
        assertEq(_balance(address(gift)), 0);
        assertEq(uint256(gift.status()), uint256(EdeeGiftPool.Status.Released));
    }

    function test_release_onlyOrganiserBeforeTheClosingDate() public {
        _reachGoal();
        vm.prank(stranger);
        vm.expectRevert(EdeeGiftPool.NotOrganiser.selector);
        gift.release();
    }

    function test_release_anyoneAfterTheClosingDate_soGiftCantGetStuck() public {
        _reachGoal();
        vm.warp(DEADLINE);
        vm.prank(stranger);
        gift.release();
        assertEq(_balance(recipient), 300 * _unit());
    }

    function test_release_refusedBelowGoal() public {
        _pay(alice, 299 * _unit());
        vm.prank(organiser);
        vm.expectRevert(EdeeGiftPool.GoalNotReached.selector);
        gift.release();
    }

    function test_release_onlyOnce_andNotAfterCancel() public {
        _reachGoal();
        vm.startPrank(organiser);
        gift.release();
        vm.expectRevert(EdeeGiftPool.NotOpen.selector);
        gift.release();
        vm.stopPrank();

        gift = _deploy(recipient);
        _reachGoal();
        vm.startPrank(organiser);
        gift.cancel();
        vm.expectRevert(EdeeGiftPool.NotOpen.selector);
        gift.release();
        vm.stopPrank();
    }

    function test_release_closesWhenTheSafetyNetOpens() public {
        _reachGoal();
        vm.warp(SAFETY_NET - 1);
        assertFalse(gift.refundsOpen());
        vm.warp(SAFETY_NET);
        vm.prank(organiser);
        vm.expectRevert(EdeeGiftPool.SafetyNetOpen.selector);
        gift.release();
    }

    // ---- cancel -------------------------------------------------------------------------------------
    function test_cancel_everyoneGetsTheirOwnMoneyBack_evenAfterGoalMet() public {
        _reachGoal();
        vm.expectEmit(address(gift));
        emit EdeeGiftPool.Cancelled();
        vm.prank(organiser);
        gift.cancel();
        assertTrue(gift.refundsOpen());

        _refund(alice);
        _refund(bob);
        _refund(carol);
        assertEq(_balance(alice), 100 * _unit());
        assertEq(_balance(bob), 150 * _unit());
        assertEq(_balance(carol), 50 * _unit());
        assertEq(_balance(address(gift)), 0);
        assertEq(_balance(organiser), 0, "the organiser gets nothing");
    }

    function test_cancel_onlyOrganiser_onlyWhileOpen() public {
        vm.prank(stranger);
        vm.expectRevert(EdeeGiftPool.NotOrganiser.selector);
        gift.cancel();

        vm.startPrank(organiser);
        gift.cancel();
        vm.expectRevert(EdeeGiftPool.NotOpen.selector);
        gift.cancel();
        vm.stopPrank();
    }

    // ---- refunds ------------------------------------------------------------------------------------
    function test_refund_whenGoalMissed_opensExactlyAtTheClosingDate() public {
        _pay(alice, 120 * _unit());
        _pay(bob, 30 * _unit());

        vm.warp(DEADLINE - 1);
        assertFalse(gift.refundsOpen());
        vm.prank(alice);
        vm.expectRevert(EdeeGiftPool.RefundsNotAvailable.selector);
        gift.refund();

        vm.warp(DEADLINE);
        assertTrue(gift.refundsOpen());
        vm.expectEmit(address(gift));
        emit EdeeGiftPool.Refunded(alice, 120 * _unit());
        _refund(alice);
        assertEq(_balance(alice), 120 * _unit());
        assertEq(gift.contributionOf(alice), 0);
        assertEq(_balance(address(gift)), 30 * _unit(), "bob's share is untouched");
    }

    function test_refund_onlyOnce_andOnlyYourOwn() public {
        _pay(alice, 10 * _unit());
        vm.warp(DEADLINE);
        _refund(alice);
        vm.prank(alice);
        vm.expectRevert(EdeeGiftPool.NothingToRefund.selector);
        gift.refund();
        vm.prank(stranger);
        vm.expectRevert(EdeeGiftPool.NothingToRefund.selector);
        gift.refund();
    }

    function test_refund_closedWhileGoalMetAndBeforeSafetyNet() public {
        _reachGoal();
        vm.warp(DEADLINE + 2 days);
        vm.prank(alice);
        vm.expectRevert(EdeeGiftPool.RefundsNotAvailable.selector);
        gift.refund();
    }

    function test_safetyNet_refundsOpenFiveBusinessDaysAfterClosing() public {
        _reachGoal(); // goal met, but nobody releases it
        vm.warp(SAFETY_NET);
        assertTrue(gift.refundsOpen());
        _refund(alice);
        _refund(bob);
        _refund(carol);
        assertEq(_balance(alice) + _balance(bob) + _balance(carol), 300 * _unit());
        assertEq(_balance(recipient), 0);
    }

    function test_refund_closedAfterRelease() public {
        _reachGoal();
        vm.prank(organiser);
        gift.release();
        vm.warp(SAFETY_NET + 30 days);
        assertFalse(gift.refundsOpen());
        vm.prank(alice);
        vm.expectRevert(EdeeGiftPool.RefundsNotAvailable.selector);
        gift.refund();
    }

    /// @notice Whatever people pay in, cancelling returns exactly what each person paid, and nothing is left.
    function testFuzz_cancel_returnsExactlyWhatEachPersonPaid(uint96 a, uint96 b, uint96 c) public {
        uint256 amountA = bound(a, 1, 1_000_000 * _unit());
        uint256 amountB = bound(b, 1, 1_000_000 * _unit());
        uint256 amountC = bound(c, 1, 1_000_000 * _unit());
        _pay(alice, amountA);
        _pay(bob, amountB);
        _pay(carol, amountC);
        vm.prank(organiser);
        gift.cancel();
        _refund(alice);
        _refund(bob);
        _refund(carol);
        assertEq(_balance(alice), amountA);
        assertEq(_balance(bob), amountB);
        assertEq(_balance(carol), amountC);
        assertEq(_balance(address(gift)), 0);
    }

    function _refund(address who) internal {
        vm.prank(who);
        gift.refund();
    }
}

contract EdeeGiftPoolEthTest is EdeeGiftPoolTestBase {
    function _token() internal pure override returns (IERC20) {
        return IERC20(address(0));
    }

    function _unit() internal pure override returns (uint256) {
        return 1 ether;
    }

    function _fund(address who, uint256 amount) internal override {
        vm.deal(who, who.balance + amount);
    }

    function _balance(address who) internal view override returns (uint256) {
        return who.balance;
    }

    function _contributeCall(address who, uint256 amount) internal override {
        vm.prank(who);
        gift.contribute{value: amount}(amount);
    }

    function test_eth_paymentMustMatchTheAmount() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert(EdeeGiftPool.WrongPayment.selector);
        gift.contribute{value: 1 ether}(2 ether);
    }

    function test_eth_plainTransfersAreRefused_useContribute() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(gift).call{value: 1 ether}("");
        assertFalse(ok);
    }

    function test_eth_smartContractWalletCanReceiveTheGift() public {
        SmartWallet safe = new SmartWallet();
        gift = _deploy(address(safe));
        _reachGoal();
        vm.prank(organiser);
        gift.release();
        assertEq(safe.received(), 300 ether);
    }

    function test_eth_ifRecipientRefusesPayment_safetyNetReturnsTheMoney() public {
        gift = _deploy(address(new RejectingWallet()));
        _reachGoal();
        vm.prank(organiser);
        vm.expectRevert(EdeeGiftPool.TransferFailed.selector);
        gift.release();
        vm.warp(SAFETY_NET);
        _refund(alice);
        assertEq(alice.balance, 100 ether);
    }
}

contract EdeeGiftPoolTokenTest is EdeeGiftPoolTestBase {
    MockStablecoin internal usd;

    function setUp() public override {
        usd = new MockStablecoin();
        super.setUp();
    }

    function _token() internal view override returns (IERC20) {
        return IERC20(address(usd));
    }

    function _unit() internal pure override returns (uint256) {
        return 1e6; // 1 dollar, 6 decimals
    }

    function _fund(address who, uint256 amount) internal override {
        usd.mint(who, amount);
        vm.prank(who);
        usd.approve(address(gift), type(uint256).max);
    }

    function _balance(address who) internal view override returns (uint256) {
        return usd.balanceOf(who);
    }

    function _contributeCall(address who, uint256 amount) internal override {
        vm.prank(who);
        gift.contribute(amount);
    }

    function test_token_sendingEthToo_isRefused() public {
        _fund(alice, 10e6);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(EdeeGiftPool.WrongPayment.selector);
        gift.contribute{value: 1}(10e6);
    }

    function test_token_mustBeARealTokenContract() public {
        vm.expectRevert(EdeeGiftPool.InvalidSetup.selector);
        new EdeeGiftPool(recipient, _goal(), DEADLINE, IERC20(makeAddr("not-a-contract")));
    }

    function test_token_withoutApproval_isRefused() public {
        usd.mint(alice, 10e6); // no approve
        vm.prank(alice);
        vm.expectRevert(); // the token itself refuses the transfer
        gift.contribute(10e6);
        assertEq(gift.totalRaised(), 0);
    }

    function test_token_thatDeliversNothing_isRefused() public {
        HollowToken hollow = new HollowToken();
        vm.prank(organiser);
        EdeeGiftPool hollowGift = new EdeeGiftPool(recipient, 300e6, DEADLINE, IERC20(address(hollow)));
        vm.prank(alice);
        vm.expectRevert(EdeeGiftPool.ZeroAmount.selector);
        hollowGift.contribute(50e6);
        assertEq(hollowGift.totalRaised(), 0, "nothing credited for nothing received");
    }

    function test_token_feeOnTransfer_countsOnlyWhatArrives() public {
        FeeOnTransferToken fee = new FeeOnTransferToken();
        vm.prank(organiser);
        EdeeGiftPool feeGift = new EdeeGiftPool(recipient, 300e6, DEADLINE, IERC20(address(fee)));
        fee.mint(alice, 100e6);
        vm.startPrank(alice);
        fee.approve(address(feeGift), 100e6);
        feeGift.contribute(100e6);
        vm.stopPrank();
        assertEq(feeGift.contributionOf(alice), 99e6, "1% fee taken in transit");
        assertEq(feeGift.totalRaised(), fee.balanceOf(address(feeGift)));
    }
}
