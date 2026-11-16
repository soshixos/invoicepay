# InvoicePay — pay invoices in tUSD8 on the QDay Aevum Testnet

**Aevum Builder Challenge #1 · Invoice Payments track · Solo entry**

InvoicePay is a minimal, auditable dApp for invoicing in a stablecoin. A
freelancer or small business creates an invoice denominated in **tUSD8**
(the challenge's test stablecoin); the payer approves the contract and pays,
and the tokens move straight from payer to payee — no escrow, no middleman,
no admin keys. Testnet only: tUSD8 has no monetary value.

- **Live demo:** run the Docker image (`docker run --rm -p 8080:80 invoicepay`)
  or open `frontend/index.html` via any static server.
- **Contract:** `src/InvoicePayments.sol` — deployed address in
  [`DEPLOYMENT.md`](DEPLOYMENT.md) (Aevum Testnet, chain 44005).
- **Challenge:** [Aevum Builder Challenge #1](https://qday.io/builder-challenge)
  — build Nov 16 – Dec 11, 2026; submissions close Dec 11, 08:00 UTC.

## The problem

Getting paid in crypto is still awkward for everyday work: you send a wallet
address over chat, the client sends the wrong amount (or the wrong token, or
nothing at all), and nobody has a record of what was agreed. InvoicePay
gives both sides a shared, on-chain record — amount, due date, memo, and
payment status — and makes the payment itself a single, verifiable
transaction.

## How it works

1. **Create** — The biller (payee) creates an invoice: payer address (or
   leave it empty for an *open* invoice anyone can pay), amount in tUSD8,
   optional due date, and a memo describing the work.
2. **Approve** — The payer approves the contract to spend the invoice amount
   of tUSD8 (one transaction, exact amount).
3. **Pay** — The payer calls `payInvoice`. The contract moves the tUSD8
   payer → payee and marks the invoice **Paid** with the payer and timestamp.
4. **Cancel** — The payee can cancel a *Pending* invoice any time before it
   is paid. A cancelled invoice can never be paid.

Overdue is informational: an invoice past its due date shows as **Overdue**
but can still be paid (late payment). There is no admin, no upgrade path,
and no way for anyone — including the deployer — to move tokens except by
settling an invoice the payer approved.

## Architecture

```
┌─────────────────────┐      ┌──────────────────────┐      ┌──────────────────┐
│  frontend/ (static) │      │  InvoicePayments.sol │      │  tUSD8 (ERC-20)  │
│  index.html + app.js│ ───▶ │  Aevum Testnet       │ ───▶ │  0x4565…3483     │
│  ethers v6 (vendored)│ read │  create / pay /      │      │  6 decimals      │
│  MetaMask / EIP-3085│ write│  cancel / views      │      │  faucet-claimed  │
└─────────────────────┘      └──────────────────────┘      └──────────────────┘
```

- **Smart contract** — `src/InvoicePayments.sol` (Solidity 0.8.20,
  OpenZeppelin `ReentrancyGuard` + `SafeERC20`). Stores invoices, enforces
  the state machine Pending → Paid / Cancelled, emits events for every
  action, and exposes paginated reads (`getInvoices`) for the UI.
- **Frontend** — dependency-free static site (`frontend/`). `ethers v6` is
  vendored under `frontend/vendor/`, so the demo works with no CDN access.
  Read-only by default via the public Aevum RPC; MetaMask (or any EIP-3085
  wallet) is needed only to create / pay / cancel. The wallet flow adds the
  Aevum Testnet chain (44005) automatically.
- **Tests** — Foundry suite in `test/` (22 tests, incl. a reentrancy
  attack test with a malicious token). `forge test` — all passing.
- **Deployment** — Foundry script in `script/Deploy.s.sol`. See
  [`DEPLOYMENT.md`](DEPLOYMENT.md).

## Safety

- **ReentrancyGuard + checks-effects-interactions** on `payInvoice`
  (state is set to Paid *before* the token transfer).
- **SafeERC20** for all token movements.
- Funds can only flow **payer → payee of a Pending invoice**, and only up
  to the invoice amount the payer approved.
- The payee is always the invoice creator (`msg.sender`); nobody can create
  an invoice that pays a third party.
- No owner, no pause, no upgradeability, no backdoors. The deployer has no
  special powers after deployment.
- Memo length is capped (500 bytes) to bound gas and keep invoices readable.

## Project layout

```
.
├── src/
│   ├── InvoicePayments.sol   # the invoice contract
│   └── MockToken.sol         # 6-decimal ERC-20 mock (tests + local demo only)
├── test/
│   └── InvoicePayments.t.sol # 22 Foundry tests
├── script/
│   └── Deploy.s.sol          # deploy to Aevum (tUSD8) or Anvil (mock token)
├── frontend/
│   ├── index.html            # demo UI
│   ├── app.js                # dApp logic (ethers v6)
│   ├── styles.css
│   ├── config.js             # network + contract addresses (edit after deploy)
│   └── vendor/ethers.umd.min.js
├── Dockerfile                # nginx serving the frontend
├── README.md
└── DEPLOYMENT.md             # addresses, tx hashes, faucet status
```

## Run it locally

**Prerequisites:** [Foundry](https://book.getfoundry.sh/) (`forge`, `cast`,
`anvil`) for the contract; Docker for the packaged demo; any static server
for the frontend.

```bash
# 1. Tests (no network needed)
forge test

# 2. Local demo chain + deploy (uses a mock tUSD8)
anvil --port 8545 --chain-id 31337        # terminal 1
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --start-fresh
# ^ Anvil's default account #0 key. Local only — never use on a live network.

# 3. Frontend (point config.js at the local deployment first)
docker build -t invoicepay . && docker run --rm -p 8080:80 invoicepay
# or: python3 -m http.server 8080 -d frontend
# open http://localhost:8080
```

**Deploy to Aevum Testnet** (needs tQDAY for gas + tUSD8 — see
[`DEPLOYMENT.md`](DEPLOYMENT.md) for the faucet status):

```bash
# PRIVATE_KEY = the testnet-only deployer key (never commit it)
PRIVATE_KEY=<key> forge script script/Deploy.s.sol \
  --rpc-url https://rpc-test.qday.info --broadcast
# then set frontend/config.js contractAddress to the deployed address
```

## Demo script (for Demo Day)

1. Open the demo, connect MetaMask (Aevum Testnet is added automatically).
2. Claim tQDAY + tUSD8 from the [faucet](https://faucet.qday.info) if needed.
3. Create an invoice: payer = a second address (or leave empty for an open
   invoice), amount e.g. `25.00`, memo e.g. `Website redesign — November`.
4. Switch to the payer account, open the invoice, click **Pay** — approve
   the exact amount, then pay. The invoice flips to **Paid** with the payer
   and timestamp; the payee's tUSD8 balance increases by the amount.
5. Show the transactions on the
   [Aevum explorer](https://explorer-test.qday.info).

## Technologies

Solidity 0.8.20 · Foundry · OpenZeppelin Contracts · ethers v6 · HTML/CSS/JS
(no framework) · nginx (Docker) · Aevum Testnet (EVM, chain 44005) · tUSD8
(ERC-20, 6 decimals).

## License

MIT — see [LICENSE](LICENSE).
