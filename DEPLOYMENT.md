# Deployment record — InvoicePay

## Aevum Testnet (chain 44005) — ✅ DEPLOYED + E2E VERIFIED (2026-11-16)

| Item | Value |
|---|---|
| Contract | `InvoicePayments` — **deployed at `0x4d60a00407d5fc38407d7bf2778d028cd4fe924c`** |
| Deploy tx | `0x5af89c68a3eee8ac9e6e9f0a17f33f433b8c8ec9ce89a7f1f279c2545b9647b7` (status 1) |
| Settlement token | tUSD8 `0x456569838f1d43009A91ebA4263147Afd7233483` (ERC-20, 6 decimals, verified live) |
| Deployer wallet | `0x0202751956fc9996e313FeEbd67A9431ab96d051` (fresh, testnet-only) |
| Deployer key | `~/workspace/qday/testnet-key.json` (mode 600, **never commit**) |
| RPC | `https://rpc-test.qday.info` (chainId `0xabe5` = 44005, verified) |
| Explorer | `https://explorer-test.qday.info` — contract: `https://explorer-test.qday.info/address/0x4d60a00407d5fc38407d7bf2778d028cd4fe924c` |
| Faucet | `https://faucet.qday.info` — **claimed by the user 2026-11-16 (option A)**; on-chain balance at first check: 0.999910917 tQDAY + 5.0 tUSD8 (documented drips are 5 tQDAY + 1 tUSD8 — observed amounts differ, likely the relay dispenses different amounts than the contracts' `dripAmount()`; either way the deployer was funded and deployment proceeded) |
| Frontend config | `frontend/config.js` `contractAddress` set to the deployed address |

### Deploy command (used)

```bash
PRIVATE_KEY=$(python3 -c "import json; print(json.load(open('$HOME/workspace/qday/testnet-key.json'))['private_key'])") \
  forge script script/Deploy.s.sol --rpc-url https://rpc-test.qday.info --broadcast
# frontend/config.js -> contractAddress set to the deployed address
# verify on https://explorer-test.qday.info/address/<deployed>
```

### MCOPY issue — first deployment superseded (2026-11-16)

The first deployment (`0x0DEF81dbA236181A7c590895d397A7375EBDD019`, tx `0x40414fe5de039a71989e23f97a4f6676db7cd06c94ce151643af0c751c4ed30d`) worked for writes (approve/create/pay all status 1, invoiceCount became 1), but `getInvoice` reverted with `invalid opcode: MCOPY` — Aevum Testnet's EVM does not support the Cancun MCOPY opcode, and the default solc target emitted it in the struct-return path. Fix: `evm_version = "shanghai"` in `foundry.toml` (see the comment there), `forge build --force`, redeploy. The new contract is the canonical one; the old address is abandoned (do not use it in the demo or submission).

### Aevum end-to-end — ✅ VERIFIED on the new contract (2026-11-16)

- Approve 1 tUSD8 to the contract — `0x7a013fe6b74c3bda6bd060d8c86d63a13a7fd5ea6f2b2ac6ce3a6221bd076707`
- Create open invoice #0 (1 tUSD8, "Test invoice - Aevum E2E") — `0x45adbc16a9d456b6cfa32dd6b715e0e71398fcbcf4f20ccc81f5ec14a559ceba`
- Pay invoice #0 — `0xd15dca9553b13b1af7160bdf7730377d97f53c866e542e460c7582705a28dda4`
- `getInvoice(0)` now returns correctly (MCOPY fix confirmed): id 0, payee = deployer, payer = 0x0 (open), amount 1,000,000 (1 tUSD8), dueDate 0, memo "Test invoice - Aevum E2E", **status 1 (Paid)**, createdAt/paidAt set, paidBy = deployer. `invoiceCount` = 1.

### Faucet status — BLOCKED (two independent gates)

The faucet was investigated in depth on 2026-11-16 (read the faucet's own
JS bundle + its `/gasapi/info` endpoint; no browser automation was used).

1. **Cloudflare Turnstile (bot check).** The claim flow loads Turnstile
   (`challenges.cloudflare.com/turnstile`) and the claim POSTs carry a
   `captchaToken`. A `curl`-only claim is not possible; it needs a real
   browser session. **The parent must do this step in a browser task.**
2. **Mainnet-holdings eligibility gate.** `GET /gasapi/eligibility?address=…`
   returns `eligible: false` for a fresh address. From `/gasapi/info`:
   `eligibility: {enabled: true, ethMinWei: "100000000000000",
   stableMinUnits: "1000000"}` — the claiming address must already hold
   **≥ 0.0001 ETH on Ethereum mainnet** (or ≥ 1 unit of a stablecoin there).
   Verified: vitalik.eth (5.8 ETH) → eligible; the ecrecover precompile
   (57 ETH) → eligible; three fresh addresses (0 ETH) → ineligible.
   **The fresh testnet-only deployer wallet holds 0 ETH on mainnet, so it
   will fail this check even in a browser.**

**What unblocks it (parent/user decision):**

- **Option A (recommended):** the user connects *their own* EVM wallet —
  one that already holds ≥ 0.0001 ETH on mainnet — to
  https://faucet.qday.info in a browser, solves the Turnstile check, claims
  5 tQDAY (gas) + 1 tUSD8, then sends them to the deployer address
  `0x0202751956fc9996e313FeEbd67A9431ab96d051`. (Only testnet tokens move;
  the mainnet ETH is never spent — it is only an eligibility proof.)
- **Option B:** fund the deployer address with 0.0001 ETH on mainnet
  (~$0.30–0.40) so it passes the gate, then claim in the browser. This
  spends real money — needs the user's explicit approval (user said to skip
  paid items).
