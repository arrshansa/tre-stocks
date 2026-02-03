// Base URL for API Gateway
const API_BASE_URL = "https://r18chb4pqc.execute-api.us-east-1.amazonaws.com";

// Utility functions for formatting numbers and UI state
function toNumber(x) {
  const n = Number(x);
  return Number.isFinite(n) ? n : null;
}

function formatMoney(x) {
  const n = toNumber(x);
  return n === null ? "N/A" : `$${n.toFixed(2)}`;
}

function formatPercent(x) {
  const n = toNumber(x);
  if (n === null) return "N/A";
  const sign = n > 0 ? "+" : "";
  return `${sign}${n.toFixed(2)}%`;
}

function pillClass(percentChange) {
  const n = toNumber(percentChange);
  if (n === null) return "pill";
  return `pill ${n >= 0 ? "green" : "red"}`;
}

// Featured card for today's highest mover
function renderFeatured(item) {
  return `
    <div class="featured-card">
      <div class="date-text">${item.date ?? ""}</div>
      <div class="featured-symbol">${item.symbol ?? "N/A"}</div>
      <div class="${pillClass(item.percent_change)}">${formatPercent(
    item.percent_change
  )}</div>
      <div class="price-text">Close: ${formatMoney(item.close)}</div>
    </div>
  `;
}

// Standard card for past winners
function renderStandardCard(item) {
  return `
    <div class="standard-card">
      <div class="date-text">${item.date ?? ""}</div>
      <div style="font-size: 1.8rem; font-weight: 700; color:#2d3748;">${
        item.symbol ?? "N/A"
      }</div>
      <div class="${pillClass(item.percent_change)}">${formatPercent(
    item.percent_change
  )}</div>
      <div class="price-text">Close: ${formatMoney(item.close)}</div>
    </div>
  `;
}

// Main function to load and display movers from the API
async function loadMovers() {
  const currentEl = document.getElementById("current-winner-section");
  const gridEl = document.getElementById("past-winners-grid");

  currentEl.innerHTML = `<div class="loading-text">Loading today's data...</div>`;
  gridEl.innerHTML = "";

  try {
    const resp = await fetch(`${API_BASE_URL}/movers`, { method: "GET" });

    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`API error ${resp.status}: ${text}`);
    }

    const data = await resp.json();

    if (!Array.isArray(data) || data.length === 0) {
      currentEl.innerHTML = `<div class="loading-text">No data yet. Run the daily Lambda once to populate DynamoDB.</div>`;
      return;
    }

    // Extra sort to ensure latest date first even though API should do this
    data.sort((a, b) => (b.date || "").localeCompare(a.date || ""));

    const latest = data[0];
    currentEl.innerHTML = renderFeatured(latest);

    // Render past winners
    const past = data.slice(1, 8); //excludes latest and shows previous 7
    gridEl.innerHTML = past.map(renderStandardCard).join("");
  } catch (err) {
    console.error(err);
    currentEl.innerHTML = `<div class="loading-text">Failed to load data: ${err.message}</div>`;
  }
}

document.addEventListener("DOMContentLoaded", loadMovers);
