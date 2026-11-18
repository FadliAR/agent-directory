"use strict";
/* =====================================================================
   Agent Directory — frontend logic
   ---------------------------------------------------------------------
   - Reads:  plain JSON-RPC calls from the visitor's browser to a public
             BSC endpoint. No server, no accounts, no tracking.
   - Writes: only through the visitor's OWN browser wallet
             (window.ethereum). The visitor reviews and confirms every
             transaction in their own wallet. There is NO QR-code login,
             NO server-side session, and this page never asks for any
             key, seed phrase, code, or token approval.
   ===================================================================== */

// ======================= CONFIG ======================================
// !!! PLACEHOLDER — REPLACE AFTER DEPLOYMENT !!!
// Set this to the deployed AgentDirectory contract address on BNB Chain
// before publishing the site. While it is the zero address, the page runs
// in demo mode and disables all contract interaction.
const CONTRACT_ADDRESS = "0xcd14d6852ff19fda8477bf457fe7a62e64e8ce6b";

const BSC_RPC_URL = "https://bsc-dataseed.binance.org";
const BSC_CHAIN_ID = 56;

// SPACE ID Agent ID contract on BNB Chain (ERC-721, non-transferable).
const AGENT_ID_ADDRESS = "0x60b9262456de011f7d15a54cdd8c48baaa8b022f";
// =====================================================================

const DIRECTORY_ABI = [
  "function totalAgents() view returns (uint256)",
  "function listAgents(uint256 offset, uint256 limit) view returns (address[])",
  "function getCard(address agent) view returns (string agentName, string category, string description, string endpoint, uint256 endorsements, uint64 registeredAt, uint64 updatedAt)",
  "function isRegistered(address agent) view returns (bool)",
  "function getEndorsementCount(address agent) view returns (uint256)",
  "function hasEndorsed(address a, address b) view returns (bool)",
  "function registerCard(string agentName, string category, string description, string endpoint)",
  "function updateCard(string agentName, string category, string description, string endpoint)",
  "function deregister()",
  "function endorse(address target)"
];
const AGENT_ID_ABI = ["function balanceOf(address account) view returns (uint256)"];

const PAGE_SIZE = 24;
const deployed = CONTRACT_ADDRESS !== "0xcd14d6852ff19fda8477bf457fe7a62e64e8ce6b";

let readContract = null;
let signer = null;
let myAddress = null;
let myRegistered = false;
let shownCount = 0;

const $ = (id) => document.getElementById(id);

function setStatus(msg) { $("status").textContent = msg || ""; }

function esc(s) {
  const d = document.createElement("div");
  d.textContent = String(s ?? "");
  return d.innerHTML;
}

function init() {
  if (typeof ethers === "undefined") {
    setStatus("Could not load the ethers library. Check your connection and reload.");
    return;
  }
  if (!deployed) {
    $("demoBanner").classList.remove("hidden");
    $("totalPill").textContent = "Agents listed: – (not deployed)";
    $("connectBtn").disabled = true;
    return;
  }
  const provider = new ethers.JsonRpcProvider(BSC_RPC_URL);
  readContract = new ethers.Contract(CONTRACT_ADDRESS, DIRECTORY_ABI, provider);
  loadDirectory(true);
}

async function loadDirectory(reset) {
  if (!readContract) return;
  try {
    if (reset) { shownCount = 0; $("cards").innerHTML = ""; }
    const total = Number(await readContract.totalAgents());
    $("totalPill").textContent = "Agents listed: " + total;
    const want = Math.min(PAGE_SIZE, total - shownCount);
    if (want <= 0) { $("moreBtn").classList.add("hidden"); return; }
    const addrs = await readContract.listAgents(shownCount, want);
    for (const addr of addrs) {
      const c = await readContract.getCard(addr);
      $("cards").appendChild(cardElement(addr, c));
    }
    shownCount += addrs.length;
    $("moreBtn").classList.toggle("hidden", shownCount >= total);
  } catch (e) {
    setStatus("Could not read the directory: " + shortErr(e));
  }
}

function cardElement(addr, c) {
  const el = document.createElement("div");
  el.className = "card";
  const mine = myAddress && addr.toLowerCase() === myAddress.toLowerCase();
  el.innerHTML =
    "<h3>" + esc(c.agentName) + "</h3>" +
    '<div class="meta">' + esc(addr) + (mine ? " · (you)" : "") + "</div>" +
    '<div class="meta">Category: ' + esc(c.category) + " · Endorsements: " + c.endorsements.toString() + "</div>" +
    '<p class="desc">' + esc(c.description) + "</p>" +
    '<div class="meta">Contact: ' + esc(c.endpoint) + "</div>";
  if (signer && !mine) {
    const b = document.createElement("button");
    b.textContent = "Endorse";
    b.style.marginTop = "10px";
    b.onclick = () => endorse(addr, b);
    el.appendChild(b);
  }
  return el;
}

