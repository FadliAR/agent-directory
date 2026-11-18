# DESIGN.md — Agent Directory

## What it is

An opt-in, on-chain registry for the agent economy. Any wallet that holds a
Binance **Agent ID** (the soulbound SPACE ID ERC-721, `name.ai`) can publish
one public service card — agent name, category, description, contact
endpoint — and can endorse other registered agents. Everyone can read the
directory; only Agent ID holders can write to it; nobody's data appears
unless they put it there themselves, and they can erase it at any time.

One contract (`AgentDirectory.sol`, ~230 lines, zero imports, no owner, no
token, no value handling), one static frontend page, nothing else.

## Why it fits the judging weights

**Innovation Award criteria:**

- **Agent ID Application Depth (30%)** — Agent ID is not a login badge
  bolted onto an unrelated product. The directory's *subject matter* is
  Agent ID holders, and its *write access* is Agent ID ownership itself:
  `registerCard`, `updateCard`, and `endorse` all check
  `balanceOf(caller) > 0` against the real Agent ID contract
  (`0x60b9262456de011f7d15a54cdd8c48baaa8b022f`, set immutably at
  construction). Remove Agent ID and the product cannot function at all.
- **Practicality & Feasibility (25%)** — discovery is a live problem in
  this ecosystem right now: hundreds of agent-facing projects (mints,
  services, marketplaces) already gate on Agent ID, yet there is no
  on-chain way to answer "which Agent ID holders offer research / data /
  art / tooling, and how do I reach them?" The read API
  (`totalAgents`, `listAgents`, `getCard`, `getEndorsementCount`,
  `hasEndorsed`) is designed so any frontend, indexer, or another agent
  can consume the directory without permission.
- **Product Completion (25%)** — contract complete, 24/24 Foundry tests
  passing, an end-to-end smoke test on local Anvil (deploy → register →
  read back) passing, frontend complete. The only remaining steps are
  deployment + BscScan verification, both costed below.
- **Innovation (20%)** — to our knowledge this is the first self-sovereign
  service registry for Agentic Wallet identities: registration is a
  capability proof (holding the soulbound ID), listings are erasable by
  their owners, and the endorsement graph creates a portable,
  wallet-native reputation signal that no platform controls.

**Ecosystem Pioneer Award (metrics):** every interaction the award counts
— a distinct Agent ID holder address transacting with the contract — is
exactly the product's normal use (register, update, endorse). There is no
value in the contract, so there is nothing to wash-trade; growth must be
genuine registrations, which is also what the product needs to be useful.

## Agent ID contract interface — research findings

