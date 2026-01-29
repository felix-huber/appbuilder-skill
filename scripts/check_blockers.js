#!/usr/bin/env node
/**
 * check_blockers.js - Safely check for blocker issues in Oracle output
 * 
 * Usage:
 *   node scripts/check_blockers.js <issues_json_or_dir>
 * 
 * Returns:
 *   - Exit code 0: No blockers found (can proceed)
 *   - Exit code 1: Blockers found (must fix)
 *   - Exit code 2: File/directory not found (can proceed, no Oracle review yet)
 *   - Exit code 3: Invalid JSON (can proceed with warning)
 * 
 * Output (JSON):
 *   { "blockers": N, "majors": N, "canProceed": true/false, "message": "..." }
 */

const fs = require('fs');
const path = require('path');

function main() {
  const target = process.argv[2];
  
  if (!target) {
    output({ blockers: 0, majors: 0, canProceed: true, message: 'No issues file specified - proceeding' });
    process.exit(0);
  }
  
  // Check if target exists
  if (!fs.existsSync(target)) {
    output({ blockers: 0, majors: 0, canProceed: true, message: `${target} not found - no Oracle review yet, proceeding` });
    process.exit(2);
  }
  
  try {
    let issues = [];
    
    // If it's a directory, find all issues*.json files
    const stat = fs.statSync(target);
    if (stat.isDirectory()) {
      const files = fs.readdirSync(target)
        .filter(f => f.startsWith('issues') && f.endsWith('.json'))
        .map(f => path.join(target, f))
        // Newest first (mtime), avoids lexicographic issues like issues-round10 < issues-round9
        .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);

      if (files.length === 0) {
        output({ blockers: 0, majors: 0, canProceed: true, message: 'No issues.json files found - proceeding' });
        process.exit(2);
      }

      // Use the most recently modified issues file
      const latestFile = files[0];
      issues = loadIssues(latestFile);
    } else {
      issues = loadIssues(target);
    }
    
    const blockers = issues.filter(i => i.severity === 'blocker').length;
    const majors = issues.filter(i => i.severity === 'major').length;
    
    const canProceed = blockers === 0;
    const message = blockers === 0 
      ? `No blockers (${majors} majors, can proceed)`
      : `${blockers} BLOCKERS found - must fix before proceeding`;
    
    output({ blockers, majors, canProceed, message });
    process.exit(blockers > 0 ? 1 : 0);
    
  } catch (err) {
    output({ blockers: 0, majors: 0, canProceed: true, message: `Error reading issues: ${err.message} - proceeding with caution` });
    process.exit(3);
  }
}

function loadIssues(file) {
  const content = fs.readFileSync(file, 'utf8').trim();
  if (!content) {
    return [];
  }
  
  const data = JSON.parse(content);
  
  // Handle both { issues: [...] } and [...] formats
  if (Array.isArray(data)) {
    return data;
  }
  if (data && Array.isArray(data.issues)) {
    return data.issues;
  }
  
  return [];
}

function output(result) {
  console.log(JSON.stringify(result));
}

main();