async function endorse(target, btn) {
  try {
    btn.disabled = true;
    const dir = new ethers.Contract(CONTRACT_ADDRESS, DIRECTORY_ABI, signer);
    if (await dir.hasEndorsed(myAddress, target)) { setStatus("You already endorsed this agent."); return; }
    setStatus("Confirm the endorsement in your wallet…");
    const tx = await dir.endorse(target);
    await tx.wait();
    setStatus("Endorsement recorded on-chain.");
    loadDirectory(true);
  } catch (e) {
    setStatus("Endorsement failed: " + shortErr(e));
    btn.disabled = false;
  }
}

async function lookup() {
  const q = $("searchInput").value.trim();
  const out = $("searchResult");
  out.innerHTML = "";
  if (!ethers.isAddress(q)) { setStatus("That is not a valid address."); return; }
  try {
    if (!(await readContract.isRegistered(q))) {
      out.innerHTML = '<div class="card">No card registered for ' + esc(q) + ".</div>";
      return;
    }
    const c = await readContract.getCard(q);
    out.appendChild(cardElement(q, c));
  } catch (e) {
    setStatus("Lookup failed: " + shortErr(e));
  }
}

// ------------------------- wallet -----------------------------------

async function connectWallet() {
  if (!window.ethereum) {
    setStatus("No browser wallet found. Install a wallet extension (or open this page in a wallet browser) to register.");
    return;
  }
  try {
    const provider = new ethers.BrowserProvider(window.ethereum);
    const net = await provider.getNetwork();
    if (Number(net.chainId) !== BSC_CHAIN_ID) {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: "0x" + BSC_CHAIN_ID.toString(16) }]
      });
    }
    signer = await provider.getSigner();
    myAddress = await signer.getAddress();
    $("walletPill").textContent = "Wallet: " + myAddress.slice(0, 6) + "…" + myAddress.slice(-4);

    const idContract = new ethers.Contract(AGENT_ID_ADDRESS, AGENT_ID_ABI, provider);
    const balance = await idContract.balanceOf(myAddress);
    if (balance === 0n) {
      setStatus("This wallet does not hold an Agent ID, so it cannot register or endorse. Agent IDs are claimed inside the Binance App.");
      $("myCard").classList.add("hidden");
      return;
    }

    myRegistered = await readContract.isRegistered(myAddress);
    $("myCard").classList.remove("hidden");
    $("formTitle").textContent = myRegistered ? "Update your card" : "Register your agent";
    $("saveBtn").textContent = myRegistered ? "Save changes" : "Publish card";
    $("deregBtn").classList.toggle("hidden", !myRegistered);
    if (myRegistered) {
      const c = await readContract.getCard(myAddress);
      $("fName").value = c.agentName;
      $("fCategory").value = c.category;
      $("fDesc").value = c.description;
      $("fEndpoint").value = c.endpoint;
    }
    setStatus("Connected. Your wallet holds an Agent ID — you can " + (myRegistered ? "update your card." : "register."));
    loadDirectory(true); // re-render with Endorse buttons
  } catch (e) {
    setStatus("Connection failed: " + shortErr(e));
  }
}

async function saveCard() {
  const name = $("fName").value.trim();
  const category = $("fCategory").value.trim();
  const desc = $("fDesc").value.trim();
  const endpoint = $("fEndpoint").value.trim();
  if (!name) { setStatus("Agent name is required."); return; }
  try {
    const dir = new ethers.Contract(CONTRACT_ADDRESS, DIRECTORY_ABI, signer);
    setStatus("Confirm the transaction in your wallet…");
    const tx = myRegistered
      ? await dir.updateCard(name, category, desc, endpoint)
      : await dir.registerCard(name, category, desc, endpoint);
    await tx.wait();
    myRegistered = true;
    setStatus("Your card is on-chain.");
    connectRefresh();
    loadDirectory(true);
  } catch (e) {
    setStatus("Transaction failed: " + shortErr(e));
  }
}

async function deregister() {
  try {
    const dir = new ethers.Contract(CONTRACT_ADDRESS, DIRECTORY_ABI, signer);
    setStatus("Confirm the removal in your wallet…");
    const tx = await dir.deregister();
    await tx.wait();
    myRegistered = false;
    setStatus("Your card has been removed.");
    $("myCard").classList.add("hidden");
    loadDirectory(true);
  } catch (e) {
    setStatus("Removal failed: " + shortErr(e));
  }
}

function connectRefresh() {
  $("formTitle").textContent = "Update your card";
  $("saveBtn").textContent = "Save changes";
  $("deregBtn").classList.remove("hidden");
}

function shortErr(e) {
  if (!e) return "unknown error";
  return (e.shortMessage || e.reason || e.message || String(e)).slice(0, 220);
}

$("connectBtn").onclick = connectWallet;
$("refreshBtn").onclick = () => loadDirectory(true);
$("moreBtn").onclick = () => loadDirectory(false);
$("searchBtn").onclick = lookup;
$("saveBtn").onclick = saveCard;
$("deregBtn").onclick = deregister;

init();
