// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Conditionals (COND)
/// @notice A fixed-supply ERC-20. The whole supply is minted once, in the constructor, to the
///         deployer (`msg.sender`). On the IdentityMD launch the deployer is the ProjectFactory,
///         which pays the supply out to the swarm's distributor, the pool and the requester.
/// @dev Deliberately minimal:
///      - no owner, admin, minter, pauser or blacklist: nobody can move or freeze a holder's balance;
///      - no mint path of any kind after the constructor, so `totalSupply()` can never grow;
///      - no fee, tax, burn-on-transfer or reflection: every transfer delivers exactly `amount`;
///      - no `selfdestruct`, `delegatecall` or upgrade path;
///      - no constructor arguments, so it deploys identically on any chain and the constructor never
///        touches another contract.
///      Transfers follow OpenZeppelin ERC20 v5 semantics: transfers to or from the zero address revert,
///      and `transferFrom` spends the caller's allowance from the `from` account.
contract ConditionalsToken is ERC20 {
    /// @notice ERC-20 name.
    string public constant TOKEN_NAME = "Conditionals";

    /// @notice ERC-20 symbol.
    string public constant TOKEN_SYMBOL = "COND";

    /// @notice ERC-20 decimals. Fixed at 18, matching the launch manifest.
    uint8 public constant TOKEN_DECIMALS = 18;

    /// @notice Total supply in minor units: 1,000,000,000 COND with 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(TOKEN_DECIMALS);

    /// @notice Mints `TOTAL_SUPPLY` once to the deployer. Nothing can mint again.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return TOKEN_DECIMALS;
    }
}
