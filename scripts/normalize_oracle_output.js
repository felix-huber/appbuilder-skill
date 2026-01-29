#!/usr/bin/env node
/**
 * Normalize Oracle outputs into a structured issues JSON file.
 *
 * Usage:
 *   node scripts/normalize_oracle_output.js <oracle_output_folder> <out_json_path> [--prefix <filename_prefix>]
 *
 * The normalizer prefers a JSON object with { issues: [...] } either:
 * - inside a ```json code fence
 * - or as the first parseable JSON object/array in the file
 *
 * If not found, it falls back to heuristic parsing of Markdown.
 *
 * Options:
 *   --prefix <str>  Only process .md files whose basename starts with this prefix.
 *                   Useful for isolating results from a single Oracle run.
 */
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

function die(msg) {
  console.error("Error:", msg);
  process.exit(1);
}

function listMdFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter(f => f.endsWith(".md"))
    .sort() // Process in order
    .map(f => path.join(dir, f));
}

function shaId(s) {
  return crypto.createHash("sha1").update(s).digest("hex").slice(0, 10);
}

// Extract JSON from ```json code fence (first parseable block wins)
function extractJsonFromFence(txt) {
  const re = /```json\s*([\s\S]*?)\s*```/gi;
  let m;
  while ((m = re.exec(txt)) !== null) {
    const body = (m[1] || "").trim();
    if (!body) continue;
    try {
      return JSON.parse(body);
    } catch {
      // keep scanning
    }
  }
  return null;
}

// Balanced-brackets JSON scanner that respects quoted strings
function tryParseJsonAt(txt, start) {
  const first = txt[start];
  if (first !== "{" && first !== "[") return null;

  const stack = [];
  let inString = false;
  let escape = false;

  for (let i = start; i < txt.length; i++) {
    const c = txt[i];

    if (escape) {
      escape = false;
      continue;
    }

    if (inString) {
      if (c === "\\") {
        escape = true;
        continue;
      }
      if (c === '"') {
        inString = false;
      }
      continue;
    }

    if (c === '"') {
      inString = true;
      continue;
    }

    if (c === "{" || c === "[") {
      stack.push(c);
      continue;
    }

    if (c === "}" || c === "]") {
      const last = stack.pop();
      if ((c === "}" && last !== "{") || (c === "]" && last !== "[")) {
        return null;
      }
      if (stack.length === 0) {
        const candidate = txt.slice(start, i + 1);
        try {
          return JSON.parse(candidate);
        } catch {
          return null;
        }
      }
    }
  }

  return null;
}

