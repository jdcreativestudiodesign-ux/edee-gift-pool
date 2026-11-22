# E-dee Gift Pool: a group gift collection on the blockchain

[![tests](https://github.com/jdcreativestudiodesign-ux/edee-gift-pool/actions/workflows/test.yml/badge.svg)](https://github.com/jdcreativestudiodesign-ux/edee-gift-pool/actions/workflows/test.yml)

> **Portfolio sample** by **jdcreative.studiodesign**. Demo only: for public test networks, never real money. All names are made up.

Friends chip in towards one gift, like an office collection, except the rules are enforced by a smart contract instead of trust:

- **Goal reached:** the money goes to the person receiving the gift.
- **Goal missed by the closing date, or the organiser calls it off:** everyone takes their own money back.
- **Safety net:** if the gift still hasn't been delivered 5 business days after the closing date, everyone can take their money back.
- **Nobody can run off with the money,** not even the organiser. It can only go to the recipient or back to the people who paid it in.

It works with **ETH** or a **stablecoin such as USDC**, chosen when the gift is set up.

This repo also includes a **sample review report** ([REVIEW-REPORT.md](REVIEW-REPORT.md)): a deliberately flawed "before" version, 6 issues found and ranked in plain English, and a test proving each fix.

## Test results

```
Ran 3 tests for test/BusinessDays.t.sol:BusinessDaysTest            3 passed
Ran 25 tests for test/EdeeGiftPool.t.sol:EdeeGiftPoolEthTest       25 passed
Ran 26 tests for test/EdeeGiftPool.t.sol:EdeeGiftPoolTokenTest     26 passed
Ran 12 tests for test/ReviewFindings.t.sol:ReviewFindingsTest       12 passed
EdeeGiftPoolEthInvariants   (runs: 1000, calls: 50000)                 passed
EdeeGiftPoolTokenInvariants (runs: 1000, calls: 50000)                 passed
68 tests passed, 0 failed
```

- **100% coverage** of lines, statements, branches and functions.
- **Every rule is tested twice:** once with ETH and once with a stablecoin.
- **Invariant tests** fire 50,000 random actions and check after each one that money is never created, lost, or paid to the wrong person.
- **Proof the tests work:** `./negative-controls.sh` plants 10 deliberate bugs, one at a time, and all 10 are caught.

## Run it

Requires [Foundry](https://getfoundry.sh).

```
git clone --recursive https://github.com/jdcreativestudiodesign-ux/edee-gift-pool
cd edee-gift-pool
forge test
```

Every push is also tested automatically on GitHub (see `.github/workflows/test.yml`).

## How it works

| Action | Who | When |
|---|---|---|
| `contribute(amount)` | Anyone | Until the closing date |
| `release()` | The organiser, or anyone after the closing date | Once the goal is met, before the safety net opens |
| `cancel()` | The organiser | Any time before release |
| `refund()` | Each contributor, for their own share | If cancelled, the goal was missed, or the safety net opened |

For ETH, send `amount` as the payment. For a stablecoin, approve the contract first and send no ETH. Tokens that take a fee on transfer are handled: each person is credited with what actually arrived.

## Built with

Solidity 0.8.39 · OpenZeppelin Contracts 5.7.0 · Foundry 1.10.0 · Slither · Solhint

## Folder guide

```
src/                 EdeeGiftPool.sol and BusinessDays.sol (the contract)
test/                Unit, fuzz, invariant and review-finding tests
review/before/       The flawed "before" version used in the review report
review/tool-output/  Raw Slither and Solhint results
REVIEW-REPORT.md     The sample review report
```

## Licence

© 2026 jdcreative.studiodesign. All rights reserved. Shared for portfolio viewing only; see [LICENSE](LICENSE).
