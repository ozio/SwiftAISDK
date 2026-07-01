#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const repoRoot = path.resolve(__dirname, "..");
const ledgerPath = path.join(repoRoot, "Docs", "ProviderVersionLedger.md");
const coreParityPath = path.join(repoRoot, "Docs", "CoreV6Parity.md");

const args = parseArgs(process.argv.slice(2));

main();

function main() {
  if (!args.noRefresh) {
    refreshUpstreamCheckout();
  }

  const commit = git(["rev-parse", "HEAD"], args.upstreamDir).trim();
  const commitLine = git(["log", "-1", "--format=%H %cI %s"], args.upstreamDir).trim();
  const testFiles = listTestFiles(args.upstreamDir);
  const grouped = groupByPackage(testFiles);
  const tracked = trackedPackages();
  const markdown = renderMarkdown({ commit, commitLine, testFiles, grouped, tracked });

  fs.mkdirSync(path.dirname(args.out), { recursive: true });
  fs.writeFileSync(args.out, markdown);
  console.log(`Wrote ${path.relative(repoRoot, args.out)} (${testFiles.length} upstream test files at ${commit.slice(0, 12)})`);
}

function parseArgs(rawArgs) {
  const parsed = {
    noRefresh: false,
    out: path.join(repoRoot, "Docs", "UpstreamTestInventory.md"),
    ref: "main",
    repoURL: "https://github.com/vercel/ai.git",
    upstreamDir: "/tmp/vercel-ai-upstream",
  };

  for (let index = 0; index < rawArgs.length; index += 1) {
    const arg = rawArgs[index];
    switch (arg) {
      case "--help":
      case "-h":
        printHelp();
        process.exit(0);
      case "--no-refresh":
        parsed.noRefresh = true;
        break;
      case "--out":
      case "-o":
        parsed.out = path.resolve(requiredValue(rawArgs, ++index, arg));
        break;
      case "--ref":
        parsed.ref = requiredValue(rawArgs, ++index, arg);
        break;
      case "--repo-url":
        parsed.repoURL = requiredValue(rawArgs, ++index, arg);
        break;
      case "--upstream-dir":
        parsed.upstreamDir = path.resolve(requiredValue(rawArgs, ++index, arg));
        break;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }

  return parsed;
}

function requiredValue(rawArgs, index, option) {
  const value = rawArgs[index];
  if (!value) {
    throw new Error(`${option} requires a value`);
  }
  return value;
}

function printHelp() {
  console.log(`Usage: Scripts/update-upstream-test-inventory.js [options]

Options:
  --upstream-dir <path>  Local vercel/ai checkout path. Defaults to /tmp/vercel-ai-upstream.
  --repo-url <url>       Upstream repository URL. Defaults to https://github.com/vercel/ai.git.
  --ref <ref>            Upstream ref to fetch. Defaults to main.
  --out <path>           Markdown output path. Defaults to Docs/UpstreamTestInventory.md.
  --no-refresh           Reuse the existing upstream checkout without fetching.
`);
}

function refreshUpstreamCheckout() {
  if (fs.existsSync(path.join(args.upstreamDir, ".git"))) {
    git(["fetch", "--depth", "1", "origin", args.ref], args.upstreamDir, { stdio: "inherit" });
    git(["checkout", "FETCH_HEAD"], args.upstreamDir, { stdio: "inherit" });
    return;
  }

  fs.mkdirSync(path.dirname(args.upstreamDir), { recursive: true });
  execFileSync("git", [
    "clone",
    "--depth",
    "1",
    "--filter=blob:none",
    "--branch",
    args.ref,
    args.repoURL,
    args.upstreamDir,
  ], { stdio: "inherit" });
}

function git(gitArgs, cwd, options = {}) {
  return execFileSync("git", gitArgs, {
    cwd,
    encoding: "utf8",
    ...options,
  });
}

function listTestFiles(root) {
  const matches = [];
  walk(root, (file) => {
    const relative = path.relative(root, file).split(path.sep).join("/");
    if (relative.includes("/node_modules/")) return;
    if (/\.(test|spec)\.(ts|tsx|mts)$/.test(relative)) {
      matches.push(relative);
    }
  });
  return matches.sort();
}

function walk(dir, visit) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === ".git" || entry.name === "node_modules") continue;
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath, visit);
    } else if (entry.isFile()) {
      visit(fullPath);
    }
  }
}

function groupByPackage(testFiles) {
  const groups = new Map();
  for (const file of testFiles) {
    const key = packageGroupFor(file);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(file);
  }
  return new Map([...groups.entries()].sort(([left], [right]) => left.localeCompare(right)));
}

function packageGroupFor(file) {
  const parts = file.split("/");
  if (parts[0] === "packages" && parts[1]) return parts[1];
  if (parts[0] === "examples" && parts[1]) return `examples/${parts[1]}`;
  return parts[0] || "root";
}