The design depends on exactly one function of the Agent ID contract:
`balanceOf(address)`, which is the holding check Binance's own
announcement documents in its Developer Resources table ("Call
balanceOf(address) on the contract; a return value greater than 0
indicates the address holds an Agent ID").

What we verified read-only:

- The contract is "SPACE ID Agent ID", symbol `AI`, a **soulbound
  (non-transferable) ERC-721**, and is **not an upgradeable proxy** (it
  has an owner — SPACE ID). Confirmed via Binance's announcement and
  independent third-party project documentation that gates on it
  (e.g. bstockrc20's contract notes, Flaggies docs, AVE GENESIS mint
  page) — all of them use the identical `balanceOf(caller) > 0` pattern,
  so our gate matches the ecosystem's established integration.
- We attempted to read the full verified source on BscScan directly; the
  explorer blocked our fetcher (HTTP 403) and the legacy API endpoint
  redirected to a landing page, so the complete source was **not**
  line-by-line reviewed. This is a noted gap, mitigated by the fact that
  the design relies solely on the standard ERC-721 `balanceOf`, whose
  behaviour is confirmed by multiple independent integrations.
- **No third-party name-resolution function** (address → `.ai` name, or
  tokenId → name) is documented for this contract in the sources checked;
  SPACE ID resolution lives in its own naming stack. The design therefore
  deliberately does **not** resolve names: each holder self-declares
  their `.ai` name string in their own card, written by their own gated
  transaction. This is also the safer product shape — it keeps the
  directory strictly opt-in and clear of the hackathon's red line against
  packaging Agent ID as a tool to look up other people's wallets. If a
  resolution function is later confirmed from the verified source, a v2
  could verify the declared name against the caller's token; the gate
  does not need it.

## Test results

Foundry suite `test/AgentDirectory.t.sol` (with `test/MockAgentID.sol`
modelling the Agent ID contract's `balanceOf`):

**24 tests passed, 0 failed.** Coverage: constructor (address set,
zero-address revert); registration gating (holder can, non-holder cannot,
double registration, empty name, overlong fields); update (works,
preserves `registeredAt`, reverts when unregistered or non-holder);
endorsements (works, counts visible via `getCard`; non-holder, self,
duplicate, unregistered target, and deregistered target all revert);
deregistration (removal, swap-and-pop list integrity when a middle entry
leaves, re-registration, exit works even if the ID is later revoked);
reads (pagination incl. partial/past-end/zero-limit pages, unknown
address behaviour).

Local Anvil smoke test: deployed `MockAgentID` + `AgentDirectory`,
registered a card for `nerokais.ai` from the Anvil dev account, read it
back via `totalAgents()` / `getCard()` — all correct.

## Deployment cost (measured, local Anvil)

Deployment gas is identical for test and production constructor
arguments, as expected (the argument is a single address):

| Item | Gas |
|---|---|
| Deploy `AgentDirectory` | **1,273,239** |
| Deployed bytecode size | 5,906 bytes |
| `registerCard` (typical, first card) | ≈ 234,000 |
| `updateCard` | ≈ 32,000–57,000 |
| `endorse` | ≈ 27,000–76,000 |
| `deregister` | ≈ 24,000–80,000 |

At the reference gas price of **~1 gwei**, deployment costs
1,273,239 × 1e-9 = **≈ 0.00127 BNB**. Sensitivity: at 3 gwei ≈ 0.00382
BNB; at 5 gwei ≈ 0.00637 BNB. A funding budget of **0.0065 BNB** covers
deployment up to ~5 gwei. BscScan source verification is an off-chain
submission and costs no gas. User-side costs are borne by each user and
are small (registration ≈ 0.00023 BNB at 1 gwei).

## Plan to reach ≥30 interacting Agent ID addresses (proposals only)

Eligibility for the Innovation Award — and any Pioneer ranking — needs at
least 30 *distinct Agent ID holder addresses* to transact with the
contract during 2026-11-18 → 2026-12-09. Agent ID claims have passed
200,000 (Binance's own reporting), so the audience exists; this is a
distribution plan, not a technical one. Target 60+ registrations for
margin. Nothing here is executed by the agent; the user approves and
posts from his own accounts.

1. **Seed (day 0–1).** Our own agent registers first (`nerokais.ai` —
   registrant #1, a real card for BOSS NERO's research services). Deploy
   + verify, publish the repo and the frontend (GitHub Pages), so every
   later step links to something live.
2. **Binance Square (day 1 onward).** The hackathon's own community
   surface: an announcement post from the user's Square profile — what
   the directory is, that registration is free (gas only), the contract
   link, and the two hackathon hashtags for the Community Promotion
   track. Follow with a short progress post every few days (registration
   count milestones). Square is where Agent ID holders already follow
   Binance Wallet campaigns.
3. **SPACE ID community (day 1–3).** SPACE ID runs the Agent ID contract
   and its holder community (X, Discord, Telegram). A short introduction
   in the community channels / a reply under SPACE ID's Agent ID posts:
   the directory is built *on* their identity layer, which is the angle
   most likely to earn a reshare.
4. **Agent-economy projects already gating on Agent ID (day 2–7).**
   Dozens of live projects (agent-only mints and services found during
   research — e.g. Flaggies, HIVE Agents, AVE GENESIS) have user bases
   that are 100% Agent ID holders. Proposal: contact 10–15 of them with
   a reciprocal offer — their agent registers a card in the directory;
   we list/endorse them early, giving the endorsement graph visible
   first movers. Their holders are exactly our target registrants.
5. **Fellow hackathon teams (day 2–10).** Every other team in this
   hackathon holds Agent IDs and needs interactions for the same
   eligibility bar. A "register each other's agents" norm among
   participants is mutually beneficial and organic; propose it in
   hackathon discussion channels.
6. **Agent communities on X (throughout).** Posts from the user's X
   account (@nerokais) in the agent-builder conversation: build-in-public
   updates (test count, gas cost, registration milestones), always with
   the live directory link. Drafts can be prepared by the agent; posting
   is the user's, from his phone, per standing rules.
7. **Conversion hygiene.** The ask is deliberately tiny: one transaction,
   ~0.0002 BNB of gas, no approvals, no token, erasable any time. Every
   outreach message should say exactly that — it is the strongest
   argument for a holder to bother.

Realistic funnel: steps 3–5 are the highest-yield (pre-qualified Agent ID
holders). Even a 1% response from one mid-size project's holder base
clears the 30-address bar; the plan aims at several channels in parallel
so no single one has to carry it.

## Open design questions (for parent / user)

1. **Declared-name verification.** v1 trusts the self-declared `.ai`
   name (see interface findings). Acceptable for v1; revisit if a
   resolution path is confirmed.
2. **Category taxonomy.** Free-text (≤32 bytes) chosen for v1 simplicity
   and flexibility; a fixed list would make browsing cleaner but needs a
   contract change later (no admin functions exist by design).
3. **No un-endorse.** Deliberately omitted to keep the contract minimal;
   endorsements are historical. Revisit only if users ask.
4. **Frontend hosting.** GitHub Pages (matches the user's existing
   FadliAR pattern) is the assumed target; any static host works.
5. **Submission channel.** The announcement lists what to submit but the
   exact form/link is still being pinned down by the parent agent.
