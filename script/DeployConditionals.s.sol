// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {ConditionalsToken} from "../src/ConditionalsToken.sol";

/// @title Deploy script for Conditionals (COND)
/// @notice Reviewable reference deployment. The token takes no constructor arguments and has no
///         configuration, so there is nothing to read from the environment: `deploy()` is the whole
///         deployment and tests call it directly. On the IdentityMD launch the ProjectFactory deploys
///         the token from its creation code; this script is for local or independent deployments only.
contract DeployConditionals is Script {
    /// @notice Deploys the token. The caller of this function (the broadcaster) receives the whole supply.
    function deploy() public returns (ConditionalsToken token) {
        token = new ConditionalsToken();
    }

    /// @notice Broadcast entry point: `forge script script/DeployConditionals.s.sol --broadcast`.
    function run() external returns (ConditionalsToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
