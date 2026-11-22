# Smart contract review: E-dee Gift Pool

> **Portfolio sample** by **jdcreative.studiodesign**. The "client", the contract and every name in it are made up.
> This is a **code review / pre-audit check**, not a formal security audit, and it is not a guarantee that code is safe. Anything that will hold real money should also get an independent professional audit.

| | |
|---|---|
| **Date** | 21 November 2026 |
| **What was reviewed** | `review/before/EdeeGiftPoolBefore.sol` (46 lines), as sent in by the client |
| **File fingerprint (SHA-256)** | `e5a5aa66346cb56f…` (the fixed version is in `src/`) |
| **What it does** | Friends chip in towards one gift. If the goal is reached, the money goes to the recipient; if not, everyone takes their money back. |
| **Result** | 6 issues found: 1 Critical, 1 High, 1 Medium, 3 Low, plus 6 notes. All fixed, and each fix is proven by a test. |

## Summary

| ID | Severity | Issue | Status |
|---|---|---|---|
| EG-01 | **Critical** | Anyone can drain everyone's refunds | Fixed |
| EG-02 | **High** | After the goal is met, people can still pull their money out, so the gift arrives short | Fixed |
| EG-03 | **Medium** | The gift can't be paid to smart-contract wallets (e.g. a Safe) | Fixed |
| EG-04 | Low | Money is accepted after the closing date | Fixed |
| EG-05 | Low | A malicious website can trigger the payout without the organiser meaning to | Fixed |
| EG-06 | Low | No checks on the setup values | Fixed |
| N-01–06 | Note | Code quality and missing features | Fixed |

**Severity guide.** *Critical*: money can be stolen. *High*: the contract breaks its main promise. *Medium*: money can get stuck, or a common case fails. *Low*: limited harm, or needs an unusual situation. *Note*: no direct risk.

## Findings

### EG-01 · Critical · Anyone can drain everyone's refunds

**Where:** `refund()`, lines 37–45.
**What happens:** the contract sends the money first and only afterwards records that the person has been refunded. A contributor using a smart-contract wallet can make that wallet call `refund()` again *while it is being paid*, before the record is updated, over and over until the pool is empty.
**Proof:** `test_EG01_before_attackerDrainsEveryonesMoney`. The attacker pays in 1 ETH and walks away with 9 ETH, which is everyone's money.
**Fix:** record the refund *before* sending (the "checks, effects, interactions" order), and add OpenZeppelin's `ReentrancyGuard` as a second lock. With the fix, the same attack gets back exactly the 1 ETH it paid in (`test_EG01_after_attackerGetsOnlyTheirOwnMoney`).

### EG-02 · High · After the goal is met, people can still pull their money out

**Where:** `refund()`, line 38. It only checks that the closing date has passed, not whether the goal was met.
**What happens:** once the closing date passes, any contributor can take their money back even though the goal was reached, right up until the organiser presses "release". The recipient then gets less than everyone was promised.
**Proof:** `test_EG02_before_goalMetButContributorsPullTheirMoneyBack`. The goal of 10 ETH is met, one person withdraws 4, and the recipient receives 6.
**Fix:** refunds open only if the goal was missed, the organiser calls the gift off, or the safety net opens (see below). Once the goal is met, the money can only go to the recipient (`test_EG02_after_onceGoalIsMetTheMoneyGoesToTheRecipient`).

### EG-03 · Medium · The gift can't be paid to smart-contract wallets

**Where:** `release()`, line 34, `recipient.transfer(...)`.
**What happens:** `transfer` only passes along a tiny amount of gas (2,300). Smart-contract wallets such as a Safe need more than that to accept a payment, so `release()` always fails and the gift can never be delivered. The Solidity compiler itself now marks `transfer` as deprecated for this reason.
**Proof:** `test_EG03_before_smartWalletRecipientCanNeverBePaid`.
**Fix:** send with a full-gas `call` and check that it succeeded (`test_EG03_after_smartWalletRecipientIsPaid`). The re-entry protection from EG-01 keeps this safe.

### EG-04 · Low · Money is accepted after the closing date

**Where:** `contribute()`, lines 23–27. There is no closing-date check.
**What happens:** late payments are accepted, which is confusing for contributors and makes the totals unreliable.
**Proof:** `test_EG04_before_acceptsMoneyAfterTheClosingDate`.
**Fix:** contributions close exactly at the closing date (`test_EG04_after_closingDateIsEnforced`).

### EG-05 · Low · A malicious website can trigger the payout

**Where:** `release()`, line 30, `require(tx.origin == organiser)`.
**What happens:** `tx.origin` is whoever started the transaction, not who is actually calling. If the organiser is tricked into using a malicious contract (for example, "claim your free badge"), that contract can call `release()` in the organiser's name. In this contract the money can still only go to the recipient, so the harm is limited to an early or unwanted payout. That's why it's rated Low.
**Proof:** `test_EG05_before_aMaliciousSiteCanTriggerReleaseEarly`.
**Fix:** check `msg.sender`, the direct caller (`test_EG05_after_onlyADirectCallFromTheOrganiserCounts`).

