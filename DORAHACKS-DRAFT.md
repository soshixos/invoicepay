# DoraHacks Submission Draft — InvoicePay
### Aevum Builder Challenge #1 · Invoice Payments track · Solo entry
### (Draft — copy-paste into the DoraHacks submission form. Written in English, as the challenge and judges are international.)

---

## Project name
InvoicePay

## Tagline (one line)
Pay invoices in tUSD8 on Aevum Testnet — no escrow, no middleman, no admin keys.

## Short description (for the project card)
InvoicePay is a minimal, auditable dApp for invoicing in a stablecoin. A freelancer or small business creates an invoice denominated in tUSD8 (the challenge's test stablecoin); the payer approves the contract and pays, and the tokens move straight from payer to payee — no escrow, no middleman, no admin keys. Testnet only: tUSD8 has no monetary value.

## Full description

### The problem
Getting paid in crypto is still awkward for everyday work: you send a wallet address over chat, the client sends the wrong amount (or the wrong token, or nothing at all), and nobody has a record of what was agreed. InvoicePay gives both sides a shared, on-chain record — amount, due date, memo, and payment status — and makes the payment itself a single, verifiable transaction.

### How it works
1. **Create** — The biller (payee) creates an invoice: payer address (or leave it empty for an *open* invoice anyone can pay), amount in tUSD8, optional due date, and a memo describing the work.
2. **Approve** — The payer approves the contract to spend the invoice amount of tUSD8 (one transaction, exact amount).
3. **Pay** — The payer calls `payInvoice`. The contract moves the tUSD8 payer → payee and marks the invoice **Paid** with the payer and timestamp.
4. **Cancel** — The payee can cancel a *Pending* invoice any time before it is paid. A cancelled invoice can never be paid.

Overdue is informational: an invoice past its due date shows as **Overdue** but can still be paid (late payment). There is no admin, no upgrade path, and no way for anyone — including the deployer — to move tokens except by settling an invoice the payer approved.

### Architecture
- **Smart contract** — `src/InvoicePayments.sol` (Solidity 0.8.20, OpenZeppelin `ReentrancyGuard` + `SafeERC20`). Stores invoices, enforces the state machine Pending → Paid / Cancelled, emits events for every action, and exposes paginated reads (`getInvoices`) for the UI.
- **Frontend** — dependency-free static site (`frontend/`). `ethers v6` is vendored, so the demo works with no CDN access. Read-only by default via the public Aevum RPC; MetaMask (or any EIP-3085 wallet) is needed only to create / pay / cancel. The wallet flow adds the Aevum Testnet chain (44005) automatically.
- **Tests** — Foundry suite in `test/` (22 tests, including a reentrancy attack test with a malicious token). `forge test` — all passing.
- **Deployment** — Foundry script in `script/Deploy.s.sol`.

### Safety & trust
- **ReentrancyGuard + checks-effects-interactions** on `payInvoice` (state is set to Paid *before* the token transfer).
- **SafeERC20** for all token movements.
- Funds can only flow **payer → payee of a Pending invoice**, and only up to the invoice amount the payer approved.
- The payee is always the invoice creator (`msg.sender`); nobody can create an invoice that pays a third party.
- No owner, no pause, no upgradeability, no backdoors. The deployer has no special powers after deployment.
- Memo length is capped (500 bytes) to bound gas and keep invoices readable.

### Technologies
Solidity 0.8.20 · Foundry · OpenZeppelin Contracts · ethers v6 · HTML/CSS/JS (no framework) · nginx (Docker) · Aevum Testnet (EVM, chain 44005) · tUSD8 (ERC-20, 6 decimals).

---

## Links (paste these into the form)

- **GitHub repo (public):** https://github.com/soshixos/invoicepay
- **Deployed contract (Aevum Testnet, chain 44005):** https://explorer-test.qday.info/address/0x4d60a00407d5fc38407d7bf2778d028cd4fe924c
- **tUSD8 token:** https://explorer-test.qday.info/address/0x456569838f1d43009A91ebA4263147Afd7233483
- **Challenge page:** https://qday.io/builder-challenge

## Live demo
Run the packaged Docker image (serves the frontend on port 8080):
```
docker build -t invoicepay . && docker run --rm -p 8080:80 invoicepay
# open http://localhost:8080
```
Or serve the static frontend directly: `python3 -m http.server 8080 -d frontend` (the frontend reads from the public Aevum RPC, no wallet needed to browse invoices; connect MetaMask to create/pay).

## Proof it works on Aevum Testnet (real transactions)
End-to-end on the deployed contract, invoice #0 (1 tUSD8, "Test invoice - Aevum E2E") — created, paid, and verified **Paid** via `getInvoice(0)`:
- Deploy: https://explorer-test.qday.info/tx/0x5af89c68a3eee8ac9e6e9f0a17f33f433b8c8ec9ce89a7f1f279c2545b9647b7
- Approve 1 tUSD8: https://explorer-test.qday.info/tx/0x7a013fe6b74c3bda6bd060d8c86d63a13a7fd5ea6f2b2ac6ce3a6221bd076707
- Create invoice #0: https://explorer-test.qday.info/tx/0x45adbc16a9d456b6cfa32dd6b715e0e71398fcbcf4f20ccc81f5ec14a559ceba
- Pay invoice #0: https://explorer-test.qday.info/tx/0xd15dca9553b13b1af7160bdf7730377d97f53c866e542e460c7582705a28dda4

## Demo Day script (3–5 min, if selected for the top 5)
1. Open the demo, connect MetaMask (Aevum Testnet is added automatically).
2. Claim tQDAY + tUSD8 from the faucet (https://faucet.qday.info) if needed.
3. Create an invoice: payer = a second address (or leave empty for an open invoice), amount e.g. `25.00`, memo e.g. `Website redesign — November`.
4. Switch to the payer account, open the invoice, click **Pay** — approve the exact amount, then pay. The invoice flips to **Paid** with the payer and timestamp; the payee's tUSD8 balance increases by the amount.
5. Show the transactions on the Aevum explorer.

## Team
Solo — Yuni Saputra.

---

## Submission checklist (before you hit submit)
- [ ] Repo is public and the link opens (https://github.com/soshixos/invoicepay)
- [ ] Contract address in the form matches the deployed one above
- [ ] Demo instructions work from a clean machine (Docker build tested, or note it as untested)
- [ ] Track selected: **Invoice Payments**
- [ ] Submitted before **Dec 11, 2026 08:00 UTC (15:00 WIB)**
