#!/usr/bin/env node
/**
 * Build design manifest from keystone and variants.
 *
 * Usage:
 *   node scripts/design_manifest_build.js
 *
 * Reads:
 *   artifacts/05-design/keystone.html
 *   artifacts/05-design/variants/*.html
 *
 * Writes:
 *   artifacts/05-design/manifest.json
 */
const fs = require("fs");
const path = require("path");

const DESIGN_DIR = "artifacts/05-design";
const VARIANTS_DIR = path.join(DESIGN_DIR, "variants");
const MANIFEST_PATH = path.join(DESIGN_DIR, "manifest.json");
const KEYSTONE_PATH = path.join(DESIGN_DIR, "keystone.html");

function extractTitle(htmlPath) {
  try {
    const html = fs.readFileSync(htmlPath, "utf8");
    const match = html.match(/<title>(.*?)<\/title>/i);
    return match ? match[1].trim() : path.basename(htmlPath, ".html");
  } catch {
    return path.basename(htmlPath, ".html");
  }
}

function extractDescription(filename) {
  // Extract description from filename pattern: variant-01-dark.html → "Dark"
  const match = filename.match(/variant-\d+-(.+)\.html$/);
  if (match) {
    return match[1]
      .split("-")
      .map(w => w.charAt(0).toUpperCase() + w.slice(1))
      .join(" ");
  }
  return filename;
}

function main() {
  console.log("Building design manifest...");
  
  // Ensure design directory exists
  if (!fs.existsSync(DESIGN_DIR)) {
    fs.mkdirSync(DESIGN_DIR, { recursive: true });
    console.log(`Created: ${DESIGN_DIR}`);
  }
  
  // Check for keystone
  let keystone = null;
  if (fs.existsSync(KEYSTONE_PATH)) {
    keystone = {
      file: "keystone.html",
      title: extractTitle(KEYSTONE_PATH),
      description: "Primary screen (keystone)"
    };
    console.log(`  Found keystone: ${KEYSTONE_PATH}`);
  } else {
    console.log(`  No keystone found at: ${KEYSTONE_PATH}`);
  }
  
  // Find variants
  const variants = [];
  if (fs.existsSync(VARIANTS_DIR)) {
    const files = fs.readdirSync(VARIANTS_DIR)
      .filter(f => f.endsWith(".html"))
      .sort();
    
    for (const file of files) {
      const filePath = path.join(VARIANTS_DIR, file);
      variants.push({
        file: `variants/${file}`,
        title: extractTitle(filePath),
        description: extractDescription(file)
      });
    }
    
    console.log(`  Found ${variants.length} variants`);
  } else {
    console.log(`  No variants directory at: ${VARIANTS_DIR}`);
  }
  
  // Check for tasteboard
  const tasteboardPath = path.join(DESIGN_DIR, "tasteboard.md");
  const hasTasteboard = fs.existsSync(tasteboardPath);
  
  // Build manifest
  const manifest = {
    generatedAt: new Date().toISOString(),
    keystone,
    variants,
    tasteboard: hasTasteboard ? "tasteboard.md" : null,
    counts: {
      keystone: keystone ? 1 : 0,
      variants: variants.length,
      total: (keystone ? 1 : 0) + variants.length
    }
  };
  
  // Write manifest
  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + "\n", "utf8");
  
  console.log("");
  console.log(`✅ Wrote manifest: ${MANIFEST_PATH}`);
  console.log(`   Keystone: ${keystone ? "yes" : "no"}`);
  console.log(`   Variants: ${variants.length}`);
  console.log(`   Tasteboard: ${hasTasteboard ? "yes" : "no"}`);
}

main();
