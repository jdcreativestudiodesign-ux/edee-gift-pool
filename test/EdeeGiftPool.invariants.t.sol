// SPDX-License-Identifier: LicenseRef-AllRightsReserved
pragma solidity 0.8.39;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EdeeGiftPool} from "../src/EdeeGiftPool.sol";
import {MockStablecoin} from "./mocks/Mocks.sol";

/// @notice Drives EdeeGiftPool with random sequences of actions from random people, keeping its own tally.
contract GiftHandler is Test {
    EdeeGiftPool public immutable GIFT;
    MockStablecoin public immutable USD; // unused (address(0)) in ETH mode
    address public immutable ORGANISER;
    address[4] public people;

    uint256 public paidIn;
    uint256 public refunded;
    uint256 public delivered;

    // How often each outcome actually happened, to prove the runs reach every case.
    uint256 public releases;
    uint256 public refundCount;
    uint256 public cancels;

    constructor(EdeeGiftPool gift_, MockStablecoin usd_, address organiser_) {
        GIFT = gift_;
        USD = usd_;
        ORGANISER = organiser_;
        people = [makeAddr("p0"), makeAddr("p1"), makeAddr("p2"), makeAddr("p3")];
    }

    function contribute(uint256 who, uint256 amount) external {
        address p = people[who % people.length];
        // Spread amounts evenly. Foundry's fuzzer favours edge values (0, 1, max), which would make most
        // amounts 1 wei and the goal unreachable; extreme amounts are covered by testFuzz_cancel_* instead.
        amount = bound(uint256(keccak256(abi.encode(amount))), 1, 200 * _unit());
        if (address(USD) == address(0)) {
            vm.deal(p, p.balance + amount);
            vm.prank(p);
            GIFT.contribute{value: amount}(amount);
        } else {
            USD.mint(p, amount);
            vm.startPrank(p);
            USD.approve(address(GIFT), amount);
            GIFT.contribute(amount);
            vm.stopPrank();
        }
        paidIn += amount;
    }

    function refund(uint256 who) external {
        address p = people[who % people.length];
        uint256 owed = GIFT.contributionOf(p);
        vm.prank(p);
        GIFT.refund();
        refunded += owed;
        refundCount++;
    }

    function release(uint256 who, bool asOrganiser) external {
        address caller = asOrganiser ? ORGANISER : people[who % people.length];
        uint256 amount = _balanceOf(address(GIFT));
        vm.prank(caller);
        GIFT.release();
        delivered += amount;
        releases++;
    }

    /// @dev Calling off is rare in real life, so only about 1 in 25 attempts goes ahead. That leaves most
    ///      runs free to reach the goal and exercise delivery and the safety net.
    function cancel(uint256 seed) external {
        if (uint256(keccak256(abi.encode(seed))) % 25 != 0) return; // hashed: the fuzzer often sends 0
        vm.prank(ORGANISER);
        GIFT.cancel();
        cancels++;
    }

    /// @dev Mostly small steps (minutes to hours) so people have time to chip in before the closing date,
    ///      with an occasional jump of days so runs also reach the closing date and the safety net.
    function passTime(uint256 secondsAhead) external {
        uint256 step = secondsAhead % 8 == 0
            ? bound(secondsAhead, 1 days, 4 days)
            : bound(secondsAhead, 10 minutes, 12 hours);
        vm.warp(block.timestamp + step);
    }

    function owedToPeople() external view returns (uint256 total) {
        for (uint256 i; i < people.length; i++) {
            total += GIFT.contributionOf(people[i]);
        }
    }

    function _balanceOf(address a) public view returns (uint256) {
        return address(USD) == address(0) ? a.balance : USD.balanceOf(a);
    }

    function _unit() internal view returns (uint256) {
        return address(USD) == address(0) ? 1 ether : 1e6;
    }
}

abstract contract EdeeGiftPoolInvariantBase is Test {
    EdeeGiftPool internal gift;
    GiftHandler internal handler;
    MockStablecoin internal usd;
    address internal organiser = makeAddr("organiser");
    address internal recipient = makeAddr("recipient");

    function _useToken() internal pure virtual returns (bool);

    function setUp() public {
        vm.warp(1796083200); // Tue 1 Dec 2026 00:00 UTC
        if (_useToken()) usd = new MockStablecoin();
        vm.prank(organiser);
        // uint256(...) matters: a bare `cond ? 1e6 : 1 ether` is typed as a 64-bit number, and 500 ether overflows it.
        uint256 unit = _useToken() ? uint256(1e6) : uint256(1 ether);
        gift = new EdeeGiftPool(recipient, 500 * unit, 1796403600, IERC20(address(usd)));
        handler = new GiftHandler(gift, usd, organiser);
        targetContract(address(handler));
    }

    /// @notice Every unit paid in is still held, refunded, or delivered. Nothing appears or disappears.
    function invariant_moneyIsConserved() public view {
        assertEq(
            handler.paidIn(), handler._balanceOf(address(gift)) + handler.refunded() + handler.delivered()
        );
        assertEq(gift.totalRaised(), handler.paidIn());
    }

    /// @notice Until the gift is delivered, the contract holds exactly what everyone is owed.
    function invariant_heldMoneyMatchesWhatPeopleAreOwed() public view {
        if (gift.status() != EdeeGiftPool.Status.Released) {
            assertEq(handler._balanceOf(address(gift)), handler.owedToPeople());
        }
    }

    /// @notice Delivered means: the goal was met and nobody was ever refunded.
    function invariant_deliveryOnlyWithGoalMet_andNeverWithRefunds() public view {
        if (gift.status() == EdeeGiftPool.Status.Released) {
            assertEq(handler.refunded(), 0);
            assertGe(handler.delivered(), gift.GOAL());
            assertEq(handler._balanceOf(recipient), handler.delivered());
        } else {
            assertEq(handler._balanceOf(recipient), 0);
        }
    }

    /// @notice The organiser never receives any money.
    function invariant_organiserNeverGetsPaid() public view {
        assertEq(handler._balanceOf(organiser), 0);
    }
}

contract EdeeGiftPoolEthInvariants is EdeeGiftPoolInvariantBase {
    function _useToken() internal pure override returns (bool) {
        return false;
    }
}

contract EdeeGiftPoolTokenInvariants is EdeeGiftPoolInvariantBase {
    function _useToken() internal pure override returns (bool) {
        return true;
    }
}
