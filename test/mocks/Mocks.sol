// SPDX-License-Identifier: LicenseRef-AllRightsReserved
pragma solidity 0.8.39;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Test stand-in for a USD stablecoin (6 decimals, like USDC).
contract MockStablecoin is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice A token that keeps 1% of every transfer as a fee, to prove EdeeGiftPool counts what actually arrives.
contract FeeOnTransferToken is ERC20 {
    constructor() ERC20("Fee Token", "FEE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = value / 100;
            super._update(from, address(0xFEE), fee);
            value -= fee;
        }
        super._update(from, to, value);
    }
}

/// @notice Behaves like a smart-contract wallet (e.g. a Safe): receiving ETH costs more than 2,300 gas.
contract SmartWallet {
    uint256 public received;

    receive() external payable {
        received += msg.value; // a storage write: more than the 2,300 gas that `transfer` allows
    }
}

/// @notice A wallet that refuses all ETH, e.g. a contract with no way to receive it.
contract RejectingWallet {
    receive() external payable {
        revert("no thanks");
    }
}

/// @notice A broken token: transferFrom says "success" but moves nothing.
contract HollowToken is ERC20 {
    constructor() ERC20("Hollow", "HOLLOW") {}

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return true;
    }
}
