#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execFileSync, spawnSync } = require("child_process");

const repoRoot = path.resolve(__dirname, "..");
const ledgerPath = path.join(repoRoot, "Docs", "ProviderVersionLedger.md");
const coreParityPath = path.join(repoRoot, "Docs", "CoreV6Parity.md");
const defaultWorkDir = "/tmp/ai-sdk-port-upstream-diffs";

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  printHelp();
  process.exit(0);
}

main();

function main() {
  const providers = readProviderLedger();
  const core = args.providersOnly ? [] : readCoreSnapshots();
  if (args.discoverPackages) {
    const tracked = [...providers, ...core];
    const discoveryRows = discoverPackages(tracked).filter((row) =>
      args.discoverKinds.size === 0 || args.discoverKinds.has(row.kind)
    );
    if (args.json) {
      console.log(JSON.stringify(discoveryRows, null, 2));
    } else {
      printDiscoveryTable(args.all ? discoveryRows : discoveryRows.filter((row) => row.status === "untracked"));
    }
    if (args.failOnNew && discoveryRows.some((row) => row.status === "untracked")) {
      process.exitCode = 3;
    }
    return;
  }

  let packages = [...providers, ...core].filter((entry) => shouldInclude(entry.name));

  if (args.from || args.to) {
    if (args.packages.size !== 1) {
      throw new Error("--from/--to requires exactly one --package or positional package name");
    }
    if (!args.from || !args.to) {
      throw new Error("--from and --to must be supplied together");
    }
    const packageName = Array.from(args.packages)[0];
    const found = packages.find((entry) => entry.name === packageName);
    packages = [{
      kind: found?.kind ?? "manual",
      name: packageName,
      current: args.from,
      forcedLatest: args.to,
      evidence: found?.evidence ?? "manual --from/--to",
    }];
  }

  if (packages.length === 0) {
    console.error("No packages matched the requested filters.");
    process.exit(1);
  }

  const rows = packages.map((entry) => {
    const latest = entry.forcedLatest ?? npmViewVersion(entry.name);
    return {
      ...entry,
      latest,
      outdated: latest !== null && latest !== entry.current,
      error: latest === null ? "npm view failed" : null,
    };
  });

  if (args.json) {
    console.log(JSON.stringify(rows, null, 2));
  } else {
    printTable(args.all ? rows : rows.filter((row) => row.outdated || row.error));
  }

  if (args.prepareDiffs) {
    const changed = rows.filter((row) => row.outdated && !row.error);
    if (changed.length === 0) {
      console.error("No changed packages to diff.");
      return;
    }

    fs.mkdirSync(args.workDir, { recursive: true });
    for (const row of changed) {
      preparePackageDiff(row, args.workDir);
    }
  }

  if (args.failOnOutdated && rows.some((row) => row.outdated || row.error)) {
    process.exitCode = 2;
  }
}

function parseArgs(rawArgs) {
  const parsed = {
    all: false,
    discoverKinds: new Set(),
    discoverPackages: false,
    failOnOutdated: false,
    failOnNew: false,
    from: null,
    help: false,
    json: false,
    packages: new Set(),
    prepareDiffs: false,
    providersOnly: false,
    to: null,
    workDir: defaultWorkDir,
  };

  for (let index = 0; index < rawArgs.length; index += 1) {
    const arg = rawArgs[index];
    switch (arg) {
      case "--all":
        parsed.all = true;
        break;
      case "--discover-packages":
        parsed.discoverPackages = true;
        break;
      case "--discover-kind":
      case "--kind": {
        const value = rawArgs[index + 1];
        if (!value) {
          throw new Error(`${arg} requires a comma-separated kind list`);
        }
        index += 1;
        for (const kind of value.split(",")) {
          if (kind.trim()) parsed.discoverKinds.add(kind.trim());
        }
        break;
      }
      case "--fail-on-outdated":
        parsed.failOnOutdated = true;
        break;
      case "--fail-on-new":
        parsed.failOnNew = true;
        break;
      case "--from": {
        const value = rawArgs[index + 1];
        if (!value) {
          throw new Error("--from requires a version");
        }
        index += 1;
        parsed.from = value;
        break;
      }
      case "--help":
      case "-h":
        parsed.help = true;
        break;
      case "--json":
        parsed.json = true;
        break;
      case "--prepare-diffs":
        parsed.prepareDiffs = true;
        break;
      case "--providers-only":
        parsed.providersOnly = true;
        break;
      case "--to": {
        const value = rawArgs[index + 1];
        if (!value) {
          throw new Error("--to requires a version");
        }
        index += 1;
        parsed.to = value;
        break;
      }
      case "--package":
      case "-p": {
        const value = rawArgs[index + 1];
        if (!value) {
          throw new Error(`${arg} requires a package name`);
        }
        index += 1;
        for (const name of value.split(",")) {
          if (name.trim()) parsed.packages.add(name.trim());
        }
        break;
      }
      case "--work-dir": {
        const value = rawArgs[index + 1];
        if (!value) {
          throw new Error("--work-dir requires a path");
        }
        index += 1;
        parsed.workDir = path.resolve(value);
        break;
      }
      default:
        if (arg.startsWith("--")) {
          throw new Error(`Unknown option: ${arg}`);
        }
        parsed.packages.add(arg);
        break;
    }
  }

  return parsed;
}

