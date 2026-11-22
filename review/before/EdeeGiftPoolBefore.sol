// SPDX-License-Identifier: LicenseRef-AllRightsReserved
// REVIEW SAMPLE: the "before" version, as a client might send it in for checking.
// It contains deliberate mistakes. Do NOT deploy. See REVIEW-REPORT.md for the findings and the fixed version.
pragma solidity ^0.8.0;

contract EdeeGiftPoolBefore {
    address public organiser;
    address payable public recipient;
    uint256 public goal;
    uint256 public deadline;
    bool public released;

    uint256 public totalRaised;
    mapping(address => uint256) public contributionOf;

    constructor(address payable _recipient, uint256 _goal, uint256 _deadline) {
        organiser = msg.sender;
        recipient = _recipient;
        goal = _goal;
        deadline = _deadline;
    }

    function contribute() external payable {
        require(!released, "already released");
        contributionOf[msg.sender] += msg.value;
        totalRaised += msg.value;
    }

    function release() external {
        require(tx.origin == organiser, "only organiser");
        require(totalRaised >= goal, "goal not reached");
        require(!released, "already released");
        released = true;
        recipient.transfer(address(this).balance);
    }

    function refund() external {
        require(block.timestamp > deadline, "too early");
        require(!released, "already released");
        uint256 amount = contributionOf[msg.sender];
        require(amount > 0, "nothing to refund");
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "refund failed");
        contributionOf[msg.sender] = 0;
    }
}
