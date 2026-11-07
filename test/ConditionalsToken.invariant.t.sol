// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsToken} from "../src/ConditionalsToken.sol";

/// @notice Drives the token with random sequences of transfers, approvals and pulls among a fixed set
///         of actors, and keeps an independent model of every balance and allowance. Calls that must
///         fail are driven too, and the handler checks that each reverts with the expected error and
///         changes nothing.
contract ConditionalsHandler is Test {
    ConditionalsToken public immutable token;
    address[] public actors;

    // Independent model: what each balance and allowance must be after every call.
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostTransferredOut; // sum of all successful amounts moved between distinct accounts
    uint256 public successfulCalls;
    uint256 public expectedReverts;
    uint256 public unexpectedOutcomes; // must stay zero

    constructor(ConditionalsToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            ghostBalance[actors_[i]] = token_.balanceOf(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // ------------------------------------------------------------------ success-or-model paths

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        bool ok = token.transfer(to, amount);
        if (!ok) unexpectedOutcomes++;

        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        if (from != to) ghostTransferredOut += amount;
        successfulCalls++;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (infinite) amount = type(uint256).max;

        vm.prank(owner);
        bool ok = token.approve(spender, amount);
        if (!ok) unexpectedOutcomes++;

        ghostAllowance[owner][spender] = amount; // approve overwrites, it does not add
        successfulCalls++;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = allowed < ghostBalance[from] ? allowed : ghostBalance[from];
        amount = bound(amount, 0, cap);

        vm.prank(spender);
        bool ok = token.transferFrom(from, to, amount);
        if (!ok) unexpectedOutcomes++;

        if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        if (from != to) ghostTransferredOut += amount;
        successfulCalls++;
    }

    // ------------------------------------------------------------------ paths that must fail

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);

        vm.prank(from);
        try token.transfer(to, amount) {
            unexpectedOutcomes++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount)
                    )
            ) unexpectedOutcomes++;
        }
        expectedReverts++;
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        try token.transfer(address(0), amount) {
            unexpectedOutcomes++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)))
            ) {
                unexpectedOutcomes++;
            }
        }
        expectedReverts++;
    }

    function transferFromAboveAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess)
        external
    {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed == type(uint256).max) return; // an infinite allowance cannot be exceeded
        uint256 amount = allowed + bound(excess, 1, type(uint256).max - allowed);

        vm.prank(spender);
        try token.transferFrom(from, to, amount) {
            unexpectedOutcomes++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(
                            IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount
                        )
                    )
            ) unexpectedOutcomes++;
        }
        expectedReverts++;
    }

    function transferFromAboveBalance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed <= held) return; // the allowance check would fire first; covered above
        uint256 amount = held + bound(excess, 1, allowed - held);

        vm.prank(spender);
        try token.transferFrom(from, to, amount) {
            unexpectedOutcomes++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount)
                    )
            ) unexpectedOutcomes++;
        }
        expectedReverts++;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.prank(owner);
        try token.approve(address(0), amount) {
            unexpectedOutcomes++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)))
            ) {
                unexpectedOutcomes++;
            }
        }
        expectedReverts++;
    }

    function sendEther(uint256 fromSeed, uint256 value) external {
        address from = _actor(fromSeed);
        value = bound(value, 1, 100 ether);
        vm.deal(from, value);
        vm.prank(from);
        (bool ok,) = address(token).call{value: value}("");
        if (ok) unexpectedOutcomes++;
        expectedReverts++;
    }
}

contract ConditionalsTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal constant DEPLOYER = address(0xFAC7);

    ConditionalsToken internal token;
    ConditionalsHandler internal handler;
    address[] internal actors;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new ConditionalsToken();

        actors.push(DEPLOYER);
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA201));
        actors.push(address(0xD157)); // distributor stand-in
        actors.push(address(0x612a9bB008e16ef2D24f41DAe9Fc661831d93367)); // remainderTo

        handler = new ConditionalsHandler(token, actors);
        targetContract(address(handler));
        excludeSender(address(0));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY, "total supply changed");
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_actorBalancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY, "balances among the only possible holders do not sum to the supply");
        assertEq(token.balanceOf(address(0)), 0, "the zero address holds tokens");
        assertEq(token.balanceOf(address(handler)), 0, "a non-actor received tokens");
        assertEq(token.balanceOf(address(token)), 0, "the token holds itself");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]), "balance diverged from model");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.ghostAllowance(actors[i], actors[j]),
                    "allowance diverged from model"
                );
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_failurePathsFailCleanly() public view {
        assertEq(handler.unexpectedOutcomes(), 0, "a call succeeded that must fail, or failed with the wrong error");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_tokenNeverHoldsEther() public view {
        assertEq(address(token).balance, 0, "the token holds ether");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_metadataNeverChanges() public view {
        assertEq(token.name(), "Conditionals");
        assertEq(token.symbol(), "COND");
        assertEq(token.decimals(), 18);
    }
}
