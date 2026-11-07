// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsToken} from "../src/ConditionalsToken.sol";
import {DeployConditionals} from "../script/DeployConditionals.s.sol";

/// @notice Stands in for the launch factory: deploys the token through CREATE2 and holds the supply.
contract FactoryStub {
    function deploy(bytes memory code, bytes32 salt) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0), "create2 failed");
    }

    function move(IERC20 token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract ConditionalsTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);

    ConditionalsToken internal token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new ConditionalsToken();
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and supply
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "Conditionals");
        assertEq(token.symbol(), "COND");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "Conditionals");
        assertEq(token.TOKEN_SYMBOL(), "COND");
        assertEq(token.TOKEN_DECIMALS(), 18);
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_wholeSupplyMintedToDeployer() public view {
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        ConditionalsToken fresh = new ConditionalsToken();
        assertEq(fresh.balanceOf(ALICE), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    /// @dev The launch deploys through CREATE2 from the factory, so `msg.sender` in the constructor is
    ///      the factory contract, which must then hold the entire supply.
    function test_create2DeploymentFromAContractMintsToThatContract() public {
        FactoryStub factory = new FactoryStub();
        bytes memory code = type(ConditionalsToken).creationCode;
        bytes32 salt = bytes32(uint256(42));
        address predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(code)))))
        );

        address deployed = factory.deploy(code, salt);

        assertEq(deployed, predicted, "CREATE2 address mismatch");
        ConditionalsToken launched = ConditionalsToken(deployed);
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY, "factory does not hold the whole supply");
        assertEq(launched.decimals(), 18);
    }

    function test_deployScriptMintsToTheScriptCaller() public {
        DeployConditionals script = new DeployConditionals();
        ConditionalsToken deployed = script.deploy();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(script)), SUPPLY);
        assertEq(deployed.name(), "Conditionals");
        assertEq(deployed.symbol(), "COND");
    }

    // ---------------------------------------------------------------------------------------------
    // transfer
    // ---------------------------------------------------------------------------------------------

    function test_transferMovesExactAmountAndEmits() public {
        uint256 amount = 1_234 ether;
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(DEPLOYER, ALICE, amount);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, amount));

        assertEq(token.balanceOf(ALICE), amount, "receiver got less than sent");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount, "sender lost more than sent");
        assertEq(token.totalSupply(), SUPPLY, "supply changed on transfer");
    }

    function test_transferWholeBalanceLeavesZero() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(DEPLOYER, 5 ether));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10 ether, 11 ether)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 11 ether);
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transfer(ALICE, 1);
    }

    function test_transferRevertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(DEPLOYER);
        token.transfer(address(0), 1 ether);
    }

    // ---------------------------------------------------------------------------------------------
    // approve / transferFrom
    // ---------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(DEPLOYER, ALICE, 7 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.approve(ALICE, 7 ether));
        assertEq(token.allowance(DEPLOYER, ALICE), 7 ether);
    }

    function test_approveRevertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(DEPLOYER);
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowanceExactly() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 100 ether);

        vm.prank(ALICE);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 60 ether));

        assertEq(token.balanceOf(BOB), 60 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 60 ether);
        assertEq(token.allowance(DEPLOYER, ALICE), 40 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromWithInfiniteAllowanceDoesNotDecrement() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, type(uint256).max);

        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1 ether);
        assertEq(token.allowance(DEPLOYER, ALICE), type(uint256).max);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1 ether));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1 ether);
    }

    function test_transferFromRevertsAboveAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 5 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 5 ether, 6 ether)
        );
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 6 ether);
    }

    function test_transferFromRevertsAboveBalanceEvenWithAllowance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 2 ether);
        vm.prank(ALICE);
        token.approve(BOB, 10 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 2 ether, 3 ether));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 3 ether);
    }

    /// @dev The deployer is the address a token would most plausibly trust. It gets no special pull rights.
    function test_deployerCannotPullWithoutAllowance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 9 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(ALICE, DEPLOYER, 1);
        assertEq(token.balanceOf(ALICE), 9 ether);
    }

    // ---------------------------------------------------------------------------------------------
    // Launch flows: everything arrives whole, supply never changes
    // ---------------------------------------------------------------------------------------------

    function test_launchFlowsArriveWhole() public {
        address distributor = address(0xD157);
        address claimant = address(0xC1A1);
        address remainder = address(0x612a9bB008e16ef2D24f41DAe9Fc661831d93367);

        uint256 swarm = (SUPPLY * 1_000) / 10_000;
        uint256 pool = (SUPPLY * 8_000) / 10_000;
        uint256 rest = SUPPLY - swarm - pool;

        vm.startPrank(DEPLOYER);
        assertTrue(token.transfer(distributor, swarm));
        assertTrue(token.transfer(ALICE, pool)); // ALICE stands in for the pool manager
        assertTrue(token.transfer(remainder, rest));
        vm.stopPrank();

        assertEq(token.balanceOf(distributor), swarm, "swarm share arrived short");
        assertEq(token.balanceOf(ALICE), pool, "pool share arrived short");
        assertEq(token.balanceOf(remainder), rest, "remainder arrived short");
        assertEq(token.balanceOf(DEPLOYER), 0, "factory kept something back");

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(claimant), swarm, "claim arrived short");
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.totalSupply(), SUPPLY, "launch flows changed the supply");
    }

    // ---------------------------------------------------------------------------------------------
    // No admin surface
    // ---------------------------------------------------------------------------------------------

    function test_noCallIncreasesSupply() public {
        address attacker = address(0xBEEF);
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);

            vm.prank(attacker);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, string.concat("unexpected function answered: ", signatures[i]));

            vm.prank(DEPLOYER);
            (ok,) = address(token).call(data);
            assertFalse(ok, string.concat("unexpected function answered: ", signatures[i]));

            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
        }
    }

    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY / 1_000);
        uint256 held = token.balanceOf(ALICE);

        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, true);
            vm.prank(DEPLOYER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, string.concat("unexpected function answered: ", signatures[i]));
        }

        assertEq(token.balanceOf(ALICE), held, "a privileged call moved the holder's balance");
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, held / 2), "the holder can no longer transfer");
        assertEq(token.balanceOf(BOB), held / 2);
    }

    function test_noEtherAccepted() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "token accepted ether");
        assertEq(address(token).balance, 0);
    }

    // ---------------------------------------------------------------------------------------------
    // Bytecode
    // ---------------------------------------------------------------------------------------------

    function test_runtimeFitsEip170() public view {
        uint256 size = address(token).code.length;
        assertGt(size, 0);
        assertLe(size, 24_576);
    }

    /// @dev Scans reachable opcodes the way the launch floor does: from the start or a JUMPDEST to
    ///      STOP, JUMP, RETURN, REVERT, INVALID or SELFDESTRUCT, skipping PUSH data.
    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
                assertTrue(op != 0xF2, "runtime code contains CALLCODE");
                assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupplyAndDeliversExactly(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != DEPLOYER);
        amount = bound(amount, 0, SUPPLY);

        vm.prank(DEPLOYER);
        assertTrue(token.transfer(to, amount));

        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.balanceOf(to) + token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);

        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(ALICE);
        token.transfer(BOB, amount);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowance, uint256 amount) public {
        allowance = bound(allowance, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY);

        vm.prank(DEPLOYER);
        token.approve(ALICE, allowance);

        if (amount > allowance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, allowance, amount)
            );
            vm.prank(ALICE);
            token.transferFrom(DEPLOYER, BOB, amount);
            assertEq(token.balanceOf(BOB), 0);
            assertEq(token.allowance(DEPLOYER, ALICE), allowance);
        } else {
            vm.prank(ALICE);
            assertTrue(token.transferFrom(DEPLOYER, BOB, amount));
            assertEq(token.balanceOf(BOB), amount);
            assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
            assertEq(token.allowance(DEPLOYER, ALICE), allowance - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_chainedTransfersConserveSupply(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, a);
        c = bound(c, 0, b);

        vm.prank(DEPLOYER);
        token.transfer(ALICE, a);
        vm.prank(ALICE);
        token.transfer(BOB, b);
        vm.prank(BOB);
        token.transfer(CAROL, c);

        assertEq(token.balanceOf(DEPLOYER), SUPPLY - a);
        assertEq(token.balanceOf(ALICE), a - b);
        assertEq(token.balanceOf(BOB), b - c);
        assertEq(token.balanceOf(CAROL), c);
        assertEq(
            token.balanceOf(DEPLOYER) + token.balanceOf(ALICE) + token.balanceOf(BOB) + token.balanceOf(CAROL), SUPPLY
        );
        assertEq(token.totalSupply(), SUPPLY);
    }
}
