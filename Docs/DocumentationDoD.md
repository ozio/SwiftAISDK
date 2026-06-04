# Documentation Definition Of Done

SwiftAISDK documentation is done when the docs are useful to a new user, kept in
sync with the package, and deployable without hand steps.

## Required Scope

1. `docs-site` exists as a static MDX documentation site with navigation modeled
   after the upstream AI SDK docs: start, core, cookbook, providers, reference,
   parity, and troubleshooting.
2. The first user-facing pages are present and written as guides, not method
   listings: install, quickstart, generate text, stream text, structured output,
   tools, MCP tools, providers, reference, parity, and troubleshooting.
3. Runnable Swift examples exist for the core recipes and compile against the
   local package.
4. Generated docs exist for provider capabilities, public symbol reference, and
   LLM-friendly `llms.txt`/`llms-full.txt`.
5. GitHub Pages deployment is wired so pushes to `main` can build and publish the
   static site.

## Verification Gates

- `swift build`
- `swift build --package-path Examples`
- `npm ci --prefix docs-site`
- `npm --prefix docs-site run generate`
- `npm --prefix docs-site run build`
- Local browser review of the built or dev site on desktop and mobile widths.

## Quality Bar

- The first screen tells users what to do next.
- Main workflows have copy, code, expected result shape, and links to deeper
  reference.
- Reference pages are generated, but they are not the primary onboarding path.
- Generated files fail loudly when source artifacts are missing.
- Layout has no obvious text overlap, clipped buttons, broken navigation, or
  unreadable color contrast.
