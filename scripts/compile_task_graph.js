#!/usr/bin/env node
/**
 * Compile a canonical task graph from:
 * - artifacts/03-plan.md task seeds
 * - normalized Oracle issues (issues.json)
 *
 * Usage:
 *   node scripts/compile_task_graph.js --plan artifacts/03-plan.md --issues artifacts/06-oracle/plan/issues.json --out artifacts/04-task-graph.json
 *
 * Options:
 *   --infer, --infer-deps  Enable tag-based dependency inference (opt-in, not default)
 *   --include-nits         Convert "nit" severity issues into tasks (default: skip nits)
 */
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

function die(msg) {
  console.error("Error:", msg);
  process.exit(1);
}

function arg(name) {
  const idx = process.argv.indexOf(name);
  if (idx === -1) return null;
  return process.argv[idx + 1] || null;
}

function hasFlag(name) {
  return process.argv.includes(name);
}

function shaId(s) {
  return crypto.createHash("sha1").update(s).digest("hex").slice(0, 10);
}

function readText(p) {
  if (!p) return "";
  if (!fs.existsSync(p)) die(`Missing file: ${p}`);
  return fs.readFileSync(p, "utf8");
}

function readJson(p) {
  if (!p) return null;
  if (!fs.existsSync(p)) die(`Missing file: ${p}`);
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

/**
 * Parse task seeds from plan.md
 * 
 * Supported formats:
 *   - [ ] tag1,tag2 :: Subject          (recommended)
 *   - [ ] <tag1,tag2> :: Subject        (legacy, still supported)
 * 
 * Optional metadata lines:
 *   - ID: T-001
 *   - Blocked by: T-000, T-123
 *   - Deliverable: ...
 *   - Allowed paths: ...
 *   - Verification: ...
 *   - Setup: ...
 */
function parsePlanSeeds(planTxt) {
  const lines = planTxt.split("\n");
  const tasks = [];
  let i = 0;
  
  // Track current sprint context
  let currentSprint = null;
  let currentSprintGoal = null;
  let currentSprintDemo = null;

  while (i < lines.length) {
    const line = lines[i];
    
    // Check for sprint header: ## Sprint N: Goal
    const sprintMatch = line.match(/^##\s*Sprint\s*(\d+)\s*:\s*(.+?)\s*$/i);
    if (sprintMatch) {
      currentSprint = parseInt(sprintMatch[1], 10);
      currentSprintGoal = sprintMatch[2].trim();
      currentSprintDemo = null;
      i++;
      
      // Look for **Demo:** on next few lines
      for (let j = 0; j < 5 && (i + j) < lines.length; j++) {
        const demoMatch = lines[i + j].match(/^\*\*Demo:\*\*\s*(.+)/i);
        if (demoMatch) {
          currentSprintDemo = demoMatch[1].trim();
          break;
        }
      }
      continue;
    }
    
    // Reset sprint context on major headers (but not ### Tasks:)
    if (line.match(/^##\s+/) && !line.match(/^##\s*Sprint/i)) {
      currentSprint = null;
      currentSprintGoal = null;
      currentSprintDemo = null;
    }
    
    // Match: - [ ] <tags> :: subject  OR  - [ ] tags :: subject
    // Also supports - [x] for pre-completed tasks
    // Supports both <tag1,tag2> and bare tag1,tag2 formats
    const m = line.match(/^\s*-\s*\[\s*([xX ]?)\s*\]\s*(?:<(.+?)>|([A-Za-z0-9_.,\/-\s]+?))\s*::\s*(.+?)\s*$/);
    if (!m) { 
      i++; 
      continue; 
    }

    const checkState = (m[1] || "").trim().toLowerCase();
    const tagPart = (m[2] || m[3] || "").trim();
    const subject = m[4].trim();
    const initialStatus = checkState === "x" ? "completed" : "pending";
    const tags = tagPart.split(",").map(s => s.trim()).filter(Boolean);

    const details = { 
      id: null,
      blockedBy: [],
      deliverable: "", 
      allowedPaths: [], 
      verification: [],
      setup: "",
      // Sprint context
      sprint: currentSprint,
      sprintGoal: currentSprintGoal,
      sprintDemo: currentSprintDemo
    };
    
    i++;

    // Consume indented bullet lines
    let currentField = null;
    while (i < lines.length) {
      const l = lines[i];
      
      // Stop if we hit another task seed (either format, with [x] or [ ])
      if (l.match(/^\s*-\s*\[\s*[xX ]?\s*\]\s*(?:<.+?>|[A-Za-z0-9_.,\/-\s]+?)\s*::/)) break;
      
      // Stop if we hit a new section header
      if (l.match(/^#+\s/)) break;
      
      // Stop if non-indented non-empty line (prevents slurping unrelated content)
      if (l.trim() !== "" && !/^\s+/.test(l)) break;
      
      // Match detail fields - support multiple formats:
      //   - **Field:** value     (colon inside bold - natural markdown)
      //   - **Field**: value     (colon outside bold)
      //   - Field: value         (no bold)
      const fieldNames = 'ID|Blocked by|Deliverable|Allowed paths|Verification|Setup';
      // Format: - **Field:** value (colon inside bold)
      const d1 = l.match(new RegExp(`^\\s*-\\s*\\*\\*(${fieldNames}):\\*\\*\\s*(.*)\\s*$`, 'i'));
      // Format: - **Field**: value (colon outside bold)  
      const d2 = d1 ? null : l.match(new RegExp(`^\\s*-\\s*\\*\\*(${fieldNames})\\*\\*\\s*:\\s*(.*)\\s*$`, 'i'));
      // Format: - Field: value (no bold)
      const d3 = (d1 || d2) ? null : l.match(new RegExp(`^\\s*-\\s*(${fieldNames})\\s*:\\s*(.*)\\s*$`, 'i'));
      const d = d1 || d2 || d3;
      if (d) {
        const key = d[1].toLowerCase();
        const val = (d[2] || "").trim();
        
        if (key === "id") {
          currentField = "id";
          details.id = val;
        }
        if (key === "blocked by") {
          currentField = "blockedBy";
          details.blockedBy = val ? val.split(",").map(s => s.trim()).filter(Boolean) : [];
        }
        if (key === "deliverable") {
          currentField = "deliverable";
          details.deliverable = val;
        }
        if (key === "allowed paths") {
          currentField = "allowedPaths";
          details.allowedPaths = val ? val.split(",").map(s => s.trim()).filter(Boolean) : [];
        }
        if (key === "verification") {
          currentField = "verification";
          details.verification = val ? [val] : [];
        }
        if (key === "setup") {
          currentField = "setup";
          details.setup = val;
        }
      } else {
        // Check for continuation bullets
        const v = l.match(/^\s{4,}-\s+(.+)\s*$/);
        if (v) {
          const content = v[1].trim();
          if (currentField === "verification") {
            details.verification.push(content);
          } else if (currentField === "allowedPaths") {
            details.allowedPaths.push(content);
          } else if (currentField === "blockedBy") {
            details.blockedBy.push(content);
          } else if (currentField === "deliverable" && !details.deliverable) {
            details.deliverable = content;
          }
        }
      }
      
      i++;
    }

    // Build task object
    const id = details.id || shaId(`seed:${tags.join(",")}:${subject}`);
    
    const descriptionParts = [];
    if (details.deliverable) {
      descriptionParts.push(`**Deliverable:** ${details.deliverable}`);
    }
    if (details.setup) {
      descriptionParts.push(`**Setup:** ${details.setup}`);
    }
    if (details.allowedPaths.length) {
      descriptionParts.push(`**Allowed paths:** ${details.allowedPaths.join(", ")}`);
    }
    if (details.verification.length) {
      descriptionParts.push(`**Verification:**\n- ${details.verification.join("\n- ")}`);
    }

    tasks.push({
      id,
      subject,
      description: descriptionParts.join("\n\n") || "Deliverable: (describe)\nVerification: (describe)",
      activeForm: toActiveForm(subject),
      tags,
      blockedBy: details.blockedBy,
      allowedPaths: details.allowedPaths.length ? details.allowedPaths : undefined,
      verification: details.verification.length ? details.verification : undefined,
      deliverable: details.deliverable || undefined,
      setup: details.setup || undefined,
      source: "plan",
      status: initialStatus,
      // Sprint context
      sprint: details.sprint || undefined,
      sprintGoal: details.sprintGoal || undefined,
      sprintDemo: details.sprintDemo || undefined
    });
  }

  // Normalize references: strip markdown formatting from blockedBy refs
  const normalizeRef = (s) => String(s || "")
    .replace(/[`*_]/g, "")
    .replace(/^"+|"+$/g, "")
    .trim();

  // Resolve blockedBy entries that are written as exact subjects (best-effort)
  const byId = new Map(tasks.map(t => [String(t.id), t]));
  const bySubject = new Map(tasks.map(t => [String(t.subject).toLowerCase(), t]));
  for (const t of tasks) {
    if (!Array.isArray(t.blockedBy) || t.blockedBy.length === 0) continue;
    t.blockedBy = t.blockedBy.map(ref => {
      const r = normalizeRef(ref);
      if (byId.has(r)) return r;
      const match = bySubject.get(r.toLowerCase());
      return match ? String(match.id) : r;
    });
  }

  return tasks;
}

/**
 * Convert subject to active form for status display
 */
function toActiveForm(subject) {
  const m = subject.match(/^(Fix|Add|Implement|Write|Create|Refactor|Build|Run|Update|Document|Set up|Configure)\b/i);
  if (!m) return `${subject}...`;
  
  const verb = m[1].toLowerCase();
  const rest = subject.slice(m[1].length).trim();
  
  const map = {
    "fix": "Fixing",
    "add": "Adding",
    "implement": "Implementing",
    "write": "Writing",
    "create": "Creating",
    "refactor": "Refactoring",
    "build": "Building",
    "run": "Running",
    "update": "Updating",
    "document": "Documenting",
    "set up": "Setting up",
    "configure": "Configuring"
  };
  
  return `${map[verb] || m[1]} ${rest}`.trim();
}

/**
 * Convert Oracle issues to tasks
 */
function issuesToTasks(issuesPayload, options = {}) {
  const { includeNits = false } = options;
  if (!issuesPayload) return [];

  // Support either { issues: [...] } or a top-level array of issues
  const rawIssues = Array.isArray(issuesPayload)
    ? issuesPayload
    : (Array.isArray(issuesPayload.issues) ? issuesPayload.issues : null);
  if (!rawIssues) return [];

  const tasks = [];

  for (const iss of rawIssues) {
    // Skip nits unless explicitly included
    if (iss.severity === "nit" && !includeNits) continue;
    
    const category = String(iss.category || "arch");
    const severity = String(iss.severity || "major");
    const title = String(iss.title || "Untitled issue");
    const subject = `[${category}/${severity}] ${title}`;
    const tags = [category, iss.lens].filter(Boolean).map(String);
    const id = iss.id ? String(iss.id) : shaId(`issue:${subject}:${iss.evidence}`);

    const description = `**Oracle Issue** (${category}, ${severity})

**Evidence:**
${iss.evidence}

**Recommendation:**
${iss.recommendation}

**Acceptance Test:**
${iss.acceptanceTest}`;

    tasks.push({
      id,
      subject,
      description,
      activeForm: `Addressing ${category} issue...`,
      tags,
      blockedBy: [],
      source: "oracle",
      severity: iss.severity,
      files: Array.isArray(iss.files) ? iss.files : undefined,
      status: "pending"
    });
  }
  
  return tasks;
}

/**
 * Infer dependencies based on tags
 */
function inferDependencies(tasks) {
  // Build tag -> task id mapping (case-insensitive)
  const tagToTasks = new Map();
  for (const t of tasks) {
    for (const rawTag of t.tags || []) {
      const tag = String(rawTag).toLowerCase();
      if (!tag) continue;
      if (!tagToTasks.has(tag)) tagToTasks.set(tag, []);
      tagToTasks.get(tag).push(t.id);
    }
  }
  
  // Define dependency rules (all lowercase)
  const dependsOn = {
    "ui": ["engine", "core", "types", "data"],
    "components": ["types", "core"],
    "tests": ["engine", "ui", "core"],
    "e2e": ["ui", "components", "tests"],
    "worker": ["types", "core"],
    "io": ["engine", "worker"],
    "integration": ["engine", "ui", "io"]
  };
  
  // Apply inferred dependencies
  for (const task of tasks) {
    const inferred = [];
    
    for (const rawTag of task.tags || []) {
      const tag = String(rawTag).toLowerCase();
      const deps = dependsOn[tag] || [];
      for (const depTag of deps) {
        const depTaskIds = tagToTasks.get(depTag) || [];
        for (const depId of depTaskIds) {
          if (depId !== task.id && !inferred.includes(depId)) {
            inferred.push(depId);
          }
        }
      }
    }
    
    if (inferred.length > 0) {
      task.blockedBy = [...new Set([...task.blockedBy, ...inferred])];
    }
  }
  
  return tasks;
}

/**
 * Detect cycles in the dependency graph using DFS
 */
function findCycles(tasks) {
  const byId = new Map(tasks.map(t => [t.id, t]));
  const visited = new Set();
  const inStack = new Set();
  const path = [];
  const cycles = [];

  function dfs(id) {
    if (inStack.has(id)) {
      const idx = path.indexOf(id);
      if (idx !== -1) cycles.push([...path.slice(idx), id]);
      return;
    }
    if (visited.has(id)) return;
    visited.add(id);
    inStack.add(id);
    path.push(id);
    const task = byId.get(id);
    for (const dep of task?.blockedBy || []) {
      if (byId.has(dep)) dfs(dep);
    }
    path.pop();
    inStack.delete(id);
  }

  for (const t of tasks) dfs(t.id);
  return cycles;
}

/**
 * Validate task graph
 */
function validateGraph(tasks) {
  const warnings = [];
  const taskIds = new Set(tasks.map(t => t.id));
  const byId = new Map(tasks.map(t => [t.id, t]));
  
  // Check for cycles
  const cycles = findCycles(tasks);
  for (const cycle of cycles) {
    const labels = cycle.map(id => {
      const t = byId.get(id);
      return t ? t.subject.slice(0, 40) : id;
    });
    warnings.push(`Dependency cycle detected: ${labels.join(" → ")}`);
  }
  
  for (const task of tasks) {
    // Check for invalid blockers
    for (const blockerId of task.blockedBy || []) {
      if (!taskIds.has(blockerId)) {
        warnings.push(`Task "${task.subject}" has invalid blocker: ${blockerId}`);
      }
    }
    
    // Check for missing verification
    if (!task.verification?.length && task.source === "plan") {
      warnings.push(`Task "${task.subject}" has no verification commands`);
    }
  }
  
  return warnings;
}

function main() {
  const planPath = arg("--plan");
  const issuesPath = arg("--issues");
  const outPath = arg("--out") || "artifacts/04-task-graph.json";
  const inferDeps = hasFlag("--infer") || hasFlag("--infer-deps");
  const includeNits = hasFlag("--include-nits");

  if (!planPath) die("Missing --plan <path>");
  // --issues is now optional

  console.log("Compiling task graph...");
  console.log(`  Plan: ${planPath}`);
  if (issuesPath) console.log(`  Issues: ${issuesPath}`);
  else console.log(`  Issues: (none - plan only)`);
  console.log(`  Output: ${outPath}`);
  if (inferDeps) console.log(`  Dependency inference: ENABLED`);
  if (includeNits) console.log(`  Include nits: YES`);
  console.log("");

  const planTxt = readText(planPath);
  const issuesPayload = issuesPath && fs.existsSync(issuesPath) ? readJson(issuesPath) : null;

  // Parse tasks from both sources
  let seedTasks = parsePlanSeeds(planTxt);
  let issueTasks = issuesPayload ? issuesToTasks(issuesPayload, { includeNits }) : [];

  console.log(`  Seed tasks from plan: ${seedTasks.length}`);
  if (issuesPayload) {
    console.log(`  Issue tasks from Oracle: ${issueTasks.length}`);
  }

  // Combine tasks
  let tasks = [...seedTasks, ...issueTasks];
  
  // Only infer dependencies if explicitly requested
  if (inferDeps) {
    tasks = inferDependencies(tasks);
    console.log(`  Inferred dependencies applied`);
  }

  // Validate
  const warnings = validateGraph(tasks);
  if (warnings.length > 0) {
    console.log("");
    console.log("⚠️  Warnings:");
    for (const w of warnings) {
      console.log(`  - ${w}`);
    }
  }

  // Build final graph
  const graph = {
    meta: {
      generatedAt: new Date().toISOString(),
      inputs: { planPath, issuesPath },
      options: { inferDeps, includeNits },
      counts: { 
        seedTasks: seedTasks.length, 
        issueTasks: issueTasks.length, 
        total: tasks.length,
        readyToStart: tasks.filter(t => !t.blockedBy?.length).length
      },
      warnings: warnings.length > 0 ? warnings : undefined
    },
    tasks
  };

  // Write output
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(graph, null, 2) + "\n", "utf8");
  
  console.log("");
  console.log(`✅ Wrote task graph: ${outPath}`);
  console.log(`   Total tasks: ${tasks.length}`);
  console.log(`   Ready to start: ${tasks.filter(t => !t.blockedBy?.length).length}`);
}

try {
  main();
} catch (err) {
  console.error("Error:", err.message);
  if (process.env.DEBUG) console.error(err.stack);
  process.exit(1);
}
