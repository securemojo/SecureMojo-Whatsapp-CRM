# SecureMojo CRM

WhatsApp-first CRM for SecureMojo — shared team inbox, contacts,
sales pipelines, broadcasts, and no-code automations built on the
official WhatsApp Business API.

<p align="center">
  <img src="./public/securemojo-logo.png" alt="SecureMojo" width="110">
</p>

Production: [securemojo.in](https://securemojo.in) ·
Next.js 16 · Supabase · Meta Cloud API

---

## Overview

SecureMojo CRM lets a whole team work one WhatsApp Business number:
conversations arrive in a shared inbox, get assigned to agents, feed
sales pipelines, and can trigger automations — all backed by a single
Postgres database with row-level security. It is an internal product,
customised and operated by SecureMojo on top of an MIT-licensed
foundation.

## Features

- Shared inbox — multiple agents on one number, per-conversation
  assignment, status tracking, and internal notes
- Contacts — tags, custom fields, CSV import, automatic
  phone-number deduplication
- Sales pipelines — Kanban boards with deals linked to conversations,
  per-account currency
- Broadcasts — Meta-approved template campaigns with delivery and
  read tracking, per-recipient variable substitution
- Automations and flows — visual builders with triggers (inbound
  message, keyword, new contact, schedule), conditional branches,
  waits, tag actions, and outbound webhooks
- AI assistant — provider key stored encrypted per account;
  AI-drafted replies, an optional auto-reply bot with human handoff,
  and a knowledge base with hybrid full-text / semantic retrieval
- Dashboard — response times, daily volume, pipeline value, and a
  cross-module activity feed in real time
- Team accounts — invitation links with role-based access
  (owner, admin, agent, viewer) and ownership transfer
- Notifications — in-app notification center with unread badges
- Public REST API — versioned endpoints under `/api/v1`, authenticated
  with scoped, revocable API keys (see [docs/public-api.md](./docs/public-api.md))
- MCP server — control the CRM from AI assistants over the Model
  Context Protocol; read-only by default (see [docs/mcp.md](./docs/mcp.md)
  and [`mcp-server/`](./mcp-server))

## Stack

| Layer | Technology |
| --- | --- |
| Application | Next.js 16 (App Router), React 19, TypeScript |
| Styling | Tailwind CSS v4, shadcn/ui components |
| Data | Supabase — Postgres, Auth, Storage, RLS on every table |
| Messaging | Meta Cloud API (official WhatsApp Business API) |
| Internationalisation | next-intl (English, Korean) |
| Testing | Vitest, colocated `*.test.ts` files |

## Project structure

```
src/
  app/            Routes — (auth), (dashboard), api/ (internal + v1)
  components/     Feature-organised UI (inbox, contacts, flows, ...)
  lib/            Domain logic — whatsapp/, automations/, ai/, auth/
  i18n/           Locale plumbing (messages live in /messages)
supabase/
  migrations/     Numbered SQL migrations — the full schema history
mcp-server/       Standalone MCP server package
docs/             Public API and MCP documentation
```

Conventions worth knowing before contributing:

- Server-side domain logic lives in `src/lib/<domain>`, with tests
  next to the code. UI components live in `src/components/<feature>`.
- All user-facing strings go through next-intl message catalogs in
  `messages/`. Strings containing raw HTML or WhatsApp `{{n}}`
  variables must be rendered with `t.raw()`, not `t()`.
- This Next.js version ships its own docs in
  `node_modules/next/dist/docs/` — consult them rather than assuming
  older App Router behaviour (see `AGENTS.md`).

## Getting started

Prerequisites: Node.js 20+, a Supabase project, and access to the
team's Meta Business assets.

```bash
git clone https://github.com/securemojo/Whatsapp-CRM.git
cd Whatsapp-CRM
npm install
cp .env.local.example .env.local
npm run dev
```

Fill `.env.local` from [`.env.local.example`](./.env.local.example) —
the example file documents every variable and which features need it.
Values for the shared environments are held by the team, not in the
repository.

Rules that protect everyone:

- `.env.local` is git-ignored and must stay that way. Production
  configuration lives in the hosting panel, never in the repo.
- The token-encryption key must be identical across environments that
  share a database. Do not rotate it casually; stored credentials
  become unreadable and have to be re-saved.

## Database

The entire schema is expressed as ordered SQL migrations in
[`supabase/migrations/`](./supabase/migrations). Apply them in numeric
order (Supabase SQL editor or `supabase db push`). Notes:

- Migrations are append-only. Never edit an applied migration; add a
  new one.
- The deduplication migrations run a merge function on apply and
  return a merged-row count — a `0` result is normal on clean data.
- Some features assume later migrations (API keys, notifications,
  AI assistant, interactive messages); a partially migrated database
  will fail at runtime, not at startup.

## Development workflow

```bash
npm run dev          # local dev server (localhost:3000)
npm run build        # production build
npm run typecheck    # tsc --noEmit
npm run lint         # eslint
npm test             # vitest run
npm run format       # prettier --write .
```

Run `typecheck`, `lint`, and `test` before pushing — CI runs the same
checks on every push to `main`.

## Deployment

The `main` branch auto-deploys to production. Practical implications:

- Treat `main` as deployable at all times; do feature work on
  branches and merge when green.
- Environment variables, build command (`npm run build`), and start
  command (`npm start`) are configured in the hosting panel.
- The WhatsApp webhook endpoint must be publicly reachable over
  HTTPS; Meta-side webhook configuration is managed in the team's
  Meta App Dashboard and verified from Settings → WhatsApp inside
  the app.

## Security notes

- Secrets never enter the repository — no keys, tokens, or `.env`
  files in commits, issues, or screenshots.
- WhatsApp access tokens are stored AES-256-GCM encrypted; inbound
  webhooks are HMAC-verified; every table carries RLS policies;
  public API keys are hashed at rest and scoped.
- If a secret is ever exposed, rotate it immediately and re-save any
  configuration encrypted under it. History rewrites do not undo
  exposure.

## License and credits

[MIT](./LICENSE). Based on the open-source
[wacrm](https://github.com/ArnasDon/wacrm) template by Arnas
Donauskas; customised, rebranded, and operated by SecureMojo.
