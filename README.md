# Conditionals (COND)

A fixed-supply ERC-20 token for the IdentityMD custom-token launch on Robinhood Chain.

| Field | Value |
| --- | --- |
| Solidity contract | `ConditionalsToken` (`src/ConditionalsToken.sol`) |
| Token name | `Conditionals` |
| Token symbol | `COND` |
| Decimals | 18 |
| Total supply | 1,000,000,000 COND = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Owner / admin | none |
| Compiler | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"` |

## Behaviour

- The constructor mints the entire supply once to `msg.sender` and emits one `Transfer(0x0, deployer, supply)`.
- There is no mint, burn, pause, blacklist, freeze, fee, tax, reflection, owner, upgrade path, `delegatecall` or `selfdestruct`. `totalSupply()` is constant for the life of the contract.
- Transfers follow OpenZeppelin ERC20 v5 semantics exactly: `transfer`, `approve` and `transferFrom` return `true` on success and revert with the ERC-6093 custom errors (`ERC20InsufficientBalance`, `ERC20InsufficientAllowance`, `ERC20InvalidReceiver`, `ERC20InvalidSpender`) on failure. `transferFrom` only spends the caller's own allowance from the `from` account. An allowance of `type(uint256).max` is never decremented.
- The contract has no `receive` or `fallback` function, so it refuses ether.
- The constructor calls no other contract and depends on nothing on-chain, so it deploys identically on an empty chain and under CREATE2 from the factory.

## Layout

```
foundry.toml                     compiler pins and remappings (solc 0.8.26, bytecode_hash none)
src/ConditionalsToken.sol        the token
script/DeployConditionals.s.sol  reviewable reference deployment (deploy() is called by tests)
test/ConditionalsToken.t.sol     unit and fuzz tests
lib/forge-std                    vendored forge-std v1.11.0 (src only), MIT/Apache-2.0
lib/openzeppelin-contracts       vendored OpenZeppelin Contracts v5.4.0, only the five files ERC20 needs, MIT
```

Dependencies are committed as ordinary files, not submodules, so the project builds offline.

## Build and test

```sh
forge build
forge test
forge fmt --check
```

Tests read no environment variables, depend on no caller address, and pass in any order and in parallel.
The fuzz tests pass with `FOUNDRY_FUZZ_SEED=0xaab85bcc3a88f94c8afc31f08ba09ca24ba8ddbde53252abefd8353c5463f7b7`.

What the tests cover:

- metadata, decimals and the exact supply constant;
- the whole supply landing on the deployer, both from an EOA and through CREATE2 from a factory-like contract at the predicted address;
- the deploy script's `deploy()` minting to its caller;
- `transfer`, `approve` and `transferFrom` success paths with events and exact balance and allowance arithmetic;
- failure paths: insufficient balance, empty account, zero-address receiver, zero-address spender, missing or insufficient allowance, allowance without balance, and the deployer trying to pull without an allowance;
- the launch flows (10% to a distributor, 80% to a pool stand-in, 10% to the remainder address, then a claim) arriving whole with the supply unchanged;
- that none of the common mint, ownership, upgrade, pause, blacklist, freeze, lock, seize or `burnFrom` selectors exists, from a stranger and from the deployer, and that a holder can still transfer afterwards;
- the runtime fitting EIP-170 and containing no reachable `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`;
- fuzzed conservation of supply across single and chained transfers, fuzzed reverts above balance, and fuzzed `transferFrom` against arbitrary allowances.

## Deployment parameters

The launch is performed by IdentityMD's deployer through `ProjectFactory.launchCustom`; nothing in this repository deploys, broadcasts or signs.

- Chain: Robinhood Chain, chain id 4663.
- Token contract: `ConditionalsToken`, no constructor arguments, so the factory is `msg.sender` and receives the whole supply.
- Manifest `token.totalSupply`: `1000000000000000000000000000` (10^27).
- Manifest `token.decimals`: `18`.
- Application contracts: none.
- Pool: paired with IMD (`0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127`), fee 12500, tick spacing 60; the deployer derives the opening price from the economics.
- Economics (copied verbatim by the manifest step): `poolBps` 8000, `initialMarketCapWei` 3000000000000000000000, `remainderTo` `0x612a9bb008e16ef2d24f41dae9fc661831d93367`.
- Distribution by the factory: 10% to the launch's MerkleDistributor, 80% seeds the pool, 10% to `remainderTo`. The token applies no fee to any of these flows.

The script in `script/DeployConditionals.s.sol` is a reference for local or independent deployments only. Its `run()` broadcasts from whatever signer `forge script` is given and `deploy()` holds the complete logic, which the tests exercise directly.

## After launch

Nothing. The token has no owner, no setters and no configuration. There is no value for anyone to supply after deployment.

## Assumptions

- "All minted once to the deployer" is read as minting to `msg.sender` of the constructor, which on the launch is the ProjectFactory. The factory, not the contract, distributes the supply.
- The brief asks for no transfer rules, so none were added: no tax, burn, vesting, reflection or governance. Adding any of these later would require a new token, as this one has no upgrade path.
- Decimals are fixed at 18 as the brief states.
- The vendored OpenZeppelin ERC20 is unmodified from v5.4.0. Its `_update` hook is not overridden.
- The compiler's default EVM target for solc 0.8.26 (cancun) is used. The token itself uses no transient storage or other post-Shanghai opcodes.

## Operational responsibilities

- Holders: a COND balance is controlled only by its holder's key or by spenders the holder approves. Lost keys cannot be recovered and approvals should be granted sparingly; there is no admin who can reverse a transfer.
- Launch deployer (IdentityMD): deploys the attested creation code through the factory, forwards the swarm share, seeds the pool and forwards the remainder. The token requires nothing from it beyond deployment.
- Requester: receives the 10% remainder at `remainderTo`. No ongoing operation is needed or possible; there is no key to safeguard for the contract itself.
- Everyone: tests passing are not an audit. The token is a thin wrapper over OpenZeppelin ERC20 v5.4.0 with no custom logic, but independent review before relying on it is still the right practice.

## Security notes

Checked against the eth-security reference: no reentrancy surface (no external calls, no hooks), no access control to misconfigure, no upgradeability, no `selfdestruct`, no `delegatecall`, no arbitrary `transferFrom` (allowance only from `msg.sender`), no `abi.encodePacked` of dynamic values, no shifts in assembly, no uninitialized storage pointers, no environment reads in tests. Slither was not available on this machine and was not run; the contract contains no code outside OpenZeppelin's ERC20 and the three constants, so none of the six rejecting detectors have anything to match.