function shouldInclude(packageName) {
  return args.packages.size === 0 || args.packages.has(packageName);
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
      current: match[2],
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

  const packageSpecs = [...snapshotText.matchAll(/`([^`]+)`/g)].map((match) => match[1]);
  return packageSpecs.map((packageSpec) => {
    const separator = packageSpec.lastIndexOf("@");
    if (separator <= 0) {
      throw new Error(`Invalid core package snapshot: ${packageSpec}`);
    }
    const packageName = packageSpec.slice(0, separator);
    const version = packageSpec.slice(separator + 1);
    return {
      kind: "core",
      name: packageName,
      current: version,
      evidence: "Docs/CoreV6Parity.md",
    };
  });
}

function discoverPackages(trackedPackages) {
  const tracked = new Map(trackedPackages.map((entry) => [entry.name, entry]));
  const packages = npmSearchAISDKPackages();
  return packages.map((pkg) => {
    const trackedEntry = tracked.get(pkg.name);
    return {
      kind: classifyDiscoveredPackage(pkg),
      name: pkg.name,
      version: pkg.version || "-",
      status: trackedEntry ? `tracked-${trackedEntry.kind}` : "untracked",
      description: oneLine(pkg.description || ""),
    };
  }).sort((lhs, rhs) => {
    if (lhs.status !== rhs.status) return lhs.status === "untracked" ? -1 : 1;
    if (lhs.kind !== rhs.kind) return lhs.kind.localeCompare(rhs.kind);
    return lhs.name.localeCompare(rhs.name);
  });
}

function npmSearchAISDKPackages() {
  const output = execFileSync("npm", ["search", "--json", "--searchlimit=250", "--scope=@ai-sdk", "ai-sdk"], {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  const parsed = JSON.parse(output);
  const byName = new Map();
  for (const pkg of parsed) {
    if (!pkg.name || !pkg.name.startsWith("@ai-sdk/")) continue;
    byName.set(pkg.name, pkg);
  }
  return Array.from(byName.values());
}

function classifyDiscoveredPackage(pkg) {
  const name = pkg.name;
  const shortName = name.replace("@ai-sdk/", "");
  const description = (pkg.description || "").toLowerCase();
  const uiPackages = new Set(["angular", "react", "rsc", "solid", "svelte", "vue", "ui-utils"]);
  const toolingPackages = new Set(["codemod", "devtools"]);
  const schemaPackages = new Set(["valibot"]);
  const corePackages = new Set(["provider", "provider-utils"]);
  const adapterPackages = new Set(["langchain", "llamaindex", "workflow"]);

  if (corePackages.has(shortName)) return "core";
  if (adapterPackages.has(shortName) || description.includes("adapter")) return "adapter";
  if (uiPackages.has(shortName)) return "ui";
  if (toolingPackages.has(shortName)) return "tooling";
  if (schemaPackages.has(shortName)) return "schema";
  if (description.includes("provider")) return "provider";
  return "unknown";
}

function npmViewVersion(packageName) {
  try {
    return execFileSync("npm", ["view", packageName, "version"], {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (error) {
    return null;
  }
}

function preparePackageDiff(row, workDir) {
  const packageDir = path.join(workDir, sanitizePackageName(row.name), `${row.current}..${row.latest}`);
  const packDir = path.join(packageDir, "packs");
  const oldDir = path.join(packageDir, "old");
  const newDir = path.join(packageDir, "new");
  const diffPath = path.join(packageDir, "upstream.diff");
  const summaryPath = path.join(packageDir, "summary.md");

  fs.rmSync(packageDir, { recursive: true, force: true });
  fs.mkdirSync(packDir, { recursive: true });
  fs.mkdirSync(oldDir, { recursive: true });
  fs.mkdirSync(newDir, { recursive: true });

  console.error(`Preparing diff for ${row.name} ${row.current} -> ${row.latest}`);
  const oldPack = npmPack(row.name, row.current, packDir);
  const newPack = npmPack(row.name, row.latest, packDir);

  extractTarball(oldPack, oldDir);
  extractTarball(newPack, newDir);

  const diff = runDiff(oldDir, newDir);
  fs.writeFileSync(diffPath, diff, "utf8");
  fs.writeFileSync(summaryPath, makeSummary(row, packageDir, diffPath), "utf8");

  console.error(`  wrote ${diffPath}`);
}

function npmPack(packageName, version, destination) {
  const output = execFileSync("npm", ["pack", `${packageName}@${version}`, "--pack-destination", destination, "--json"], {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  const parsed = JSON.parse(output);
  const filename = parsed[0] && parsed[0].filename;
  if (!filename) {
    throw new Error(`npm pack did not return a filename for ${packageName}@${version}`);
  }
  return path.join(destination, filename);
}

function extractTarball(tarballPath, destination) {
  execFileSync("tar", ["-xzf", tarballPath, "-C", destination, "--strip-components=1"], {
    cwd: repoRoot,
    stdio: "ignore",
  });
}

function runDiff(oldDir, newDir) {
  const result = spawnSync(
    "diff",
    [
      "-ruN",
      "--exclude=package.tgz",
      "--exclude=*.map",
      "--exclude=*.d.ts.map",
      oldDir,
      newDir,
    ],
    {
      cwd: repoRoot,
      encoding: "utf8",
    }
  );

  if (result.status !== 0 && result.status !== 1) {
    throw new Error(result.stderr || `diff failed with status ${result.status}`);
  }

  return result.stdout;
}

function makeSummary(row, packageDir, diffPath) {
  return [
    `# ${row.name} ${row.current} -> ${row.latest}`,
    "",
    `Kind: ${row.kind}`,
    `Swift evidence: ${row.evidence}`,
    `Package work dir: ${packageDir}`,
    `Diff: ${diffPath}`,
    "",
    "## Port Notes",
    "",
    "- Upstream files changed:",
    "- Swift surfaces to inspect:",
    "- Tests to add/update:",
    "- Docs/version rows to update:",
    "",
  ].join("\n");
}

