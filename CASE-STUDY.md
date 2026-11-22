# Case study: smart contract build and pre-audit review

*Portfolio sample. The scenario, team and contract are made up; the review findings, fixes and test results are real.*

**Example scenario.** A small team has written a "group gift" smart contract: friends chip in, and the money goes to one person if a goal is met. They want it checked before launch, and they want it to work with a stablecoin as well as ETH.

**What I did.**
- Read the contract line by line against what it was meant to do, and ran the standard automated tools (Slither, Solhint).
- Wrote a test for each problem: one showing it happen, and one proving the fix.
- Rebuilt the contract with clear rules: refunds if the goal is missed, a way for the organiser to call it off, and a safety net that returns everyone's money if the gift isn't delivered within 5 business days.
- Added stablecoin support, including tokens that take a fee on each transfer.

**What the review found.** 6 issues: 1 Critical (anyone could drain the refunds), 1 High, 1 Medium and 3 Low. The automated tools caught some of them. The two that broke the contract's own rules were only found by reading the code carefully. All 6 are fixed, and the findings are written up in a plain-English report.

**Proof.** 68 tests with 100% coverage, including random simulations of 50,000 actions. 10 deliberate bugs are planted by a script, and all 10 are caught. Zero warnings from the compiler and the code checkers.

**Honest scope.** This is a pre-audit check, not a formal audit. Anything holding real money should also be independently audited.

**Stack.** Solidity 0.8.39, OpenZeppelin 5.7.0, Foundry 1.10.0, Slither, Solhint.
