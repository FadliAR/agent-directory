# CHECKS.md — Agent Directory vs. Agent ID Hackathon rules

Source of rules: official Binance announcement "Agent ID Hackathon: Build
Decentralized Applications (dApps) Around Agent ID to Win 60,000 USDC"
(Binance Wallet + BNB Chain, submission period 2026-11-18 08:00 UTC →
2026-12-09 08:00 UTC). Every rule is mapped to how this build satisfies it.
Status column reflects the LOCAL build; deployment steps are gated on the
user's explicit decision and are marked accordingly.

## Eligibility & submission requirements

| # | Rule (from the announcement) | How this build satisfies it | Status |
|---|---|---|---|
| E1 | Project deployed on BNB Chain (chain id 56) | `AgentDirectory.sol` is plain EVM Solidity with no chain-specific opcodes; constructor takes the BNB Chain Agent ID contract address. Deployment itself is a later, separately approved step. | Build ready; deploy pending user decision |
| E2 | Contract source verified and open-source on BscScan | Single self-contained source file, zero external imports, SPDX MIT header, pinned compiler (solc 0.8.26, optimizer 200 runs in `foundry.toml`) so BscScan verification is a byte-for-byte match. Repo is published open-source (MIT) by the parent after review. | Ready |
| E3 | Project must ACTIVELY use Agent ID | Agent ID ownership is the gate for the product's core flow: `registerCard`, `updateCard` and `endorse` all revert unless `balanceOf(msg.sender) > 0` on the real Agent ID contract (`0x60b9262456de011f7d15a54cdd8c48baaa8b022f`). No card, no endorsement, no directory presence without an Agent ID. The check address is set once in the constructor and is `immutable`. | Done in contract |
| E4 | New and existing projects eligible; only data generated during the submission period counts | New project; all interactions will occur after deployment inside the window. Events (`CardRegistered`, `CardUpdated`, `CardDeregistered`, `Endorsed`) are emitted for every interaction so period activity is independently countable. | Done in contract |
| E5 | One project per team | One contract, one repo, one submission. | By construction |
| E6 | Submission = project name, website, contract address(es), Agent ID usage description | `README.md` carries the name, a plain-language Agent ID usage description, and placeholders for the website URL and deployed address(es), to be filled at submission time. | Draft ready |

## Award-track requirements

| # | Rule | How this build satisfies it | Status |
|---|---|---|---|
| A1 | Ecosystem Pioneer Award: ranked by (a) number of distinct Agent ID holder addresses interacting with the contract and (b) transaction volume/count during the submission period | Every state-changing function is a real on-chain transaction from a distinct Agent ID holder address (the gate guarantees the "Agent ID holder" property for every interacting address). No fake-volume mechanics: the contract holds no value and moves no assets, so counted volume is genuine usage transactions only. Growth plan is organic only (see DESIGN.md) — no wash activity of any kind. | Design compliant |
| A2 | Innovation Award eligibility: product LIVE and ≥30 distinct Agent ID addresses interacting during the submission period | Product liveness = deployed contract + static frontend reading it (frontend included in this build). The ≥30-address bar is a distribution task, addressed by the concrete outreach plan in DESIGN.md; the contract itself makes every qualifying interaction countable via events and `totalAgents()`. | Plan in DESIGN.md |
| A3 | Innovation judging: Agent ID Application Depth (30%) | Identity is not a bolt-on: the directory cannot be written to at all without holding an Agent ID, and the registry's subject matter is Agent ID holders themselves (their public `.ai` service cards). | Done in contract |
| A4 | Innovation judging: Practicality & Feasibility (25%) | Solves a real, current problem: agent-economy participants (mint projects, service agents, marketplaces) have no on-chain way to discover which Agent ID holders offer what. Read API (`totalAgents`, `listAgents`, `getCard`, `getEndorsementCount`) is deliberately indexer- and frontend-friendly. | Done in contract |
| A5 | Innovation judging: Product Completion (25%) | Working contract + full Foundry test suite + working static frontend in this build; deployment and verification are the only remaining steps and are costed in DESIGN.md/README. | Local build complete |
| A6 | Innovation judging: Innovation (20%) | An opt-in, self-sovereign service registry for Agentic Wallet identities with an on-chain endorsement graph — no equivalent registry exists for Agent ID holders today (see DESIGN.md). | Design position |

## Safety red lines (disqualification risks) — all must hold

| # | Red line | How this build satisfies it |
|---|---|---|
| S1 | No web-based QR-code login for Agentic Wallet | The frontend has no QR flow at all. It uses the standard injected provider (`window.ethereum`) of the visitor's own browser wallet. |
| S2 | No storing user sessions server-side | There is no server. The frontend is a static page; all reads go from the visitor's browser to a public BSC RPC; all writes are signed in the visitor's own wallet. Nothing is collected or stored anywhere off-chain. |
| S3 | No bypassing user transaction confirmation | Every write is initiated by an explicit button click in the visitor's browser and confirmed in their own wallet UI. No auto-signing, no session keys, no meta-transaction relayers. |
| S4 | No unauthorized / scheduled / bundled asset transfers | The contract is non-payable, holds no funds, and contains no transfer functionality of any kind. It cannot move any asset, ever. |
| S5 | No hidden unlimited approvals | The contract never calls `approve`, `transferFrom`, or any token contract except the read-only `balanceOf` on the Agent ID contract. There is no token in this product at all. The frontend requests no approvals. |
| S6 | Contracts open-source with owner permissions disclosed | The contract has **no owner and no admin functions at all** — no pause, no upgrade, no withdrawal, no setters. The only privileged decision was the constructor argument (the Agent ID contract address), which is `immutable` and disclosed in README.md. |
| S7 | No Binance / BNB brand impersonation | Product name is "Agent Directory". No Binance or BNB logos, names, or trade dress in the product or frontend. README states the project is independent and not affiliated with Binance, BNB Chain, or SPACE ID. |
| S8 | No collecting seed phrases, private keys, API secrets, or pairing codes | Nothing in the contract or frontend asks for, accepts, or could receive any credential. The only user inputs are the four public card fields (name, category, description, endpoint). |
| S9 | No promising returns | No token, no yield, no staking, no financial language anywhere in the contract, frontend, or README. The product is a directory. |
| S10 | Trading products must show risk warnings | Not a trading product — no swaps, prices, or orders exist. (Frontend carries a plain "you sign your own transactions; registration costs only network gas" note instead.) |
| S11 | Agent ID must not be packaged as a tool to look up other people's wallets | The directory only ever shows agents who **opted in themselves**, by sending a registration transaction from their own wallet. It performs no name resolution of arbitrary addresses, exposes nothing about non-registrants, and any registrant can erase their card at any time with `deregister()`. |

## Build-level checks (our own discipline)

| # | Check | Result |
|---|---|---|
| B1 | Foundry test suite covers: holder/non-holder gating, register, update, endorse rules (self / duplicate / unregistered target / non-holder), deregister incl. list integrity, re-registration, pagination, string-length caps, zero-address constructor | See `test/AgentDirectory.t.sol`; run output recorded in DESIGN.md |
| B2 | Deployment gas measured locally (Anvil) and quoted in gas units + BNB at ~1 gwei | See DESIGN.md / README.md |
| B3 | No mainnet/testnet deployment, no wallet use, no spending during the build phase | Honoured — local Anvil only, with Anvil's public dev account |
