# Deployment runbook

Production is **securemojo.in** on Hostinger (Cloud Startup plan,
managed Node.js). This document is the single source of truth for how
changes reach production. Follow it for every deploy.

## The rule: never build on the production server

A Next.js production build (`next build`) is CPU- and RAM-heavy and
briefly spawns many processes. On Hostinger's shared plan the process
ceiling is ~200; a server-side build spikes straight into that ceiling,
Hostinger throttles the whole app, and **every request returns 503**
until the spike clears. This is the "503 after every deploy" symptom.

**Therefore the build happens in GitHub Actions, not on Hostinger.**
The production server only ever *runs* the pre-built app.

```
push to main  ->  GitHub Actions: lint/typecheck/test/build
              ->  rsync built .next to Hostinger over SSH
              ->  install prod deps + restart
```

The workflow that does this is
[`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml).

## One-time setup (do this once, then never again)

### 1. Turn OFF Hostinger's Git auto-deploy

This is the step that actually stops the server-side build. In
hPanel → your app → **Deployments** (or Git), **disconnect the
auto-deploy / auto-build on push**. If Hostinger keeps rebuilding on
push, the 503 will keep happening no matter what CI does.

### 2. Confirm the runtime start command

hPanel → your app → the **start** command must be `npm start`
(= `next start`), Node **20+**. It must **not** be `npm run dev`.

### 3. Create the repository secrets and variables

GitHub → repo → Settings → Secrets and variables → Actions.

**Variables** (public, inlined at build time):

| Name | Value |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | your Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | your `sb_publishable_...` key |
| `NEXT_PUBLIC_SITE_URL` | `https://securemojo.in` |

**Secrets** (SSH access to Hostinger — from hPanel → Advanced → SSH):

| Name | Value |
| --- | --- |
| `HOSTINGER_SSH_HOST` | SSH host/IP |
| `HOSTINGER_SSH_PORT` | SSH port (often 65002 on Hostinger) |
| `HOSTINGER_SSH_USER` | SSH username (e.g. `u868484251`) |
| `HOSTINGER_SSH_KEY` | a **private** deploy key whose public half is added to the server's `~/.ssh/authorized_keys` |
| `HOSTINGER_DEPLOY_PATH` | absolute path to the app dir, e.g. `/home/u868484251/domains/securemojo.in/nodejs` |

> Server-only secrets — `SUPABASE_SERVICE_ROLE_KEY`, `ENCRYPTION_KEY`,
> `META_APP_SECRET` — are **not** GitHub secrets. They live only in
> Hostinger's Environment Variables and are read at runtime. Keep
> `ENCRYPTION_KEY` **identical** to local `.env.local` (shared DB).

### 4. Confirm the restart mechanism

Hostinger's default Node runner is Phusion Passenger, which restarts
when `tmp/restart.txt` is touched — that is what the workflow does. If
your app is run some other way (PM2, systemd), replace the touch line
in `deploy.yml` with the correct restart command. Check hPanel or ask
Hostinger support which runner backs the app.

## Every deploy after setup

1. Open a branch, make the change, push, open a PR. CI runs the same
   checks.
2. Merge to `main`. `deploy.yml` builds in CI and ships the artifact.
   No build runs on Hostinger, so no 503.
3. Watch the Actions run go green. Load securemojo.in.

## Database migrations are separate

Code deploys do **not** run SQL. When a change adds a file under
`supabase/migrations/`, apply it by hand in the Supabase SQL editor
(in numeric order) **before or together with** the deploy that depends
on it. A deploy whose code expects a not-yet-applied migration will
throw at runtime.

## If you still see a 503

- It is almost always the process/RAM ceiling, not disk (disk is <1%).
- hPanel → your app → **Stop running processes**, then start again —
  clears anything stuck from a bad window.
- Confirm Hostinger auto-build is really OFF (setup step 1).
- During an unavoidable heavy moment, the free **Boost resources**
  button gives temporary headroom.
