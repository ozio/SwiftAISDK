import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import remarkGfm from 'remark-gfm';

const base = process.env.DOCS_BASE ?? '/';
const site = process.env.DOCS_SITE ?? 'https://ozio.github.io';

export default defineConfig({
  site,
  base,
  markdown: {
    remarkPlugins: [remarkGfm],
  },
  integrations: [
    starlight({
      title: 'SwiftAISDK',
      description: 'SwiftPM port of the provider-facing Vercel AI SDK.',
      customCss: ['./src/styles/custom.css'],
      editLink: {
        baseUrl:
          'https://github.com/ozio/SwiftAISDK/edit/main/docs-site/',
      },
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/ozio/SwiftAISDK',
        },
      ],
      sidebar: [
        {
          label: 'Start',
          items: [
            { label: 'Introduction', slug: '' },
            { label: 'Install', slug: 'getting-started/install' },
            { label: 'Quickstart', slug: 'getting-started/quickstart' },
          ],
        },
        {
          label: 'Core',
          items: [
            { label: 'Generate text', slug: 'core/generate-text' },
            { label: 'Stream text', slug: 'core/stream-text' },
            { label: 'Structured output', slug: 'core/structured-output' },
            { label: 'Tools', slug: 'core/tools' },
            { label: 'Embeddings', slug: 'core/embeddings' },
            { label: 'Generate image', slug: 'core/generate-image' },
            { label: 'Transcribe audio', slug: 'core/transcribe' },
            { label: 'Generate speech', slug: 'core/generate-speech' },
            { label: 'Generate audio', slug: 'core/generate-audio' },
            { label: 'Transform audio', slug: 'core/transform-audio' },
            { label: 'Dubbing', slug: 'core/dubbing' },
            { label: 'Generate video', slug: 'core/generate-video' },
            { label: 'Rerank', slug: 'core/rerank' },
            { label: 'Error handling', slug: 'core/error-handling' },
            { label: 'Telemetry', slug: 'core/telemetry' },
          ],
        },
        {
          label: 'Cookbook',
          items: [{ label: 'MCP tools', slug: 'cookbook/mcp-tools' }],
        },
        {
          label: 'Components',
          items: [{ label: 'Components', slug: 'components' }],
        },
        {
          label: 'Providers',
          items: [{ label: 'Provider matrix', slug: 'providers' }],
        },
        {
          label: 'Reference',
          items: [
            {
              label: 'Public symbols',
              slug: 'reference/generated/public-symbols',
            },
          ],
        },
        {
          label: 'Project',
          items: [
            { label: 'Troubleshooting', slug: 'troubleshooting' },
          ],
        },
      ],
    }),
  ],
});
