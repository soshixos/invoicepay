// InvoicePay — frontend logic (ethers v6, no build step)
// Read-only by default via the public Aevum RPC; wallet needed only to
// create / pay / cancel invoices.
"use strict";

// Human-readable ABI (ethers v6). Keep in sync with src/InvoicePayments.sol.
const INVOICE_ABI = [
  "function createInvoice(address payer, uint256 amount, uint256 dueDate, string memo) returns (uint256)",
  "function payInvoice(uint256 id)",
  "function cancelInvoice(uint256 id)",
  "function getInvoice(uint256 id) view returns (tuple(uint256 id, address payee, address payer, uint256 amount, uint256 dueDate, string memo, uint8 status, uint256 createdAt, uint256 paidAt, address paidBy))",
  "function getInvoices(uint256 offset, uint256 limit) view returns (tuple(uint256 id, address payee, address payer, uint256 amount, uint256 dueDate, string memo, uint8 status, uint256 createdAt, uint256 paidAt, address paidBy)[])",
  "function invoiceCount() view returns (uint256)",
  "function isOverdue(uint256 id) view returns (bool)",
  "function token() view returns (address)",
  "event InvoiceCreated(uint256 indexed id, address indexed payee, address indexed payer, uint256 amount, uint256 dueDate, string memo)",
  "event InvoicePaid(uint256 indexed id, address indexed paidBy, uint256 amount, uint256 paidAt)",
  "event InvoiceCancelled(uint256 indexed id, address indexed cancelledBy)",
];
const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
];

const ZERO = "0x0000000000000000000000000000000000000000";
const STATUS = ["Pending", "Paid", "Cancelled"];

let readProvider = null;
let signer = null;
let account = null;
let readContract = null;
let writeContract = null;
let tokenRead = null;
let tokenWrite = null;
let deployed = false;

// ---------- helpers ----------
const $ = (id) => document.getElementById(id);

function shortAddr(a) {
  return a ? a.slice(0, 6) + "…" + a.slice(-4) : "–";
}

function fmtAmount(baseUnits) {
  // tUSD8 has 6 decimals.
  return (Number(baseUnits) / 1e6).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 6,
  });
}

function toBaseUnits(amountStr) {
  // Parse a decimal string into 6-decimal base units without float error.
  const [whole, frac = ""] = String(amountStr).trim().split(".");
  const frac6 = (frac + "000000").slice(0, 6);
  return BigInt(whole || "0") * 1000000n + BigInt(frac6 || "0");
}

function fmtDate(ts) {
  if (!ts || Number(ts) === 0) return "No due date";
  return new Date(Number(ts) * 1000).toLocaleString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function explorerTx(hash) {
  return `${CONFIG.explorerUrl}/tx/${hash}`;
}
function explorerAddr(addr) {
  return `${CONFIG.explorerUrl}/address/${addr}`;
}

function setStatus(msg, kind = "") {
  const bar = $("statusBar");
  bar.textContent = msg;
  bar.className = "statusbar" + (kind ? " " + kind : "");
}

function setBusy(busy, label) {
  document.querySelectorAll("button").forEach((b) => (b.disabled = busy));
  if (label) setStatus(label);
}

// ---------- init ----------
async function init() {
  $("tokenLink").href = explorerAddr(CONFIG.tokenAddress);
  $("tokenLink").textContent = shortAddr(CONFIG.tokenAddress);
  deployed = CONFIG.contractAddress.toLowerCase() !== ZERO;
  if (deployed) {
    $("contractLink").href = explorerAddr(CONFIG.contractAddress);
    $("contractLink").textContent = shortAddr(CONFIG.contractAddress);
  } else {
    $("deployNotice").classList.remove("hidden");
    $("invoiceList").innerHTML =
      '<p class="empty">No contract deployed yet — the invoice list will appear once the contract address is set in <code>config.js</code>.</p>';
    setStatus("Preview mode: contract not deployed yet.", "warn");
    return;
  }

  readProvider = new ethers.JsonRpcProvider(CONFIG.rpcUrl);
  readContract = new ethers.Contract(CONFIG.contractAddress, INVOICE_ABI, readProvider);
  tokenRead = new ethers.Contract(CONFIG.tokenAddress, ERC20_ABI, readProvider);

  if (window.ethereum) {
    // Reconnect silently if the user previously connected.
    try {
      const accounts = await window.ethereum.request({ method: "eth_accounts" });
      if (accounts && accounts.length > 0) await connectWallet(true);
    } catch (e) {
      /* ignore — user can connect manually */
    }
    window.ethereum.on("accountsChanged", () => window.location.reload());
    window.ethereum.on("chainChanged", () => window.location.reload());
  }

  await loadInvoices();
}

// ---------- wallet ----------
async function connectWallet(silent = false) {
  if (!window.ethereum) {
    if (!silent) setStatus("No wallet found. Install MetaMask (or any EIP-3085 wallet) to transact.", "error");
    return;
  }
  try {
    const browserProvider = new ethers.BrowserProvider(window.ethereum);
    await browserProvider.send("eth_requestAccounts", []);
    const network = await browserProvider.getNetwork();
    if (Number(network.chainId) !== CONFIG.chainId) {
      try {
        await window.ethereum.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: CONFIG.chainIdHex }],
        });
      } catch (switchErr) {
        if (switchErr.code === 4902) {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [
              {
                chainId: CONFIG.chainIdHex,
                chainName: CONFIG.chainName,
                nativeCurrency: CONFIG.nativeCurrency,
                rpcUrls: [CONFIG.rpcUrl],
                blockExplorerUrls: [CONFIG.explorerUrl],
              },
            ],
          });
        } else {
          throw switchErr;
        }
      }
    }
    signer = await browserProvider.getSigner();
    account = await signer.getAddress();
    writeContract = new ethers.Contract(CONFIG.contractAddress, INVOICE_ABI, signer);
    tokenWrite = new ethers.Contract(CONFIG.tokenAddress, ERC20_ABI, signer);

    $("connectBtn").textContent = shortAddr(account);
    $("connectBtn").disabled = true;
    $("createBtn").disabled = false;
    $("createBtn").textContent = "Create invoice";
    $("walletInfo").classList.remove("hidden");
    $("walletAddr").textContent = shortAddr(account);
    setStatus(`Connected as ${shortAddr(account)} on ${CONFIG.chainName}.`, "ok");
    await loadBalances();
    await loadInvoices();
  } catch (e) {
    if (!silent) setStatus(`Could not connect wallet: ${e.message || e}`, "error");
  }
}

