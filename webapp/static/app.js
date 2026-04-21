const charts = {};

const PALETTE = [
  "#7c9cff", "#5ad7b2", "#ffb86b", "#ff7e7e",
  "#c78bff", "#6bd3ff", "#ffd56b", "#9aa3c7",
];

const TIER_ORDER = ["0%", "1-10%", "11-20%", "21-30%", "30%+"];

Chart.defaults.color = "#9aa3c7";
Chart.defaults.borderColor = "#2a3154";
Chart.defaults.font.family = '-apple-system, "Segoe UI", system-ui, sans-serif';

// ---------- helpers ----------
async function load(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url} → HTTP ${r.status}`);
  return r.json();
}

function fmt(n) {
  if (n === null || n === undefined) return "—";
  if (typeof n !== "number") return String(n);
  if (Math.abs(n) >= 1_000_000) return (n / 1_000_000).toFixed(2) + "M";
  if (Math.abs(n) >= 1_000) return (n / 1_000).toFixed(1) + "k";
  return Number.isInteger(n) ? n.toString() : n.toFixed(2);
}

function renderTable(id, rows) {
  const el = document.getElementById(id);
  if (!rows || !rows.length) { el.innerHTML = "<p>No data.</p>"; return; }
  const cols = Object.keys(rows[0]);
  const thead = `<tr>${cols.map(c => `<th>${c}</th>`).join("")}</tr>`;
  const body = rows.map(r =>
    `<tr>${cols.map(c => `<td>${fmt(r[c])}</td>`).join("")}</tr>`
  ).join("");
  el.innerHTML = `<table><thead>${thead}</thead><tbody>${body}</tbody></table>`;
}

function destroyIf(key) {
  if (charts[key]) { charts[key].destroy(); charts[key] = null; }
}

function showError(name, e) {
  console.error(name, e);
  const s = document.getElementById("status");
  s.textContent = `⚠ ${name}: ${e.message}`;
}

// group a flat list of rows by a key, returning a Map.
function groupBy(rows, key) {
  const m = new Map();
  for (const r of rows) {
    const k = r[key];
    if (!m.has(k)) m.set(k, []);
    m.get(k).push(r);
  }
  return m;
}

function sortTiers(tiers) {
  return tiers.slice().sort((a, b) => TIER_ORDER.indexOf(a) - TIER_ORDER.indexOf(b));
}

function baseBarOpts(titleY = "Revenue (USD)") {
  return {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { labels: { color: "#e6e9f5" } },
      tooltip: { callbacks: { label: ctx => `${ctx.dataset.label}: ${fmt(ctx.parsed.y ?? ctx.parsed.x)}` } },
    },
    scales: {
      x: { ticks: { color: "#9aa3c7" }, grid: { color: "#2a3154" } },
      y: { ticks: { color: "#9aa3c7", callback: v => fmt(v) }, grid: { color: "#2a3154" }, title: { display: true, text: titleY, color: "#9aa3c7" } },
    },
  };
}

// ---------- Q1 ----------
async function renderQ1() {
  const data = await load("/api/q1");
  destroyIf("q1");
  charts.q1 = new Chart(document.getElementById("chart-q1"), {
    type: "bar",
    data: {
      labels: data.map(d => d.discount_tier),
      datasets: [
        {
          label: "Total revenue",
          data: data.map(d => +d.total_revenue),
          backgroundColor: PALETTE[0],
          yAxisID: "y",
        },
        {
          label: "Avg revenue / order",
          data: data.map(d => +d.avg_revenue_per_order),
          type: "line",
          borderColor: PALETTE[1],
          backgroundColor: PALETTE[1],
          yAxisID: "y1",
          tension: 0.25,
        },
      ],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { labels: { color: "#e6e9f5" } } },
      scales: {
        x: { ticks: { color: "#9aa3c7" }, grid: { color: "#2a3154" } },
        y: { position: "left", ticks: { color: "#9aa3c7", callback: v => fmt(v) }, grid: { color: "#2a3154" }, title: { display: true, text: "Total revenue", color: "#9aa3c7" } },
        y1: { position: "right", ticks: { color: "#9aa3c7", callback: v => fmt(v) }, grid: { drawOnChartArea: false }, title: { display: true, text: "Avg / order", color: "#9aa3c7" } },
      },
    },
  });
  renderTable("table-q1", data);
}

// ---------- Q2: brand x tier grouped bar ----------
async function renderQ2() {
  const data = await load("/api/q2");
  const brands = [...new Set(data.map(d => d.brand_name))];
  const tiers = sortTiers([...new Set(data.map(d => d.discount_tier))]);
  const datasets = tiers.map((t, i) => ({
    label: t,
    backgroundColor: PALETTE[i % PALETTE.length],
    data: brands.map(b => {
      const row = data.find(d => d.brand_name === b && d.discount_tier === t);
      return row ? +row.total_revenue : 0;
    }),
  }));
  destroyIf("q2");
  charts.q2 = new Chart(document.getElementById("chart-q2"), {
    type: "bar",
    data: { labels: brands, datasets },
    options: {
      ...baseBarOpts(),
      scales: {
        x: { ticks: { color: "#9aa3c7" }, grid: { color: "#2a3154" } },
        y: { ticks: { color: "#9aa3c7", callback: v => fmt(v) }, grid: { color: "#2a3154" }, title: { display: true, text: "Revenue", color: "#9aa3c7" } },
      },
    },
  });
  renderTable("table-q2", data);
}

// ---------- Q3: category x tier grouped bar ----------
async function renderQ3() {
  const data = await load("/api/q3");
  const cats = [...new Set(data.map(d => d.category_name))];
  const tiers = sortTiers([...new Set(data.map(d => d.discount_tier))]);
  const datasets = tiers.map((t, i) => ({
    label: t,
    backgroundColor: PALETTE[i % PALETTE.length],
    data: cats.map(c => {
      const row = data.find(d => d.category_name === c && d.discount_tier === t);
      return row ? +row.total_revenue : 0;
    }),
  }));
  destroyIf("q3");
  charts.q3 = new Chart(document.getElementById("chart-q3"), {
    type: "bar",
    data: { labels: cats, datasets },
    options: baseBarOpts("Revenue"),
  });
  renderTable("table-q3", data);
}

// ---------- Q4: channel x tier ----------
async function renderQ4() {
  const data = await load("/api/q4");
  const channels = [...new Set(data.map(d => d.channel_name))];
  const tiers = sortTiers([...new Set(data.map(d => d.discount_tier))]);
  const datasets = tiers.map((t, i) => ({
    label: t,
    backgroundColor: PALETTE[i % PALETTE.length],
    data: channels.map(c => {
      const row = data.find(d => d.channel_name === c && d.discount_tier === t);
      return row ? +row.total_revenue : 0;
    }),
  }));
  destroyIf("q4");
  charts.q4 = new Chart(document.getElementById("chart-q4"), {
    type: "bar",
    data: { labels: channels, datasets },
    options: baseBarOpts("Revenue"),
  });
  renderTable("table-q4", data);
}

// ---------- Q5: horizontal bar of top combos ----------
async function renderQ5() {
  const limit = +document.getElementById("q5-limit").value || 15;
  const data = await load(`/api/q5?limit=${limit}`);
  const labels = data.map(d => `${d.brand_name}·${d.category_name}·${d.gender_name}·${d.price_band}·${d.discount_tier}`);
  destroyIf("q5");
  charts.q5 = new Chart(document.getElementById("chart-q5"), {
    type: "bar",
    data: {
      labels,
      datasets: [{
        label: "Avg rating",
        data: data.map(d => +d.avg_rating),
        backgroundColor: PALETTE[1],
      }],
    },
    options: {
      indexAxis: "y",
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: {
        x: { min: 3, max: 5, ticks: { color: "#9aa3c7" }, grid: { color: "#2a3154" }, title: { display: true, text: "Avg rating", color: "#9aa3c7" } },
        y: { ticks: { color: "#9aa3c7", font: { size: 10 } }, grid: { color: "#2a3154" } },
      },
    },
  });
  renderTable("table-q5", data);
}

// ---------- Q6: country revenue + income mix ----------
async function renderQ6() {
  const data = await load("/api/q6");
  destroyIf("q6");
  charts.q6 = new Chart(document.getElementById("chart-q6"), {
    type: "bar",
    data: {
      labels: data.map(d => d.country_name),
      datasets: [{
        label: "Total revenue",
        data: data.map(d => +d.total_revenue),
        backgroundColor: PALETTE[0],
      }],
    },
    options: baseBarOpts("Revenue"),
  });

  destroyIf("q6income");
  charts.q6income = new Chart(document.getElementById("chart-q6-income"), {
    type: "bar",
    data: {
      labels: data.map(d => d.country_name),
      datasets: [
        { label: "Low %",    data: data.map(d => +d.pct_low),    backgroundColor: PALETTE[3] },
        { label: "Medium %", data: data.map(d => +d.pct_medium), backgroundColor: PALETTE[2] },
        { label: "High %",   data: data.map(d => +d.pct_high),   backgroundColor: PALETTE[1] },
      ],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { labels: { color: "#e6e9f5" } } },
      scales: {
        x: { stacked: true, ticks: { color: "#9aa3c7" }, grid: { color: "#2a3154" } },
        y: { stacked: true, max: 100, ticks: { color: "#9aa3c7", callback: v => v + "%" }, grid: { color: "#2a3154" }, title: { display: true, text: "Income mix", color: "#9aa3c7" } },
      },
    },
  });
  renderTable("table-q6", data);
}

// ---------- Q7: size × color demand ----------
async function renderQ7() {
  const cat = document.getElementById("q7-category").value || "Running";
  const limit = +document.getElementById("q7-limit").value || 20;
  const data = await load(`/api/q7?category=${encodeURIComponent(cat)}&limit=${limit}`);
  destroyIf("q7");
  charts.q7 = new Chart(document.getElementById("chart-q7"), {
    type: "bar",
    data: {
      labels: data.map(d => `${d.size} · ${d.color}`),
      datasets: [{
        label: "Units sold",
        data: data.map(d => +d.total_units),
        backgroundColor: PALETTE[4],
      }],
    },
    options: {
      indexAxis: "y",
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: {
        x: { ticks: { color: "#9aa3c7", callback: v => fmt(v) }, grid: { color: "#2a3154" }, title: { display: true, text: "Units", color: "#9aa3c7" } },
        y: { ticks: { color: "#9aa3c7", font: { size: 10 } }, grid: { color: "#2a3154" } },
      },
    },
  });
  renderTable("table-q7", data);
}

async function populateCategories() {
  try {
    const cats = await load("/api/categories");
    const sel = document.getElementById("q7-category");
    sel.innerHTML = cats.map(c =>
      `<option value="${c.category_name}"${c.category_name === "Running" ? " selected" : ""}>${c.category_name}</option>`
    ).join("");
  } catch (e) { showError("categories", e); }
}

// ---------- Q8 line charts ----------
function lineOpts(xTitle) {
  return {
    responsive: true, maintainAspectRatio: false,
    plugins: { legend: { labels: { color: "#e6e9f5" } } },
    interaction: { mode: "index", intersect: false },
    scales: {
      x: { ticks: { color: "#9aa3c7" }, grid: { color: "#2a3154" }, title: { display: true, text: xTitle, color: "#9aa3c7" } },
      y: { ticks: { color: "#9aa3c7", callback: v => fmt(v) }, grid: { color: "#2a3154" }, title: { display: true, text: "Revenue", color: "#9aa3c7" } },
    },
  };
}

async function renderQ8a() {
  const data = await load("/api/q8?groupby=year");
  const years = [...new Set(data.map(d => d.year))].sort();
  const cats = [...new Set(data.map(d => d.category_name))];
  const datasets = cats.map((c, i) => ({
    label: c,
    borderColor: PALETTE[i % PALETTE.length],
    backgroundColor: PALETTE[i % PALETTE.length],
    tension: 0.25,
    data: years.map(y => {
      const r = data.find(d => d.year === y && d.category_name === c);
      return r ? +r.revenue : 0;
    }),
  }));
  destroyIf("q8a");
  charts.q8a = new Chart(document.getElementById("chart-q8a"), {
    type: "line",
    data: { labels: years, datasets },
    options: lineOpts("Year"),
  });
  renderTable("table-q8a", data);
}

async function renderQ8b() {
  const data = await load("/api/q8?groupby=month");
  const months = [...new Set(data.map(d => d.month))].sort((a, b) => a - b);
  const monthNames = months.map(m => data.find(d => d.month === m).month_name.trim());
  const cats = [...new Set(data.map(d => d.category_name))];
  const datasets = cats.map((c, i) => ({
    label: c,
    borderColor: PALETTE[i % PALETTE.length],
    backgroundColor: PALETTE[i % PALETTE.length],
    tension: 0.3,
    data: months.map(m => {
      const r = data.find(d => d.month === m && d.category_name === c);
      return r ? +r.revenue : 0;
    }),
  }));
  destroyIf("q8b");
  charts.q8b = new Chart(document.getElementById("chart-q8b"), {
    type: "line",
    data: { labels: monthNames, datasets },
    options: lineOpts("Month"),
  });
  renderTable("table-q8b", data);
}

// ---------- Q9 ----------
async function renderQ9() {
  const data = await load("/api/q9");
  destroyIf("q9");
  charts.q9 = new Chart(document.getElementById("chart-q9"), {
    type: "bar",
    data: {
      labels: data.map(d => d.discount_tier),
      datasets: [{
        label: "Avg rating",
        data: data.map(d => +d.avg_rating),
        backgroundColor: PALETTE.slice(0, data.length),
      }],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            afterLabel: ctx => {
              const row = data[ctx.dataIndex];
              return [
                `Orders: ${fmt(+row.order_count)}`,
                `Avg revenue/order: ${fmt(+row.avg_revenue_per_order)}`,
                `Stddev: ${fmt(+row.rating_stddev)}`,
              ];
            },
          },
        },
      },
      scales: {
        x: { ticks: { color: "#9aa3c7" }, grid: { color: "#2a3154" } },
        y: { min: 3, max: 5, ticks: { color: "#9aa3c7" }, grid: { color: "#2a3154" }, title: { display: true, text: "Avg rating", color: "#9aa3c7" } },
      },
    },
  });
  renderTable("table-q9", data);
}

// ---------- Tabs ----------
function setupTabs() {
  document.querySelectorAll(".tabs button").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".tabs button").forEach(b => b.classList.remove("active"));
      document.querySelectorAll(".panel").forEach(p => p.classList.remove("active"));
      btn.classList.add("active");
      document.getElementById(btn.dataset.tab).classList.add("active");
    });
  });
}

// ---------- Health ----------
async function checkHealth() {
  const el = document.getElementById("health");
  try {
    const r = await load("/api/health");
    el.textContent = r.ok ? "db: connected" : "db: error";
    el.className = "health " + (r.ok ? "ok" : "err");
  } catch (e) {
    el.textContent = "db: unreachable";
    el.className = "health err";
  }
}

// ---------- Init ----------
document.addEventListener("DOMContentLoaded", async () => {
  setupTabs();
  checkHealth();

  document.getElementById("q5-apply").addEventListener("click", () => renderQ5().catch(e => showError("Q5", e)));
  document.getElementById("q7-apply").addEventListener("click", () => renderQ7().catch(e => showError("Q7", e)));

  await populateCategories();

  const renders = [renderQ1, renderQ2, renderQ3, renderQ4, renderQ5, renderQ6, renderQ7, renderQ8a, renderQ8b, renderQ9];
  await Promise.all(renders.map(fn => fn().catch(e => showError(fn.name, e))));
});