- **Option C:** ask in the QDay Discord whether there is another way to get
  testnet gas (e.g. a Discord faucet).

Faucet contract details (for reference):
- Gas faucet `0x33d19Bde2e1798c13808f17BfBa1780b28e4bACC` — holds 715 tQDAY,
  `dripAmount()` = 5 tQDAY, `cooldown()` = 86400 s, `paused()` = false.
  `claim(address)` dispenses tQDAY only; the contract holds **0 tUSD8**.
- tUSD8 faucet `0x4551B2a3dE4F43e6613E23edf798Ab4FB0211564` — holds
  ~298,446 tUSD8, `dripAmount()` = 1,000,000 (1.0 tUSD8), `paused()` = false.
- Both claims go through the relay backend (`claimRelay: true`), which is
  what enforces Turnstile + eligibility.

## Local verification (Anvil, chain 31337) — ✅ DONE

The full flow was proven end-to-end on a local Anvil node on 2026-11-16:

| Item | Value |
|---|---|
| MockToken (mock tUSD8) | `0x5FbDB2315678afecb367f032d93F642f64180aa3` |
| InvoicePayments | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` |
| Deployer (Anvil #0) | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` |

End-to-end (cast):
- Mint 1,000 mock tUSD8 to payer —
  `0x1cb8c1e8c76f1c4f23aecfd2f22cbd6c41296dd6b3e7d0f158402dd94b3bf8dd`
- Payer approves 25 tUSD8 —
  `0x9b54463c95945362c3d94fcee9c239d668a1b60a7b0ce165449110962037e87e`
- Payee creates invoice #0 (25 tUSD8, due +7d, "Website redesign") —
  `0xa0822597ee79a98c0f3ffcb29351eadb91125ee2f8d8202484436c0e1b20f5f9`
- Payer pays invoice #0 —
  `0xe35eca011f67821000b79586c5399c99042c10a5d5d48b641276a44b8fab0559`
- Verified on-chain: invoice #0 status **Paid**, payee +25 tUSD8
  (balance 25,000,000), payer −25 tUSD8 (balance 975,000,000).

Node/ethers E2E (same calls as the frontend) also passed: open-invoice
create → approve → pay (invoice #1, 10 tUSD8, paid by a third account),
cancel flow (invoice #2 cancelled; paying it reverts). See `frontend/`
smoke test below.

## Tests

- `forge test` — **24 passed, 0 failed** (22 InvoicePayments tests + 2
  scaffold tests, since removed). Covers create/pay/cancel, access control,
  overdue, pagination, insufficient allowance/balance, and a reentrancy
  attack with a malicious token.
- Frontend smoke test (Playwright, headless Chromium, Anvil backend) —
  **PASS, 0 JS errors**: invoice #0 renders as Paid with correct amounts;
  stats 1 total / 0 pending / 1 paid / 25.00 tUSD8 settled. Desktop +
  mobile screenshots verified.

## Docker

`Dockerfile` serves `frontend/` with nginx:alpine (self-contained — ethers
is vendored, no CDN needed at runtime).

```bash
docker build -t invoicepay . && docker run --rm -p 8080:80 invoicepay
# open http://localhost:8080
```

Docker image build/test status: see the parent report — Docker was not
available in the build VM at build time (see "Known gaps").

## Known gaps / what is left

1. **Aevum deployment** — ✅ DONE 2026-11-16 (see above). The faucet was claimed by the user (option A); the first deployment was superseded by the MCOPY/Shanghai fix; the canonical contract is `0x4d60a00407d5fc38407d7bf2778d028cd4fe924c`.
2. **Aevum end-to-end** — ✅ DONE 2026-11-16 (see above): create → approve → pay → `getInvoice` verifies Paid, with real explorer tx links.
3. **Docker image test** — `docker build`/`docker run` could not be run in the build VM (no Docker daemon). The Dockerfile is the standard nginx:alpine static pattern; verify with `docker build -t invoicepay .` on a machine with Docker before submitting.
4. **GitHub repo + DoraHacks** — intentionally NOT done by this build: the parent creates the repo (browser task) and the user registers/submits on their own DoraHacks account.
