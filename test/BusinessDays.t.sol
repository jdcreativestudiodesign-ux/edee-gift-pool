// SPDX-License-Identifier: LicenseRef-AllRightsReserved
pragma solidity 0.8.39;

import {Test} from "forge-std/Test.sol";
import {BusinessDays} from "../src/BusinessDays.sol";

/// @notice Expected values were computed independently with Python's calendar (UTC), not with this library.
contract BusinessDaysTest is Test {
    function test_dayOfWeek_knownDates() public pure {
        assertEq(BusinessDays.dayOfWeek(0), 3, "1 Jan 1970 was a Thursday");
        assertEq(BusinessDays.dayOfWeek(1796083200), 1, "1 Dec 2026 is a Tuesday");
        assertEq(BusinessDays.dayOfWeek(1796403600), 4, "4 Dec 2026 is a Friday");
        assertEq(BusinessDays.dayOfWeek(1796472000), 5, "5 Dec 2026 is a Saturday");
        assertEq(BusinessDays.dayOfWeek(1796558400), 6, "6 Dec 2026 is a Sunday");
        assertEq(BusinessDays.dayOfWeek(1796634000), 0, "7 Dec 2026 is a Monday");
    }

    function test_addFiveWeekdays_knownDates() public pure {
        assertEq(BusinessDays.addWeekdays(1796403600, 5), 1797008400, "Fri 17:00 -> next Fri 17:00");
        assertEq(BusinessDays.addWeekdays(1796472000, 5), 1796990400, "Sat 12:00 -> Fri 12:00");
        assertEq(BusinessDays.addWeekdays(1796558400, 5), 1796990400, "Sun 12:00 -> Fri 12:00");
        assertEq(BusinessDays.addWeekdays(1796634000, 5), 1797238800, "Mon 09:00 -> next Mon 09:00");
        assertEq(BusinessDays.addWeekdays(1798761599, 5), 1799366399, "Thu 31 Dec 23:59:59 -> Thu 7 Jan 2027");
    }

    /// @notice For any start time: the result is the same time of day, on a weekday, 5 to 7 days later,
    ///         and exactly 5 weekdays lie between the two.
    function testFuzz_addFiveWeekdays_properties(uint256 start) public pure {
        start = bound(start, 0, 4_102_444_800); // up to the year 2100
        uint256 result = BusinessDays.addWeekdays(start, 5);
        uint256 daysAdded = (result - start) / 1 days;

        assertEq((result - start) % 1 days, 0, "same time of day");
        assertLt(BusinessDays.dayOfWeek(result), 5, "lands on a weekday");
        assertGe(daysAdded, 5);
        assertLe(daysAdded, 7);

        uint256 weekdays;
        for (uint256 i = 1; i <= daysAdded; i++) {
            if (BusinessDays.dayOfWeek(start + i * 1 days) < 5) weekdays++;
        }
        assertEq(weekdays, 5, "exactly five weekdays counted");
    }
}
