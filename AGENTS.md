# Repository Guidelines

## Project Structure & Module Organization

This repository currently contains product and architecture documentation plus static UI previews. Core docs live in `docs/`: `ARCHITECTURE.md` explains system concepts, `IMPLEMENTATION.md` tracks the phased roadmap, `schema.sql` captures database shape, and `STAGE0_*` files record audit/spec work. Detailed module designs are in `docs/modules/`. Static design previews are in `docs/uiux-preview/` as standalone HTML pages.

The docs now describe a future split into `siriusx-control-plane` and `siriusx-sandbox-runtime`; keep new guidance aligned with that boundary.

## Build, Test, and Development Commands

There is no application build pipeline committed yet. Use these commands for the current repository:

```bash
open docs/uiux-preview/index.html
python3 -m http.server 8080 --directory docs/uiux-preview
git diff --check
```

`open` previews the static UI locally on macOS. The HTTP server is useful when browser security rules block local-file behavior. `git diff --check` catches trailing whitespace before review.

## Coding Style & Naming Conventions

Keep Markdown concise, link related documents with relative paths, and preserve existing terminology: `Task`, `Run`, `Worker`, `Sandbox`, `TaskStore`, and `ResultBus`. Existing module documents use descriptive Chinese filenames under `docs/modules/`; keep new module docs there and name them by domain area. Static preview pages use lowercase kebab-case names, for example `task-detail.html`.

No formatter or linter config is currently present. For future TypeScript code, follow the documented stack: Bun, NestJS, Next.js, and Tailwind CSS.

## Testing Guidelines

Automated tests are specified but not yet implemented. Use `docs/modules/测试场景清单.md` as the source of truth for planned unit, integration, and E2E coverage. Future test files should follow the documented patterns, such as `*.test.ts`, colocated with the module being tested. For UI preview changes, manually inspect the affected HTML page in a desktop and narrow mobile viewport.

## Commit & Pull Request Guidelines

`main` has no commits yet, so there is no established history convention. Use short imperative subjects with an optional scope, for example `docs: update task lifecycle spec` or `ui: adjust history preview`. Pull requests should describe the changed docs or preview pages, link related issues/spec sections, and include screenshots for visual changes.

## Security & Configuration Notes

Do not commit secrets, local credentials, or cloud resource identifiers. Keep tenant isolation, auth boundaries, and S3 path-guard assumptions aligned with the architecture and stage 0 specs.
