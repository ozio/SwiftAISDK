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
          ],
        },
        {
          label: 'Cookbook',
          items: [{ label: 'MCP tools', slug: 'cookbook/mcp-tools' }],
        },
        {
          label: 'Providers',
          items: [{ label: 'Provider matrix', slug: 'providers' }],
        },
        {
          label: 'Reference',
          items: [
            { label: 'Overview', slug: 'reference' },
            {
              label: 'Public symbols',
              slug: 'reference/generated/public-symbols',
            },
          ],
        },
        {
          label: 'Project',
          items: [
            { label: 'Upstream parity', slug: 'upstream-parity' },
            { label: 'Troubleshooting', slug: 'troubleshooting' },
          ],
        },
      ],
    }),
  ],
});
