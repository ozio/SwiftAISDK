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

function stripCodeTicks(value) {
  return value.replaceAll('`', '');
}

function readProviderRows() {
  const matrix = readFileSync(
    join(repoRoot, 'Docs/ProviderCapabilityMatrix.md'),
    'utf8',
  );
  const lines = matrix.split('\n');
  const notes = new Map();
  const notesHeaderIndex = lines.findIndex((line) =>
    line.startsWith('| Provider ID | Note |'),
  );
  if (notesHeaderIndex !== -1) {
    for (const line of lines.slice(notesHeaderIndex + 2)) {
      if (!line.startsWith('| `')) break;
      const [providerID, note] = splitMarkdownRow(line);
      notes.set(providerID.replaceAll('`', ''), note);
    }
  }
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
      upstreamPackageCell,
      providerIDCell,
      factories,
      language,
      completion,
      embedding,
      image,
      transcription,
      speech,
      audioGeneration,
      audioTransformation,
      dubbing,
      video,
      reranking,
      files,
      skills,
    ] = splitMarkdownRow(line);
    const upstreamPackage = stripCodeTicks(upstreamPackageCell);
    const providerID = stripCodeTicks(providerIDCell);
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
      audioGeneration,
      audioTransformation,
      dubbing,
      video,
      reranking,
      files,
      skills,
      notes: notes.get(providerID) ?? '',
    });
  }
  return rows;
}

function marker(value) {
  return value ? '✅' : '';
}

function slugify(value) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

function providerSlug(providerID) {
  return slugify(providerID);
}

function yamlString(value) {
  return JSON.stringify(value);
}