### EG-06 · Low · No checks on the setup values

**Where:** the constructor, lines 16–21.
**What happens:** a gift can be created with no recipient (money sent there is lost forever), a goal of zero, or a closing date in the past.
**Proof:** `test_EG06_before_acceptsAZeroRecipientAndAPastClosingDate`.
**Fix:** these are refused when the gift is set up (`test_EG06_after_badSetupIsRefused`).

### Notes (no direct risk, all addressed)

- **N-01** The compiler version is left open (`^0.8.0`), so the code could be built with older compilers that have known bugs. Now pinned to Solidity 0.8.39, the newest stable release, which has no known bugs.
- **N-02** No events are emitted, so websites and block explorers can't show contributions, refunds or the payout. Events have been added for each.
- **N-03** Settings that never change aren't marked `immutable`, which wastes gas on every read. Fixed.
- **N-04** Text error messages are used instead of custom errors. Custom errors are cheaper and easier for a website to translate into friendly messages.
- **N-05** Zero-value contributions are accepted, which adds noise. They're now refused.
- **N-06** There is no way to call the gift off. Also, once EG-02 is fixed, money could get stuck if the recipient can't be paid and the organiser disappears. In this version it only escapes that because of the EG-02 flaw. Added: the organiser can call the gift off before release; anyone can deliver it after the closing date; and a safety net opens refunds 5 business days after the closing date if it still hasn't been delivered.

## How the review was done

1. **Read by hand**, line by line, against the client's description of how the gift should behave.
2. **Automated tools** on both versions (Slither 0.11.6, Solhint 6.2.5, and the Solidity compiler's own warnings).
3. **A test proving each finding**: the problem happening in the "before" version and failing against the fixed one (`test/ReviewFindings.t.sol`).
4. **A full test suite for the fixed version** (Foundry 1.10.0): 68 tests, run for both ETH and a stablecoin; random-input tests; and invariant tests that fire 50,000 random actions per run and check after each one that money is never created, lost or paid to the wrong person.
5. **Proof the tests work**: `negative-controls.sh` plants 10 deliberate bugs in the fixed contract, one at a time. All 10 were caught.

**Coverage of the fixed contract: 100%** of lines, statements, branches and functions.

### What the tools found, and what only a person found

| Finding | Slither | Solhint | Compiler | Found by reading |
|---|:-:|:-:|:-:|:-:|
| EG-01 Re-entry drain | ✓ | | | ✓ |
| EG-02 Refunds after goal met | | | | ✓ |
| EG-03 `transfer` and smart wallets | | | ✓ (deprecation) | ✓ |
| EG-04 Late contributions | | | | ✓ |
| EG-05 `tx.origin` | ✓ | ✓ | | ✓ |
| EG-06 Setup checks | partly | | | ✓ |

The tools are valuable, but EG-02 and EG-04, which break the contract's own rules, were only found by reading the code against what it is supposed to do.

### Tool results on the fixed version, reviewed

- **Solhint: 0 warnings.** Three rules are switched off in `.solhint.json`, each for a stated reason. `import-path-check` can't read Foundry's library paths, and the compiler checks every import anyway. `gas-strict-inequalities` would change the meaning of the date rules. `gas-indexed-events` adds cost with no benefit here.
- **Slither: 13 notes, all reviewed and accepted:**
  - *timestamp* (4): the rules use dates measured in days, and a validator can only shift a block's time by seconds.
  - *arbitrary-send-eth* and *low-level-calls* (1 each): payments only ever go to the fixed recipient, or back to a contributor's own recorded share, and the full-gas call is the EG-03 fix.
  - *incorrect-equality* (1): `received == 0` is an intentional exact check.
  - *naming-convention* (6): settings that never change are written in CAPITALS, as Foundry's own style checker requires.
- **Foundry's built-in checker: 0 warnings.** The timestamp rule is excluded in `foundry.toml`, and the payment line is marked as reviewed, both for the reasons above.
- **Defence in depth:** the `nonReentrant` locks on `refund()` and `contribute()` are a deliberate second layer. Because the first layer (updating records before paying) already stops the attack, removing only the second layer doesn't change any result a test can observe. That is expected, not a gap.

Full tool output is in `review/tool-output/`.

## What this review did not cover

- Deploying to a live network, or how a website talks to the contract.
- Tokens that change balances on their own (rebasing or interest-bearing tokens). E-dee Gift Pool is meant for stablecoins such as USDC and is documented as such.
- Stablecoin issuers' own powers: for example, USDC can freeze an address. If the recipient is frozen, the payout fails and the safety net returns everyone's money.
- Public holidays. The safety net counts Monday to Friday in UTC, because blockchains don't know about holidays.
- Gas cost optimisation beyond the notes above.
- An independent formal audit.

---
*Questions about this report are welcome through my Fiverr or Upwork profile.*
