import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const docsSiteRoot = fileURLToPath(new URL('..', import.meta.url));
const repoRoot = fileURLToPath(new URL('../..', import.meta.url));
const contentRoot = join(docsSiteRoot, 'src/content/docs');
const publicRoot = join(docsSiteRoot, 'public');
const docsBase = process.env.DOCS_BASE ?? '/';
const docsSite = process.env.DOCS_SITE ?? '';

function ensureDir(path) {
  mkdirSync(path, { recursive: true });
}

function writeGenerated(path, body) {
  ensureDir(join(path, '..'));
  writeFileSync(path, body);
}

function normalizedDocsBase() {
  if (!docsBase || docsBase === '/') return '';
  return `/${docsBase.replace(/^\/|\/$/g, '')}`;
}

function publicDocsUrl(slug) {
  const path = `${normalizedDocsBase()}${slug}`;
  if (!docsSite) return path;
  return `${docsSite.replace(/\/$/g, '')}${path}`;
}

function splitMarkdownRow(row) {
  return row
    .trim()
    .replace(/^\|/, '')
    .replace(/\|$/, '')
    .split(/(?<!\\)\|/)
    .map((cell) => cell.trim().replaceAll('\\|', '|'));
}

function readProviderRows() {
  const matrix = readFileSync(
    join(repoRoot, 'Docs/ProviderCapabilityMatrix.md'),
    'utf8',
  );
  const lines = matrix.split('\n');
  const headerIndex = lines.findIndex((line) =>
    line.startsWith('| Upstream package | Provider ID |'),
  );
  if (headerIndex === -1) {
    throw new Error('Could not find provider capability table.');
  }

  const rows = [];
  for (const line of lines.slice(headerIndex + 2)) {
    if (!line.startsWith('| `')) break;
    const [
      upstreamPackage,
      providerID,
      factories,
      language,
      completion,
      embedding,
      image,
      transcription,
      speech,
      video,
      reranking,
      files,
      skills,
    ] = splitMarkdownRow(line);
    rows.push({
      upstreamPackage,
      providerID,
      factories,
      language,
      completion,
      embedding,
      image,
      transcription,
      speech,
      video,
      reranking,
      files,
      skills,
    });
  }
  return rows;
}

function marker(value) {
  return value ? 'yes' : '';
}

function generateProviders() {
  const rows = readProviderRows();
  const capabilityLabels = [
    ['language', 'Language'],
    ['completion', 'Completion'],
    ['embedding', 'Embedding'],
    ['image', 'Image'],
    ['transcription', 'Transcription'],
    ['speech', 'Speech'],
    ['video', 'Video'],
    ['reranking', 'Reranking'],
    ['files', 'Files'],
    ['skills', 'Skills'],
  ];

  const capabilityList = capabilityLabels
    .map(([key, label]) => {
      const count = rows.filter((row) => row[key]).length;
      return `<code>${label}: ${count}</code>`;
    })
    .join('\n');

  const table = rows
    .map(
      (row) =>
        `| ${row.providerID} | ${row.upstreamPackage} | ${row.factories} | ${marker(row.language)} | ${marker(row.embedding)} | ${marker(row.image)} | ${marker(row.transcription)} | ${marker(row.speech)} | ${marker(row.video)} | ${marker(row.reranking)} | ${marker(row.files)} | ${marker(row.skills)} |`,
    )
    .join('\n');

  writeGenerated(
    join(contentRoot, 'providers/index.mdx'),
    `---\ntitle: Provider matrix\ndescription: Generated provider capability overview for SwiftAISDK.\n---\n\n# Provider matrix\n\nThis page is generated from the package capability matrix. Update [ProviderCapabilityMatrix.swift](https://github.com/ozio/SwiftAISDK/blob/main/Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift) first when provider coverage changes.\n\n<div class="capability-grid">\n${capabilityList}\n</div>\n\n| Provider | Upstream package | Swift factories | Language | Embedding | Image | Transcription | Speech | Video | Reranking | Files | Skills |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n${table}\n`,
  );
}

function findSwiftAISDKSymbolGraphs() {
  const root = join(repoRoot, '.build');
  const candidates = [];
  function walk(dir) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(path);
      } else if (entry.name === 'SwiftAISDK.symbols.json') {
        candidates.push(path);
      }
    }
  }
  if (existsSync(root)) {
    walk(root);
  }
  return candidates.sort();
}

function removeExistingSymbolGraphs() {
  for (const path of findSwiftAISDKSymbolGraphs()) {
    rmSync(path);
  }
}

function dumpSymbolGraph() {
  removeExistingSymbolGraphs();
  const result = spawnSync(
    'swift',
    [
      'package',
      'dump-symbol-graph',
      '--skip-synthesized-members',
      '--minimum-access-level',
      'public',
      '--pretty-print',
    ],
    { cwd: repoRoot, encoding: 'utf8' },
  );
  if (result.status !== 0) {
    const emittedGraphs = findSwiftAISDKSymbolGraphs();
    if (emittedGraphs.length > 0) {
      console.warn(
        'swift package dump-symbol-graph returned non-zero after emitting SwiftAISDK.symbols.json; continuing with the library graph.',
      );
      return;
    }
    process.stdout.write(result.stdout);
    process.stderr.write(result.stderr);
    throw new Error('Failed to dump SwiftAISDK symbol graph.');
  }
}