function generateProviders() {
  const rows = readProviderRows();
  const providersRoot = join(contentRoot, 'providers');
  if (existsSync(providersRoot)) {
    for (const entry of readdirSync(providersRoot, { withFileTypes: true })) {
      if (entry.isFile() && entry.name !== 'index.mdx' && entry.name.endsWith('.mdx')) {
        rmSync(join(providersRoot, entry.name));
      }
    }
  }
  const capabilityLabels = [
    ['language', 'Language'],
    ['completion', 'Completion'],
    ['embedding', 'Embedding'],
    ['image', 'Image'],
    ['transcription', 'Transcription'],
    ['speech', 'Speech'],
    ['audioGeneration', 'Audio generation'],
    ['audioTransformation', 'Audio transformation'],
    ['dubbing', 'Dubbing'],
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
        `| [\`${row.providerID}\`](${providerSlug(row.providerID)}/) | \`${row.upstreamPackage}\` | ${row.factories} | ${marker(row.language)} | ${marker(row.embedding)} | ${marker(row.image)} | ${marker(row.transcription)} | ${marker(row.speech)} | ${marker(row.audioGeneration)} | ${marker(row.audioTransformation)} | ${marker(row.dubbing)} | ${marker(row.video)} | ${marker(row.reranking)} | ${marker(row.files)} | ${marker(row.skills)} |`,
    )
    .join('\n');

  writeGenerated(
    join(contentRoot, 'providers/index.mdx'),
    `---\ntitle: Provider matrix\ndescription: Generated provider capability overview for SwiftAISDK.\n---\n\nThis page is generated from the package capability matrix. Update [ProviderCapabilityMatrix.swift](https://github.com/ozio/SwiftAISDK/blob/main/Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift) first when provider coverage changes.\n\n<div class="capability-grid">\n${capabilityList}\n</div>\n\n| Provider | Upstream package | Swift factories | Language | Embedding | Image | Transcription | Speech | Audio generation | Audio transformation | Dubbing | Video | Reranking | Files | Skills |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n${table}\n`,
  );

  for (const row of rows) {
    const capabilities = [
      ['Language', row.language],
      ['Completion', row.completion],
      ['Embedding', row.embedding],
      ['Image', row.image],
      ['Transcription', row.transcription],
      ['Speech', row.speech],
      ['Audio generation', row.audioGeneration],
      ['Audio transformation', row.audioTransformation],
      ['Dubbing', row.dubbing],
      ['Video', row.video],
      ['Reranking', row.reranking],
      ['Files', row.files],
      ['Skills', row.skills],
    ].filter(([, supported]) => supported);
    const capabilityListText = capabilities.length
      ? capabilities.map(([label]) => `- ${label}`).join('\n')
      : '- No capabilities recorded yet.';
    const note = row.notes ? `\n## Notes\n\n${row.notes}\n` : '';
    writeGenerated(
      join(contentRoot, `providers/${providerSlug(row.providerID)}.mdx`),
      `---\ntitle: ${yamlString(row.providerID)}\ndescription: ${yamlString(`${row.providerID} provider capabilities and factories.`)}\n---\n\n## Package\n\n\`${row.upstreamPackage}\`\n\n## Factories\n\n${row.factories}\n\n## Capabilities\n\n${capabilityListText}\n${note}\nFactory argument requirements are defined by the public Swift factory signatures. Use [Public symbols](../reference/generated/public-symbols/) when you need the exact initializer or factory declaration.\n\nReturn to the [provider matrix](./).\n`,
    );
  }
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

function componentForPath(path) {
  if (path.includes('/Providers/') || path.includes('Provider')) return 'Providers';
  if (path.includes('/Models/')) return 'Provider models';
  if (path.includes('MCP')) return 'MCP';
  if (path.includes('Middleware')) return 'Middleware';
  if (path.includes('AIChat') || path.includes('AIUI')) return 'Chat and UI messages';
  if (path.includes('Telemetry')) return 'Telemetry';
  if (path.includes('Object') || path.includes('Output')) return 'Structured output';
  if (path.includes('Tool')) return 'Tools';
  if (path.includes('Media') || path.includes('Image')) return 'Media';
  if (path.includes('Audio') || path.includes('Transcription') || path.includes('Speech')) return 'Audio';
  if (path.includes('Video') || path.includes('Reranking')) return 'Video and reranking';
  if (path.includes('Error')) return 'Errors';
  if (path.includes('Core') || path.includes('AI.swift') || path.includes('JSON') || path.includes('HTTP')) return 'Core runtime';
  return 'Core runtime';
}

function generateComponents(symbols) {
  const componentsRoot = join(contentRoot, 'components');
  if (existsSync(componentsRoot)) {
    rmSync(componentsRoot, { recursive: true, force: true });
  }
  const groups = new Map();
  for (const symbol of symbols) {
    const component = componentForPath(symbol.path);
    if (!groups.has(component)) groups.set(component, []);
    groups.get(component).push(symbol);
  }

  const overviewRows = [...groups.entries()]
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([component, componentSymbols]) => {
      const slug = slugify(component);
      return `| [${component}](${slug}/) | ${componentSymbols.length} |`;
    })
    .join('\n');

  writeGenerated(
    join(contentRoot, 'components/index.mdx'),
    `---\ntitle: Components\ndescription: Generated component map for SwiftAISDK public APIs.\n---\n\nSwiftAISDK groups public APIs into component areas so you can browse exact types without starting from the full symbol table.\n\n| Component | Public symbols |\n| --- | --- |\n${overviewRows}\n`,
  );

  for (const [component, componentSymbols] of [...groups.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
    const kindCounts = new Map();
    for (const symbol of componentSymbols) {
      kindCounts.set(symbol.kind, (kindCounts.get(symbol.kind) ?? 0) + 1);
    }
    const counts = [...kindCounts.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([kind, count]) => `| ${kind} | ${count} |`)
      .join('\n');
    const symbolRows = componentSymbols
      .slice()
      .sort((a, b) => `${a.kind}:${a.title}`.localeCompare(`${b.kind}:${b.title}`))
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
      join(contentRoot, `components/${slugify(component)}.mdx`),
      `---\ntitle: ${component}\ndescription: Public SwiftAISDK APIs for ${component.toLowerCase()}.\n---\n\n## Symbol counts\n\n| Symbol kind | Count |\n| --- | --- |\n${counts}\n\n## Public symbols\n\n| Kind | Symbol | Declaration | Source |\n| --- | --- | --- | --- |\n${symbolRows}\n`,
    );
  }
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
    `---\ntitle: Public symbols\ndescription: Generated public SwiftAISDK symbol table.\n---\n\nThis page is generated by \`npm --prefix docs-site run generate\` from \`swift package dump-symbol-graph\`.\n\n| Kind | Symbol | Declaration | Source |\n| --- | --- | --- | --- |\n${symbolRows}\n`,
  );

  generateComponents(symbols);
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
        pages.push({ slug: `/${slug}`, title, description, source, path });
      }
    }
  }
  walk(contentRoot);
  return pages.sort((a, b) => a.slug.localeCompare(b.slug));
}