// Find first valid JSON object/array in text
function extractFirstJsonObject(txt) {
  const candidates = [];

  // 1) High-signal: the common "{ \"issues\": ... }" shape
  const issuesRe = /\{\s*"issues"\s*:/g;
  const issuesM = issuesRe.exec(txt);
  if (issuesM) candidates.push(issuesM.index);

  // 2) JSON starting at the beginning of a line
  const lineRe = /^[ \t]*([{[])/gm;
  let m;
  while ((m = lineRe.exec(txt)) !== null) {
    const idx = m.index + m[0].length - 1;
    candidates.push(idx);
    if (candidates.length > 20) break;
  }

  // 3) Last resort: any brace/bracket
  const startObj = txt.indexOf("{");
  const startArr = txt.indexOf("[");
  if (startObj !== -1) candidates.push(startObj);
  if (startArr !== -1) candidates.push(startArr);

  const uniq = Array.from(new Set(candidates.filter(n => Number.isInteger(n) && n >= 0)))
    .sort((a, b) => a - b);

  for (const start of uniq) {
    const parsed = tryParseJsonAt(txt, start);
    if (parsed !== null && parsed !== undefined) return parsed;
  }
  return null;
}

// Allowed values for normalization
const allowedSev = new Set(["blocker", "major", "minor", "nit"]);
const allowedCat = new Set(["product", "ux", "arch", "security", "perf", "tests", "simplicity", "ops"]);

// Normalize severity synonyms
function normSeverity(v) {
  const s = String(v || "").trim().toLowerCase();
  if (allowedSev.has(s)) return s;
  if (s === "critical" || s === "sev0" || s === "p0" || s === "urgent") return "blocker";
  if (s === "high" || s === "sev1" || s === "p1") return "major";
  if (s === "medium" || s === "sev2" || s === "p2") return "major";
  if (s === "low" || s === "sev3" || s === "p3") return "minor";
  if (s === "trivial") return "nit";
  return "major";
}

// Normalize category synonyms
function normCategory(v) {
  const s = String(v || "").trim().toLowerCase();
  if (allowedCat.has(s)) return s;
  if (s === "architecture") return "arch";
  if (s === "performance") return "perf";
  if (s === "test" || s === "testing") return "tests";
  if (s === "ui" || s === "interface") return "ux";
  return "arch";
}

// Infer lens from filename like "20260126-120000_security.md"
function inferLensFromFilename(basename, prefix) {
  const name = String(basename || "").replace(/\.md$/i, "");
  const trimmed = prefix && name.startsWith(prefix) ? name.slice(prefix.length) : name;
  const parts = trimmed.split("_").filter(Boolean);
  if (parts.length === 0) return null;
  return parts[parts.length - 1] || null;
}

// Coerce raw issues to standard schema
function coerceIssues(obj, sourceFile, prefix) {
  if (!obj) return [];
  
  // Support either { issues: [...] } or top-level array
  const raw = Array.isArray(obj)
    ? obj
    : (Array.isArray(obj.issues) ? obj.issues : null);
  if (!raw) return [];

  const lens = inferLensFromFilename(path.basename(sourceFile), prefix);
  
  return raw.map((it) => {
    const severity = normSeverity(it.severity);
    const category = normCategory(it.category);
    
    const title = String(it.title || it.issue || it.finding || "").trim() || "Untitled issue";
    const evidence = String(it.evidence ?? it.why ?? it.context ?? "").trim() || "(no evidence provided)";
    const recommendation = String(it.recommendation ?? it.fix ?? it.remediation ?? it.suggestion ?? "").trim() || "(no recommendation provided)";
    const acceptanceTest = String(it.acceptanceTest ?? it.acceptance_test ?? it.verify ?? it.test ?? "").trim() || "(no acceptance test provided)";
    
    let files = undefined;
    if (Array.isArray(it.files)) files = it.files.map(String);
    else if (typeof it.files === "string") files = it.files.split(",").map(s => s.trim()).filter(Boolean);

    const id = it.id 
      ? String(it.id) 
      : shaId(`${category}:${title}:${evidence}`);
    
    return { 
      id, 
      severity, 
      category, 
      title, 
      evidence, 
      recommendation, 
      acceptanceTest, 
      files,
      source: path.basename(sourceFile),
      lens: lens || undefined
    };
  });
}

// Heuristic parsing for non-JSON outputs
function parseHeuristic(txt, sourceLabel) {
  const issues = [];
  
  // Try to parse headings like "## Issue: ..." or "### <title>"
  const blocks = txt.split(/\n(?=##+\s)/g);

  for (const b of blocks) {
    const head = b.match(/^##+\s+(.*)$/m);
    if (!head) continue;
    
    const titleRaw = head[1]
      .replace(/^(Issue:|Finding:|Problem:)\s*/i, "")
      .trim();
    if (!titleRaw) continue;

    // Extract fields from the block
    const getField = (name) => {
      const re = new RegExp(`^\\s*[-*]?\\s*\\*?\\*?${name}\\*?\\*?\\s*:\\s*(.+)$`, "im");
      const m = b.match(re);
      return m ? m[1].trim() : "";
    };

    const severity = (getField("Severity") || "").toLowerCase();
    const category = (getField("Category") || "").toLowerCase();

    const issue = {
      id: shaId(`${sourceLabel}:${titleRaw}`),
      severity: allowedSev.has(severity) ? severity : "major",
      category: allowedCat.has(category) ? category : "arch",
      title: titleRaw,
      evidence: getField("Evidence") || getField("Context") || "(no evidence provided)",
      recommendation: getField("Recommendation") || getField("Fix") || getField("Solution") || "(no recommendation provided)",
      acceptanceTest: getField("Acceptance Test") || getField("Verify") || getField("Test") || "(no acceptance test provided)",
      source: sourceLabel
    };

    issues.push(issue);
  }

  // If nothing parsed, salvage as a single meta-issue
  if (issues.length === 0 && txt.trim().length > 50) {
    issues.push({
      id: shaId(`fallback:${sourceLabel}`),
      severity: "minor",
      category: "arch",
      title: `Unstructured Oracle output (${sourceLabel})`,
      evidence: txt.slice(0, 1200),
      recommendation: "Re-run Oracle and ask it to output strict JSON { issues: [...] }.",
      acceptanceTest: "Normalized issues.json contains structured issues from Oracle.",
      source: sourceLabel
    });
  }

  return issues;
}

// Deduplicate by category + title
function dedupe(issues) {
  const seen = new Set();
  const out = [];
  
  for (const it of issues) {
    const key = `${it.category}::${it.title}`.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(it);
  }
  
  return out;
}

// Sort by severity (blocker first)
function sortBySeverity(issues) {
  const order = { blocker: 0, major: 1, minor: 2, nit: 3 };
  return issues.sort((a, b) => (order[a.severity] ?? 4) - (order[b.severity] ?? 4));
}

function main() {
  const dir = process.argv[2];
  const outPath = process.argv[3];
  
  if (!dir || !outPath) {
    die("Usage: node scripts/normalize_oracle_output.js <folder> <out_json> [--prefix <filename_prefix>]");
  }

  // Parse --prefix option for run isolation
  let prefix = null;
  for (let i = 4; i < process.argv.length; i++) {
    const a = process.argv[i];
    if (a === "--prefix") {
      prefix = process.argv[i + 1] || null;
      i++;
      continue;
    }
    die(`Unknown option: ${a}`);
  }

  // Ensure output directory exists
  const outDir = path.dirname(outPath);
  if (outDir && outDir !== ".") {
    fs.mkdirSync(outDir, { recursive: true });
  }

  let files = listMdFiles(dir);
  
  // Filter by prefix if specified
  if (prefix) {
    files = files.filter((f) => path.basename(f).startsWith(prefix));
  }

  if (files.length === 0) {
    if (prefix) {
      die(`No .md files found in: ${dir} matching prefix: ${prefix}`);
    }
    // Create empty issues file so downstream steps can continue
    const payload = { 
      issues: [], 
      meta: { 
        generatedAt: new Date().toISOString(), 
        sourceDir: dir,
        note: "No .md files found in directory"
      } 
    };
    fs.writeFileSync(outPath, JSON.stringify(payload, null, 2) + "\n", "utf8");
    console.log(`No .md files found in: ${dir}`);
    console.log(`Created empty issues file: ${outPath}`);
    return;
  }

  let issues = [];
  let parsedFromJson = 0;
  let parsedFromHeuristic = 0;

  for (const f of files) {
    const txt = fs.readFileSync(f, "utf8");
    const fileName = path.basename(f);
    
    // Try JSON extraction first
    const fromFence = extractJsonFromFence(txt);
    const fromObj = fromFence || extractFirstJsonObject(txt);
    const coerced = coerceIssues(fromObj, fileName, prefix);

    if (coerced.length > 0) {
      issues = issues.concat(coerced);
      parsedFromJson += coerced.length;
    } else {
      const heuristic = parseHeuristic(txt, fileName);
      issues = issues.concat(heuristic);
      parsedFromHeuristic += heuristic.length;
    }
  }

  // Deduplicate and sort
  issues = dedupe(issues);
  issues = sortBySeverity(issues);

  // Build payload
  const payload = { 
    issues, 
    meta: { 
      generatedAt: new Date().toISOString(), 
      sourceDir: dir,
      prefix: prefix || undefined,
      sourceFiles: files.map(f => path.basename(f)),
      counts: {
        total: issues.length,
        fromJson: parsedFromJson,
        fromHeuristic: parsedFromHeuristic,
        bySeverity: {
          blocker: issues.filter(i => i.severity === "blocker").length,
          major: issues.filter(i => i.severity === "major").length,
          minor: issues.filter(i => i.severity === "minor").length,
          nit: issues.filter(i => i.severity === "nit").length
        }
      }
    } 
  };
  
  fs.writeFileSync(outPath, JSON.stringify(payload, null, 2) + "\n", "utf8");
  console.log(`Normalized ${issues.length} issues → ${outPath}`);
  console.log(`  From JSON: ${parsedFromJson}, From heuristic: ${parsedFromHeuristic}`);
  if (prefix) console.log(`  Prefix filter: ${prefix}`);
}

main();
