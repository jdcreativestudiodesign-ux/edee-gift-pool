// SPDX-License-Identifier: LicenseRef-AllRightsReserved
// Portfolio sample by jdcreative.studiodesign.
pragma solidity 0.8.39;

/// @title BusinessDays
/// @author jdcreative.studiodesign
/// @notice Counts weekdays (Monday to Friday) in UTC. Blockchains don't know public holidays,
///         so those count as normal weekdays.
library BusinessDays {
    uint256 internal constant DAY = 1 days;

    /// @notice Day of the week for a timestamp, in UTC. 0 = Monday ... 6 = Sunday.
    /// @dev 1 January 1970 (day 0 of Unix time) was a Thursday, which is 3 when Monday is 0.
    /// @param timestamp Unix time in seconds.
    /// @return The weekday, 0 (Monday) to 6 (Sunday).
    function dayOfWeek(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / DAY + 3) % 7;
    }

    /// @notice The same time of day, `count` weekdays after `timestamp`. Saturdays and Sundays are skipped.
    /// @dev Steps one day at a time; `count` is a small constant in practice (5), so the loop is bounded.
    /// @param timestamp Unix time in seconds to count from.
    /// @param count How many weekdays to add.
    /// @return result The resulting Unix time.
    function addWeekdays(uint256 timestamp, uint256 count) internal pure returns (uint256 result) {
        result = timestamp;
        while (count > 0) {
            result += DAY;
            if (dayOfWeek(result) < 5) {
                --count;
            }
        }
    }
}
