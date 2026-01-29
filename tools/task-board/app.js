// Task Board - Kanban view of task-graph.json

const GRAPH_URL = "../../artifacts/04-task-graph.json";

function el(tag, attrs = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") e.className = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2).toLowerCase(), v);
    else e.setAttribute(k, v);
  }
  for (const kid of kids) {
    if (kid === null || kid === undefined) continue;
    e.appendChild(typeof kid === "string" ? document.createTextNode(kid) : kid);
  }
  return e;
}

async function fetchJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch ${url}: ${res.status}`);
  return res.json();
}

function uniqueSorted(arr) {
  return [...new Set(arr)].sort();
}

function setOptions(sel, values) {
  const current = sel.value;
  // Keep first option (all)
  while (sel.options.length > 1) sel.remove(1);
  for (const v of values) {
    sel.appendChild(el("option", { value: v }, v));
  }
  // Restore previous selection if still present
  if ([...sel.options].some(o => o.value === current)) {
    sel.value = current;
  } else {
    sel.value = "";
  }
}

function applyFilters(tasks, filters) {
  return tasks.filter(t => {
    if (filters.q) {
      const q = filters.q.toLowerCase();
      const haystack = [
        t.subject,
        ...(t.tags || []),
        t.source,
        t.severity
      ].filter(Boolean).map(String).join(" ").toLowerCase();
      if (!haystack.includes(q)) return false;
    }
    // Case-insensitive tag filtering
    if (filters.tag) {
      const want = String(filters.tag).toLowerCase();
      const have = (t.tags || []).map(x => String(x).toLowerCase());
      if (!have.includes(want)) return false;
    }
    // Status filtering should match the board semantics:
    // - Tasks with status=pending AND blockedBy>0 are shown as "blocked"
    if (filters.status) {
      const status = t.status || "pending";
      const effectiveStatus = (status === "pending" && t.blockedBy && t.blockedBy.length > 0)
        ? "blocked"
        : status;
      if (effectiveStatus !== filters.status) return false;
    }
    if (filters.source && t.source !== filters.source) return false;
    return true;
  });
}

function bucketize(tasks) {
  const cols = {
    pending: [],
    blocked: [],
    in_progress: [],
    completed: []
  };
  
  for (const t of tasks) {
    const status = t.status || "pending";
    // Check if blocked
    if (status === "pending" && t.blockedBy && t.blockedBy.length > 0) {
      cols.blocked.push(t);
    } else if (cols[status]) {
      cols[status].push(t);
    } else {
      cols.pending.push(t);
    }
  }
  
  return cols;
}

function renderCard(task) {
  const severityClass = task.severity || "";
  const sourceClass = task.source || "";
  
  const pills = [];
  if (task.severity) {
    pills.push(el("span", { class: `pill ${task.severity}` }, task.severity));
  }
  if (task.source) {
    pills.push(el("span", { class: `pill ${task.source}` }, task.source));
  }
  
  const tags = (task.tags || []).map(tag => 
    el("span", { class: "muted" }, `#${tag}`)
  );
  
  const blockedInfo = task.blockedBy && task.blockedBy.length > 0
    ? el("div", { class: "muted" }, `⏳ Blocked by: ${task.blockedBy.join(", ")}`)
    : null;
  
  return el("div", { class: `card ${severityClass}` },
    el("div", { class: "top" },
      el("div", { class: "subject" }, task.subject),
      ...pills
    ),
    el("div", { class: "meta" }, ...tags),
    blockedInfo
  );
}

function renderColumn(title, tasks, emoji) {
  const header = el("h2", {}, 
    `${emoji} ${title} `,
    el("span", { class: "count" }, `(${tasks.length})`)
  );
  
  const cards = el("div", { class: "cards" });
  if (tasks.length === 0) {
    cards.appendChild(el("div", { class: "empty" }, "No tasks"));
  } else {
    for (const t of tasks) {
      cards.appendChild(renderCard(t));
    }
  }
  
  return el("div", { class: "col" }, header, cards);
}