function trackedPackages() {
  const tracked = new Map();
  for (const entry of readProviderLedger()) {
    tracked.set(packageToGroup(entry.name), entry);
  }
  for (const entry of readCoreSnapshots()) {
    tracked.set(packageToGroup(entry.name), entry);
  }
  return tracked;
}

function packageToGroup(packageName) {
  if (packageName === "ai") return "ai";
  return packageName.replace(/^@ai-sdk\//, "");
}

function readProviderLedger() {
  const contents = fs.readFileSync(ledgerPath, "utf8");
  const entries = [];
  const rowPattern = /^\| `(@ai-sdk\/[^`]+)` \| `([^`]+)` \| (.+) \|$/gm;
  let match;
  while ((match = rowPattern.exec(contents)) !== null) {
    entries.push({
      kind: "provider",
      name: match[1],
      version: match[2],
      evidence: stripMarkdown(match[3]),
    });
  }
  return entries;
}

function readCoreSnapshots() {
  if (!fs.existsSync(coreParityPath)) return [];
  const contents = fs.readFileSync(coreParityPath, "utf8");
  const start = contents.indexOf("snapshots, currently ");
  if (start === -1) return [];
  const end = contents.indexOf("\nReferences:", start);
  const snapshotText = contents.slice(start, end === -1 ? undefined : end);

  return [...snapshotText.matchAll(/`([^`]+)`/g)].map((match) => {
    const packageSpec = match[1];
    const separator = packageSpec.lastIndexOf("@");
    return {
      kind: "core",
      name: packageSpec.slice(0, separator),
      version: packageSpec.slice(separator + 1),
      evidence: "Docs/CoreV6Parity.md",
    };
  });
}

function stripMarkdown(value) {
  return value.replace(/`/g, "").trim();
}

function renderMarkdown({ commit, commitLine, testFiles, grouped, tracked }) {
  const trackedGroups = [...grouped.keys()].filter((group) => tracked.has(group));
  const untrackedGroups = [...grouped.keys()].filter((group) => !tracked.has(group));
  const generatedAt = new Date().toISOString();
  const sourceTreeURL = `https://github.com/vercel/ai/tree/${commit}`;

  const lines = [
    "# Upstream Test Inventory",
    "",
    "Generated inventory of test/spec files from the upstream Vercel AI SDK monorepo.",
    "Use it as a review checklist before porting behavior into SwiftAISDK; do not copy tests mechanically when the Swift public surface differs.",
    "",
    "## Snapshot",
    "",
    `- Generated at: ${generatedAt}`,
    `- Upstream ref: \`${args.ref}\``,
    `- Upstream commit: [\`${commit.slice(0, 12)}\`](${sourceTreeURL})`,
    `- Commit line: \`${commitLine}\``,
    `- Total upstream test/spec files: ${testFiles.length}`,
    `- Package/example groups with tests: ${grouped.size}`,
    `- Groups tracked by SwiftAISDK ledger/core snapshot: ${trackedGroups.length}`,
    `- Groups not tracked locally: ${untrackedGroups.length}`,
    "",
    "## Maintenance Plan",
    "",
    "1. Refresh this inventory during the weekly upstream check after version discovery.",
    "2. For each package being ported, inspect every upstream test file listed under that package before editing Swift code.",
    "3. Translate behavior assertions into idiomatic Swift tests, preserving local API differences and existing transport/test helpers.",
    "4. Record intentionally skipped upstream tests in the package sync report when they cover JS-only runtime, framework UI hooks, codemods, or product surfaces SwiftAISDK does not expose.",
    "5. Keep the inventory commit SHA in reports so future diffs can distinguish test drift from implementation drift.",
    "",
    "## Tracked Package Matrix",
    "",
    "| Package group | Upstream package | Baseline | Kind | Upstream tests | Local evidence |",
    "| --- | --- | --- | --- | ---: | --- |",
  ];

  for (const group of [...tracked.keys()].sort()) {
    const entry = tracked.get(group);
    const files = grouped.get(group) || [];
    lines.push(`| \`${group}\` | \`${entry.name}\` | \`${entry.version}\` | ${entry.kind} | ${files.length} | ${entry.evidence} |`);
  }

  lines.push(
    "",
    "## Untracked Upstream Groups With Tests",
    "",
    "These are visible in the upstream monorepo but are not currently tracked in the SwiftAISDK provider ledger or core snapshot. Most are framework adapters, codemods, harnesses, examples, or tooling packages.",
    "",
    "| Group | Tests |",
    "| --- | ---: |",
  );

  for (const group of untrackedGroups) {
    lines.push(`| \`${group}\` | ${grouped.get(group).length} |`);
  }

  lines.push("", "## Test Files By Group", "");
  for (const [group, files] of grouped) {
    const entry = tracked.get(group);
    const title = entry ? `${group} (${entry.name}@${entry.version})` : group;
    lines.push(`### \`${title}\``, "");
    for (const file of files) {
      lines.push(`- [\`${file}\`](https://github.com/vercel/ai/blob/${commit}/${file})`);
    }
    lines.push("");
  }

  return `${lines.join("\n")}\n`;
}
