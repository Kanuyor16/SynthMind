SynthMind: AI-Powered Synthetic Asset Management Protocol
=========================================================

I have developed this comprehensive documentation to provide an exhaustive technical deep dive into the **SynthMind** smart contract. This README covers every facet of the Clarity code, from its error-handling philosophy to the intricate logic governing its diversified collateral engine.

* * * * *

1\. Technical Architecture Overview
-----------------------------------

**SynthMind** is a decentralized synthetic asset issuance protocol built on Stacks. I have designed it to utilize AI-driven price oracles that provide not just price data, but confidence intervals and risk scores. The contract ensures protocol solvency through over-collateralization and a competitive liquidation market.

* * * * *

2\. Error Handling & Constants
------------------------------

I have implemented a robust set of error constants to ensure that any failure state is explicitly communicated to the calling application. This is critical for frontend integration and debugging.

### 2.1 Error Code Registry

| **Constant** | **Code** | **Description** |
| --- | --- | --- |
| `ERR-NOT-AUTHORIZED` | `u100` | Thrown when a non-owner attempts administrative tasks or a non-oracle attempts to submit prices. |
| `ERR-INSUFFICIENT-COLLATERAL` | `u101` | Triggered if a user's health ratio falls below the `MIN-COLLATERAL-RATIO` during minting. |
| `ERR-INVALID-AMOUNT` | `u102` | Used for zero-value deposits, negative inputs, or mismatched list lengths. |
| `ERR-POSITION-NOT-FOUND` | `u103` | Thrown when attempting to interact with a principal that has no open position. |
| `ERR-STALE-PRICE` | `u104` | Triggered if the oracle data is older than `ORACLE-STALENESS-LIMIT` (100 blocks). |
| `ERR-LIQUIDATION-NOT-ALLOWED` | `u105` | Thrown when attempting to liquidate a healthy position ($>120\%$). |
| `ERR-CONTRACT-PAUSED` | `u106` | Emergency state error; stops all state-changing interactions. |
| `ERR-ORACLE-NOT-REGISTERED` | `u107` | Thrown when a principal not in the `authorized-oracles` map tries to submit data. |
| `ERR-EXCEEDS-MAX-POSITION` | `u108` | Prevents any single user from controlling >10% of the protocol's total collateral. |

### 2.2 Protocol Parameters

-   **`MIN-COLLATERAL-RATIO (u150)`**: The baseline 150% requirement for minting.

-   **`LIQUIDATION-THRESHOLD (u120)`**: The 120% danger zone where positions become eligible for liquidation.

-   **`LIQUIDATION-BONUS (u10)`**: A 10% incentive for liquidators to cover bad debt.

-   **`COOLDOWN-BLOCKS (u10)`**: A mandatory 10-block wait between interactions to prevent price manipulation exploits.

* * * * *

3\. Deep Dive: Private Internal Logic
-------------------------------------

I use private functions to handle the heavy mathematical lifting. These functions are not accessible externally, ensuring the integrity of the calculations.

### `calculate-position-health`

I use this to derive the current ratio of collateral value to debt.

$$Health = \frac{(Collateral \times Price) \times 100}{Debt \times 100,000,000}$$

Note: If debt is zero, I return u999999 to represent an "infinitely" healthy position.

### `calculate-max-mintable`

I designed this to calculate the ceiling for synthetic issuance based on the `MIN-COLLATERAL-RATIO`.

-   **Formula:** `(/ (* collateral price) (* MIN-COLLATERAL-RATIO u1000000))`

### `is-liquidatable`

A simple boolean check. If the health value is numerically less than `LIQUIDATION-THRESHOLD`, the function returns `true`.

* * * * *

4\. Deep Dive: Public Functions
-------------------------------

These are the primary entry points for users and oracles.

### 4.1 Administrative & Oracle Functions

-   **`register-oracle`**: I allow the contract owner to whitelist specific AI agents. This populates the `authorized-oracles` map with an initial `credibility-score` of 100.

-   **`submit-price-feed`**: This is how AI agents push data to the chain. I have enforced a `MIN-ORACLE-CONFIDENCE` check here; if the AI isn't at least 60% sure of its data, the price is rejected.

-   **`pause-contract / resume-contract`**: Standard emergency circuit breakers.

### 4.2 User Interaction Functions

-   **`deposit-collateral`**: Transfers STX from the user to the contract. I update the `user-positions` map and increment the `total-collateral` global variable.

-   **`mint-synthetic`**: The engine for synthetic issuance. I check against the `COOLDOWN-BLOCKS` and verify the `max-mintable` limit before deducting a `MINTING-FEE-BPS`.

-   **`liquidate-position`**: This function allows a third party to "bail out" an under-collateralized position. I have restricted this so a liquidator can only cover up to 50% of the total debt in a single transaction, preventing total "wiping" of users while ensuring protocol safety.

### 4.3 Advanced Management: `manage-diversified-collateral-position`

I consider this the most advanced feature of the protocol. It allows for:

-   **Multi-Asset Input**: Handling lists of assets and amounts simultaneously.

-   **AI Risk Integration**: Taking a list of `risk-scores` provided by the user (and verified against the oracle) to adjust the required collateral ratio.

-   **Diversification Bonus**: I reward users for not putting all their eggs in one basket. If `num-assets > 2`, the required collateral ratio drops, increasing capital efficiency.

* * * * *

5\. Read-Only Functions
-----------------------

These functions do not cost gas and are used for querying the state of the blockchain.

-   **`get-user-position (user principal)`**: Returns a detailed object containing:

    -   `collateral-deposited`

    -   `synthetic-minted`

    -   `position-health`

    -   `liquidation-protected` (boolean)

-   **`get-current-price`**: Returns the most recent AI-verified price from the global state.

* * * * *

6\. Full MIT License
--------------------

```
MIT License

Copyright (c) 2026 SynthMind Protocol

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```

* * * * *

7\. Development & Contribution
------------------------------

### Running Tests

I recommend using the following Clarinet command to test the error constants specifically:

clarinet test ./tests/synth-mind_test.ts

### Contribution Rules

1.  **Strict Typing**: All new functions must use explicit `uint` or `principal` types.

2.  **Safety First**: Any modification to the `calculate-position-health` function requires a full mathematical proof in the PR description.

3.  **Documentation**: Update the "Error Code Registry" in this README if you add new error constants.

* * * * *