function render(state) {
  const board = document.getElementById("board");
  const summary = document.getElementById("summary");
  
  board.innerHTML = "";
  
  const { tasksByCol, meta, all } = state;
  
  // Render columns
  board.appendChild(renderColumn("Pending", tasksByCol.pending, "📋"));
  board.appendChild(renderColumn("Blocked", tasksByCol.blocked, "⏳"));
  board.appendChild(renderColumn("In Progress", tasksByCol.in_progress, "🔄"));
  board.appendChild(renderColumn("Completed", tasksByCol.completed, "✅"));
  
  // Summary
  const counts = meta.counts || {};
  summary.textContent = `Total: ${all.length} tasks | Seeds: ${counts.seedTasks || 0} | Oracle: ${counts.issueTasks || 0} | Ready: ${counts.readyToStart || tasksByCol.pending.length}`;
}

function buildReport(state) {
  const { tasksByCol, meta, all } = state;
  const lines = [
    "# Task Board Report",
    "",
    `Generated: ${new Date().toISOString()}`,
    "",
    `## Summary`,
    "",
    `- Total tasks: ${all.length}`,
    `- Pending: ${tasksByCol.pending.length}`,
    `- Blocked: ${tasksByCol.blocked.length}`,
    `- In Progress: ${tasksByCol.in_progress.length}`,
    `- Completed: ${tasksByCol.completed.length}`,
    ""
  ];
  
  const addSection = (title, tasks) => {
    if (tasks.length === 0) return;
    lines.push(`## ${title}`);
    lines.push("");
    for (const t of tasks) {
      const tags = (t.tags || []).map(x => `\`${x}\``).join(" ");
      lines.push(`- **${t.subject}** ${tags}`);
      if (t.blockedBy && t.blockedBy.length) {
        lines.push(`  - Blocked by: ${t.blockedBy.join(", ")}`);
      }
    }
    lines.push("");
  };
  
  addSection("🔄 In Progress", tasksByCol.in_progress);
  addSection("⏳ Blocked", tasksByCol.blocked);
  addSection("📋 Pending", tasksByCol.pending);
  addSection("✅ Completed", tasksByCol.completed);
  
  return lines.join("\n");
}

function download(filename, content) {
  const blob = new Blob([content], { type: "text/markdown" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

async function main() {
  const qInput = document.getElementById("q");
  const tagSel = document.getElementById("tag");
  const statusSel = document.getElementById("status");
  const sourceSel = document.getElementById("source");

  async function reload() {
    try {
      const graph = await fetchJson(GRAPH_URL);
      const tasks = Array.isArray(graph.tasks) ? graph.tasks : [];
      const tags = uniqueSorted(tasks.flatMap(t => Array.isArray(t.tags) ? t.tags : []));

      setOptions(tagSel, tags);

      const filters = {
        q: qInput.value || "",
        tag: tagSel.value || "",
        status: statusSel.value || "",
        source: sourceSel.value || ""
      };

      const filtered = applyFilters(tasks, filters);
      const state = {
        all: filtered,
        tasksByCol: bucketize(filtered),
        meta: graph.meta || {},
        filters
      };
      window.__state = state;
      render(state);
    } catch (err) {
      const board = document.getElementById("board");
      board.innerHTML = "";
      board.appendChild(el("div", { class: "error" }, 
        `Error loading task graph: ${err.message}. Make sure artifacts/04-task-graph.json exists.`
      ));
    }
  }

  document.getElementById("reload").addEventListener("click", reload);
  document.getElementById("export").addEventListener("click", () => {
    const state = window.__state;
    if (!state) return;
    const md = buildReport(state);
    download("task-board-report.md", md);
  });

  function onFilterChange() { reload(); }
  qInput.addEventListener("input", () => {
    clearTimeout(window.__qT);
    window.__qT = setTimeout(onFilterChange, 120);
  });
  tagSel.addEventListener("change", onFilterChange);
  statusSel.addEventListener("change", onFilterChange);
  sourceSel.addEventListener("change", onFilterChange);

  await reload();
}

main();