function llmsPagePath(slug) {
  if (slug === '/') return '/llms/index.txt';
  return `/llms/${slug.replace(/^\/|\/$/g, '')}.txt`;
}

function stripFrontmatter(source) {
  return source.replace(/^---[\s\S]*?---\n/, '');
}

function expandRawCodeImports(source, pagePath) {
  const imports = new Map();
  let expanded = source.replace(
    /^import\s+(\w+)\s+from\s+['"](.+[?]raw)['"];\n?/gm,
    (_, name, importPath) => {
      const filePath = importPath.replace(/[?]raw$/, '');
      imports.set(name, readFileSync(join(pagePath, '..', filePath), 'utf8').trimEnd());
      return '';
    },
  );
  expanded = expanded.replace(/^import\s+.*\s+from\s+['"][^'"]+['"];\n?/gm, '');
  expanded = expanded.replace(
    /^<Code\s+code={(\w+)}\s+lang="([^"]+)"\s+title="([^"]+)"\s*\/>$/gm,
    (_, name, lang, title) => {
      const code = imports.get(name);
      if (!code) return '';
      return `\`\`\`${lang} title="${title}"\n${code}\n\`\`\``;
    },
  );
  return expanded;
}

function markdownForLLM(source, pagePath) {
  let inCodeFence = false;
  const text = stripFrontmatter(expandRawCodeImports(source, pagePath))
    .replace(/<\/?(?:a|div|p|span|strong|code)[^>]*>/g, '')
    .split('\n')
    .map((line) => {
      if (line.trim().startsWith('```')) {
        inCodeFence = !inCodeFence;
        return line.trimEnd();
      }
      return inCodeFence ? line.trimEnd() : line.trim();
    })
    .join('\n')
    .replace(/^\s+$/gm, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  return text;
}

function llmsPageBody(page) {
  return [
    `# ${page.title}`,
    '',
    `Source URL: ${publicDocsUrl(page.slug)}`,
    '',
    markdownForLLM(page.source, page.path),
    '',
  ].join('\n');
}

function generateLLMSFiles() {
  ensureDir(publicRoot);
  const pages = collectDocsPages();
  const llmsRoot = join(publicRoot, 'llms');
  const llmsFullPath = join(publicRoot, 'llms-full.txt');
  if (existsSync(llmsRoot)) {
    rmSync(llmsRoot, { recursive: true, force: true });
  }
  if (existsSync(llmsFullPath)) {
    rmSync(llmsFullPath);
  }
  for (const page of pages) {
    writeGenerated(
      join(publicRoot, llmsPagePath(page.slug)),
      llmsPageBody(page),
    );
  }

  const llms = [
    '# SwiftAISDK documentation',
    '',
    'SwiftAISDK is a SwiftPM port of the provider-facing Vercel AI SDK.',
    '',
    '## LLM-readable pages',
    ...pages.map(
      (page) =>
        `- [${page.title}](${publicDocsUrl(llmsPagePath(page.slug))}): ${page.description}`,
    ),
    '',
  ].join('\n');

  writeGenerated(join(publicRoot, 'llms.txt'), llms);
}

generateProviders();
generateReference();
generateLLMSFiles();