function printTable(rows) {
  if (rows.length === 0) {
    console.log("All checked packages match npm latest.");
    return;
  }

  const headers = ["kind", "package", "current", "latest", "status"];
  const data = rows.map((row) => [
    row.kind,
    row.name,
    row.current,
    row.latest || "-",
    row.error ? row.error : row.outdated ? "outdated" : "current",
  ]);
  const widths = headers.map((header, index) =>
    Math.max(header.length, ...data.map((row) => row[index].length))
  );

  console.log(formatRow(headers, widths));
  console.log(formatRow(widths.map((width) => "-".repeat(width)), widths));
  for (const row of data) {
    console.log(formatRow(row, widths));
  }
}

function printDiscoveryTable(rows) {
  if (rows.length === 0) {
    console.log("No untracked @ai-sdk packages found.");
    return;
  }

  const headers = ["kind", "package", "version", "status", "description"];
  const data = rows.map((row) => [
    row.kind,
    row.name,
    row.version,
    row.status,
    row.description,
  ]);
  const widths = headers.map((header, index) =>
    Math.min(72, Math.max(header.length, ...data.map((row) => row[index].length)))
  );

  console.log(formatRow(headers, widths));
  console.log(formatRow(widths.map((width) => "-".repeat(width)), widths));
  for (const row of data) {
    console.log(formatRow(row.map((value, index) => truncate(value, widths[index])), widths));
  }
}

function formatRow(values, widths) {
  return values.map((value, index) => value.padEnd(widths[index])).join("  ");
}

function stripMarkdown(value) {
  return value.replace(/`/g, "").trim();
}

function oneLine(value) {
  return value.replace(/\s+/g, " ").trim();
}

function truncate(value, width) {
  if (value.length <= width) return value;
  return `${value.slice(0, Math.max(0, width - 1))}…`;
}

function sanitizePackageName(packageName) {
  return packageName.replace(/^@/, "").replace(/[\/@]/g, "__");
}

function printHelp() {
  console.log(`Usage: node Scripts/check-upstream-versions.js [options] [package...]

Checks provider versions from Docs/ProviderVersionLedger.md and core snapshots
from Docs/CoreV6Parity.md against npm latest.

Options:
  -p, --package <name>   Check only one package. Can be repeated or comma-separated.
      --all              Show current packages too. Default output shows drift only.
      --json             Print machine-readable JSON.
      --providers-only   Skip core snapshot packages.
      --prepare-diffs    Download old/latest tarballs and write upstream.diff files.
      --discover-packages
                         Discover official @ai-sdk/* packages missing from local tracking.
      --discover-kind <kind[,kind]>
                         Filter discovery by kind, e.g. provider,adapter,core.
      --from <version>   Force old version for a single package diff/check.
      --to <version>     Force new version for a single package diff/check.
      --fail-on-outdated Exit with status 2 when drift or npm errors are found.
      --fail-on-new      With --discover-packages, exit with status 3 when untracked packages are found.
      --work-dir <path>  Diff output directory. Default: ${defaultWorkDir}
  -h, --help             Show this help.

Examples:
  node Scripts/check-upstream-versions.js
  node Scripts/check-upstream-versions.js --all --json
  node Scripts/check-upstream-versions.js --discover-packages
  node Scripts/check-upstream-versions.js --discover-packages --discover-kind provider,adapter,core --fail-on-new
  node Scripts/check-upstream-versions.js -p @ai-sdk/openai --prepare-diffs
  node Scripts/check-upstream-versions.js -p @ai-sdk/openai --from 3.0.69 --to 3.0.71 --prepare-diffs
`);
}