async function loadBalances() {
  if (!account || !tokenRead) return;
  try {
    const [tus, gas] = await Promise.all([
      tokenRead.balanceOf(account),
      readProvider.getBalance(account),
    ]);
    $("tusdbalance").textContent = `${fmtAmount(tus)} tUSD8`;
    $("gasbalance").textContent = `${ethers.formatEther(gas)} tQDAY`;
  } catch (e) {
    /* balances are best-effort */
  }
}

// ---------- invoices ----------
async function loadInvoices() {
  if (!readContract) return;
  try {
    const count = Number(await readContract.invoiceCount());
    let invoices = [];
    const PAGE = 50;
    for (let offset = 0; offset < count; offset += PAGE) {
      const page = await readContract.getInvoices(offset, Math.min(PAGE, count - offset));
      invoices = invoices.concat(page);
    }
    // Newest first.
    invoices.reverse();
    renderStats(invoices);
    renderInvoices(invoices);
  } catch (e) {
    $("invoiceList").innerHTML = `<p class="empty">Could not load invoices: ${e.message || e}</p>`;
    setStatus(`Failed to load invoices: ${e.message || e}`, "error");
  }
}

function renderStats(invoices) {
  const pending = invoices.filter((i) => i.status === 0n || i.status === 0);
  const paid = invoices.filter((i) => Number(i.status) === 1);
  const volume = paid.reduce((sum, i) => sum + i.amount, 0n);
  $("statTotal").textContent = invoices.length;
  $("statPending").textContent = pending.length;
  $("statPaid").textContent = paid.length;
  $("statVolume").textContent = fmtAmount(volume);
}

function statusBadge(inv, overdue) {
  if (Number(inv.status) === 1) return '<span class="pill paid">Paid</span>';
  if (Number(inv.status) === 2) return '<span class="pill cancelled">Cancelled</span>';
  if (overdue) return '<span class="pill overdue">Overdue</span>';
  return '<span class="pill pending">Pending</span>';
}

async function renderInvoices(invoices) {
  const list = $("invoiceList");
  if (invoices.length === 0) {
    list.innerHTML =
      '<p class="empty">No invoices yet. Connect a wallet and create the first one.</p>';
    return;
  }
  const rows = [];
  for (const inv of invoices) {
    let overdue = false;
    try {
      overdue = await readContract.isOverdue(inv.id);
    } catch (e) {
      /* ignore */
    }
    const isPayee = account && inv.payee.toLowerCase() === account.toLowerCase();
    const isPayer =
      account &&
      (inv.payer === ZERO ||
        inv.payer.toLowerCase() === account.toLowerCase());
    const canPay = Number(inv.status) === 0 && isPayer;
    const canCancel = Number(inv.status) === 0 && isPayee;
    rows.push(`
      <article class="invoice">
        <div class="inv-main">
          <div class="inv-title">
            <strong>#${inv.id} — ${escapeHtml(inv.memo || "(no memo)")}</strong>
            ${statusBadge(inv, overdue)}
          </div>
          <div class="inv-meta">
            <span>Payee <a href="${explorerAddr(inv.payee)}" target="_blank" rel="noopener">${shortAddr(inv.payee)}</a>${isPayee ? " (you)" : ""}</span>
            <span>Payer ${inv.payer === ZERO ? "anyone (open invoice)" : `<a href="${explorerAddr(inv.payer)}" target="_blank" rel="noopener">${shortAddr(inv.payer)}</a>${isPayer ? " (you)" : ""}`}</span>
            <span>Due: ${fmtDate(inv.dueDate)}${overdue ? " — overdue" : ""}</span>
            <span>Created: ${fmtDate(inv.createdAt)}</span>
            ${Number(inv.status) === 1 ? `<span>Paid by <a href="${explorerAddr(inv.paidBy)}" target="_blank" rel="noopener">${shortAddr(inv.paidBy)}</a> on ${fmtDate(inv.paidAt)}</span>` : ""}
          </div>
        </div>
        <div class="inv-side">
          <div class="inv-amount">${fmtAmount(inv.amount)} <span>tUSD8</span></div>
          <div class="inv-actions">
            <button class="btn primary small" data-pay="${inv.id}" ${canPay ? "" : "disabled"}>Pay</button>
            <button class="btn ghost small" data-cancel="${inv.id}" ${canCancel ? "" : "disabled"}>Cancel</button>
          </div>
        </div>
      </article>`);
  }
  list.innerHTML = rows.join("");
  list.querySelectorAll("[data-pay]").forEach((b) =>
    b.addEventListener("click", () => payInvoice(BigInt(b.dataset.pay)))
  );
  list.querySelectorAll("[data-cancel]").forEach((b) =>
    b.addEventListener("click", () => cancelInvoice(BigInt(b.dataset.cancel)))
  );
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[c]);
}