function findSymbolGraphFile() {
  const candidates = findSwiftAISDKSymbolGraphs();
  if (candidates.length === 0) {
    throw new Error('SwiftAISDK.symbols.json was not emitted.');
  }
  return candidates.sort()[0];
}

function declaration(symbol) {
  const fragments =
    symbol.declarationFragments ?? symbol.names?.subHeading ?? [];
  return fragments.map((fragment) => fragment.spelling).join('');
}

function sourcePath(symbol) {
  const uri = symbol.location?.uri;
  if (!uri) return '';
  const filePath = fileURLToPath(uri);
  return relative(repoRoot, filePath);
}

function generateReference() {
  dumpSymbolGraph();
  const symbolGraph = JSON.parse(readFileSync(findSymbolGraphFile(), 'utf8'));
  const symbols = symbolGraph.symbols
    .filter((symbol) => !symbol.accessLevel || symbol.accessLevel === 'public')
    .map((symbol) => ({
      title: symbol.names?.title ?? symbol.identifier?.precise ?? 'Symbol',
      kind: symbol.kind?.displayName ?? symbol.kind?.identifier ?? 'symbol',
      declaration: declaration(symbol),
      path: sourcePath(symbol),
    }))
    .sort((a, b) => `${a.kind}:${a.title}`.localeCompare(`${b.kind}:${b.title}`));

  const counts = new Map();
  for (const symbol of symbols) {
    counts.set(symbol.kind, (counts.get(symbol.kind) ?? 0) + 1);
  }
  const countRows = [...counts.entries()]
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([kind, count]) => `| ${kind} | ${count} |`)
    .join('\n');

  writeGenerated(
    join(contentRoot, 'reference/index.mdx'),
    `---\ntitle: Reference\ndescription: Generated overview of the public SwiftAISDK surface.\n---\n\n# Reference\n\nThe reference layer is generated from Swift symbol graphs. It is useful for exact names, public types, and source ownership, but the guides and cookbook should remain the primary onboarding path.\n\n| Symbol kind | Count |\n| --- | --- |\n${countRows}\n\nContinue to [Public symbols](generated/public-symbols/) for the generated symbol table.\n`,
  );

  const symbolRows = symbols
    .map((symbol) => {
      const declarationText = symbol.declaration
        .replaceAll('|', '\\|')
        .replaceAll('\n', ' ');
      const path = symbol.path
        ? `[${symbol.path}](https://github.com/ozio/SwiftAISDK/blob/main/${symbol.path})`
        : '';
      return `| ${symbol.kind} | \`${symbol.title.replaceAll('`', '')}\` | \`${declarationText.replaceAll('`', '')}\` | ${path} |`;
    })
    .join('\n');

  writeGenerated(
    join(contentRoot, 'reference/generated/public-symbols.mdx'),
    `---\ntitle: Public symbols\ndescription: Generated public SwiftAISDK symbol table.\n---\n\n# Public symbols\n\nThis page is generated by \`npm --prefix docs-site run generate\` from \`swift package dump-symbol-graph\`.\n\n| Kind | Symbol | Declaration | Source |\n| --- | --- | --- | --- |\n${symbolRows}\n`,
  );
}

function collectDocsPages() {
  const pages = [];
  function walk(dir) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(path);
      } else if (entry.name.endsWith('.mdx')) {
        const relativePath = relative(contentRoot, path).replace(/\\/g, '/');
        const slug = relativePath
          .replace(/\/index\.mdx$/, '/')
          .replace(/index\.mdx$/, '')
          .replace(/\.mdx$/, '/');
        const source = readFileSync(path, 'utf8');
        const title =
          source.match(/^title:\s*(.+)$/m)?.[1]?.trim() ??
          slug.replaceAll('/', ' ');
        const description =
          source.match(/^description:\s*(.+)$/m)?.[1]?.trim() ?? '';
        pages.push({ slug: `/${slug}`, title, description, source });
      }
    }
  }
  walk(contentRoot);
  return pages.sort((a, b) => a.slug.localeCompare(b.slug));
}

function generateLLMSFiles() {
  ensureDir(publicRoot);
  const pages = collectDocsPages();
  const llms = [
    '# SwiftAISDK documentation',
    '',
    'SwiftAISDK is a SwiftPM port of the provider-facing Vercel AI SDK.',
    '',
    '## Pages',
    ...pages.map(
      (page) =>
        `- [${page.title}](${publicDocsUrl(page.slug)}): ${page.description}`,
    ),
    '',
  ].join('\n');

  const full = [
    llms,
    ...pages.map(
      (page) =>
        `\n\n# ${page.title}\n\nSource URL: ${publicDocsUrl(page.slug)}\n\n${page.source.replace(/^---[\s\S]*?---\n/, '')}`,
    ),
  ].join('\n');

  writeGenerated(join(publicRoot, 'llms.txt'), llms);
  writeGenerated(join(publicRoot, 'llms-full.txt'), full);
}

generateProviders();
generateReference();
generateLLMSFiles();
