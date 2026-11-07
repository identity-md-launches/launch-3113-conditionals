// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsToken} from "../src/ConditionalsToken.sol";

/// @notice Edge inputs the main suite does not pin: the zero address as caller, self-pulls,
///         approval overwrites, allowance at the boundary, error precedence, and deployments that
///         do not share state.
contract ConditionalsTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    ConditionalsToken internal token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new ConditionalsToken();
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100 ether);
    }

    // ------------------------------------------------------------------ zero address as caller / owner

    function test_transferFromZeroAddressSenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
    }

    function test_approveFromZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(ALICE, 1);
    }

    function test_transferFromZeroAddressOwnerRevertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(0), ALICE, 1);
    }

    function test_transferFromZeroAddressOwnerZeroAmountReverts() public {
        // The zero allowance passes, then spending it tries to write an approval for the zero address.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(address(0), ALICE, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromToZeroAddressReverts() public {
        vm.prank(ALICE);
        token.approve(BOB, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(ALICE, address(0), 1 ether);
        assertEq(token.allowance(ALICE, BOB), 10 ether, "a reverted pull spent allowance");
        assertEq(token.balanceOf(ALICE), 100 ether);
    }

    /// @dev Allowance is checked before the receiver: with neither, the allowance error is reported.
    function test_transferFromErrorPrecedenceAllowanceBeforeReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, address(0), 1);
    }

    // ------------------------------------------------------------------ self pulls and self approvals

    function test_holderNeedsAllowanceToPullFromSelf() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1 ether));
        vm.prank(ALICE);
        token.transferFrom(ALICE, BOB, 1 ether);
    }

    function test_selfApprovalThenSelfPull() public {
        vm.startPrank(ALICE);
        token.approve(ALICE, 3 ether);
        assertTrue(token.transferFrom(ALICE, BOB, 2 ether));
        vm.stopPrank();
        assertEq(token.allowance(ALICE, ALICE), 1 ether);
        assertEq(token.balanceOf(BOB), 2 ether);
        assertEq(token.balanceOf(ALICE), 98 ether);
    }

    function test_transferFromToSameAccountSpendsAllowanceKeepsBalance() public {
        vm.prank(ALICE);
        token.approve(BOB, 10 ether);
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, ALICE, 4 ether));
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.allowance(ALICE, BOB), 6 ether);
    }

    function test_transferToSelfAboveBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 100 ether, 100 ether + 1)
        );
        vm.prank(ALICE);
        token.transfer(ALICE, 100 ether + 1);
    }

    // ------------------------------------------------------------------ approvals

    function test_approveOverwritesRatherThanAdds() public {
        vm.startPrank(ALICE);
        token.approve(BOB, 5 ether);
        token.approve(BOB, 2 ether);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, BOB), 2 ether);
    }

    function test_approveZeroRevokes() public {
        vm.startPrank(ALICE);
        token.approve(BOB, 5 ether);
        token.approve(BOB, 0);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1);
    }

    function test_approveIsDirectional() public {
        vm.prank(ALICE);
        token.approve(BOB, 5 ether);
        assertEq(token.allowance(BOB, ALICE), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(BOB, ALICE, 1);
    }

    function test_approveAboveBalanceIsAllowedButPullIsCappedByBalance() public {
        vm.prank(ALICE);
        token.approve(BOB, SUPPLY);
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 100 ether);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(ALICE, BOB), SUPPLY - 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1);
    }

    function test_allowanceJustBelowInfiniteIsDecremented() public {
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max - 1);
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max - 2);
    }

    function test_exactAllowanceIsFullyConsumed() public {
        vm.prank(ALICE);
        token.approve(BOB, 7 ether);
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 7 ether);
        assertEq(token.allowance(ALICE, BOB), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1);
    }

    function test_transferFromZeroAmountNeedsNoAllowance() public {
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.allowance(ALICE, BOB), 0);
    }

    /// @dev Spending an allowance through transferFrom does not emit Approval (OZ v5 behaviour); only Transfer.
    function test_transferFromEmitsOnlyTransfer() public {
        vm.prank(ALICE);
        token.approve(BOB, 10 ether);
        vm.recordLogs();
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
    }

    // ------------------------------------------------------------------ deployments

    function test_independentDeploymentsDoNotShareState() public {
        vm.prank(BOB);
        ConditionalsToken other = new ConditionalsToken();
        assertEq(other.balanceOf(BOB), SUPPLY);
        assertEq(other.balanceOf(DEPLOYER), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unknownSelectorReverts() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("burn(uint256)", 1 ether));
        assertFalse(ok, "burn exists");
        (ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok, "fallback exists");
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ------------------------------------------------------------------ fuzz

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactValue(address owner, address spender, uint256 first, uint256 second) public {
        owner = address(uint160(bound(uint160(owner), 1, type(uint160).max)));
        spender = address(uint160(bound(uint160(spender), 1, type(uint160).max)));
        vm.startPrank(owner);
        token.approve(spender, first);
        assertEq(token.allowance(owner, spender), first);
        token.approve(spender, second);
        vm.stopPrank();
        assertEq(token.allowance(owner, spender), second);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_failedTransferChangesNothing(uint256 amount) public {
        amount = bound(amount, 100 ether + 1, type(uint256).max);
        vm.prank(ALICE);
        (bool ok,) = address(token).call(abi.encodeCall(IERC20.transfer, (BOB, amount)));
        assertFalse(ok);
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_infiniteAllowanceSurvivesAnyPull(uint256 amount) public {
        amount = bound(amount, 0, 100 ether);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max);
        assertEq(token.balanceOf(BOB), amount);
    }
}