// ---------- actions ----------
async function createInvoice(e) {
  e.preventDefault();
  if (!writeContract || !account) {
    setStatus("Connect your wallet first.", "error");
    return;
  }
  const payerRaw = $("payerInput").value.trim();
  const amountRaw = $("amountInput").value.trim();
  const dueRaw = $("dueInput").value;
  const memo = $("memoInput").value.trim();
  if (!amountRaw || Number(amountRaw) <= 0) {
    setStatus("Enter an amount greater than 0.", "error");
    return;
  }
  if (!memo) {
    setStatus("Enter a memo describing the invoice.", "error");
    return;
  }
  let payer = ZERO;
  if (payerRaw) {
    if (!ethers.isAddress(payerRaw)) {
      setStatus("Payer address is not a valid address.", "error");
      return;
    }
    payer = payerRaw;
  }
  const amount = toBaseUnits(amountRaw);
  const dueDate = dueRaw ? Math.floor(new Date(dueRaw).getTime() / 1000) : 0;
  if (dueDate !== 0 && dueDate * 1000 <= Date.now()) {
    setStatus("Due date must be in the future.", "error");
    return;
  }
  try {
    setBusy(true, "Creating invoice… confirm in your wallet.");
    const tx = await writeContract.createInvoice(payer, amount, dueDate, memo);
    setStatus(`Invoice submitted: ${tx.hash} — waiting for confirmation…`);
    const receipt = await tx.wait();
    setStatus(`Invoice created! Tx ${tx.hash} (block ${receipt.blockNumber}).`, "ok");
    $("createForm").reset();
    await loadBalances();
    await loadInvoices();
  } catch (err) {
    setStatus(`Could not create invoice: ${err.reason || err.message || err}`, "error");
  } finally {
    setBusy(false);
    $("createBtn").disabled = false;
    $("connectBtn").disabled = true;
  }
}

async function payInvoice(id) {
  if (!writeContract || !account) {
    setStatus("Connect your wallet first.", "error");
    return;
  }
  try {
    const inv = await readContract.getInvoice(id);
    const amount = inv.amount;
    setBusy(true, `Paying invoice #${id}…`);
    const allowance = await tokenRead.allowance(account, CONFIG.contractAddress);
    if (allowance < amount) {
      setStatus(`Approving ${fmtAmount(amount)} tUSD8… confirm in your wallet.`);
      const approveTx = await tokenWrite.approve(CONFIG.contractAddress, amount);
      await approveTx.wait();
      setStatus(`Approved. Now paying invoice #${id}… confirm in your wallet.`);
    }
    const tx = await writeContract.payInvoice(id);
    setStatus(`Payment submitted: ${tx.hash} — waiting for confirmation…`);
    const receipt = await tx.wait();
    setStatus(
      `Invoice #${id} paid! ${fmtAmount(amount)} tUSD8 sent to ${shortAddr(inv.payee)}. Tx ${tx.hash} (block ${receipt.blockNumber}).`,
      "ok"
    );
    await loadBalances();
    await loadInvoices();
  } catch (err) {
    setStatus(`Could not pay invoice: ${err.reason || err.message || err}`, "error");
  } finally {
    setBusy(false);
  }
}

async function cancelInvoice(id) {
  if (!writeContract || !account) {
    setStatus("Connect your wallet first.", "error");
    return;
  }
  try {
    setBusy(true, `Cancelling invoice #${id}… confirm in your wallet.`);
    const tx = await writeContract.cancelInvoice(id);
    await tx.wait();
    setStatus(`Invoice #${id} cancelled.`, "ok");
    await loadInvoices();
  } catch (err) {
    setStatus(`Could not cancel invoice: ${err.reason || err.message || err}`, "error");
  } finally {
    setBusy(false);
  }
}

// ---------- wire up ----------
$("connectBtn").addEventListener("click", () => connectWallet(false));
$("refreshBtn").addEventListener("click", () => loadInvoices());
$("createForm").addEventListener("submit", createInvoice);

init();
