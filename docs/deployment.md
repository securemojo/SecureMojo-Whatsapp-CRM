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

## Will normal usage ever cause a 503? No.

This is the common worry, so state it plainly: **request volume does
not cause 503.** Node.js serves the whole app from one process on an
event loop — hundreds of concurrent requests share it without
spawning new OS processes. Hostinger's "Max Processes: 200" ceiling
counts processes, not requests, so heavy CRM use (inbox, broadcasts,
API traffic in and out) never approaches it.

Two design facts make runtime robust:

- A single failing request returns a 500 for **that request only**;
  it never crashes the server process. One bad broadcast or webhook
  cannot take the site down.
- The heavy endpoints (broadcast send, webhook processing) are
  batched and time-capped (`maxDuration = 60`), so no request runs
  away with CPU or memory.

503 therefore only comes from the app failing to **start** (a boot
crash-loop) or the **build** spiking during a server-side deploy —
never from serving traffic. Both are addressed:

- **Boot reliability** — the app only crash-loops if it cannot start.
  Keep env vars complete and correct, and never change `ENCRYPTION_KEY`
  on only one side (it must match across local and Hostinger). This is
  the single most important operational rule.
- **Deploy spike** — remove it with the CI build path above, or simply
  deploy during low-traffic hours; a sub-minute blip at a quiet time
  affects no one.
- **Self-healing** — Hostinger restarts a crashed app within seconds;
  "Stop running processes" clears a stuck window instantly.

### Optional: a lighter runtime (standalone output)

To shrink the app's memory footprint further, Next.js can emit a
`standalone` server bundle (only the code and dependencies actually
used). It lowers runtime RAM and speeds cold starts. It is **opt-in**
because it changes how the app is started:

1. Add `output: "standalone"` to `next.config.ts`.
2. Ensure `.next/static` and `public` are copied next to the
   standalone server after build.
3. Change the Hostinger **start** command to
   `node .next/standalone/server.js`.

Do all three together or not at all — enabling the config without
changing the start command has no effect. Leave this until there is a
measured memory problem; the app runs comfortably without it.

## If you still see a 503

- It is almost always the process/RAM ceiling, not disk (disk is <1%).
- hPanel → your app → **Stop running processes**, then start again —
  clears anything stuck from a bad window.
- Confirm Hostinger auto-build is really OFF (setup step 1).
- During an unavoidable heavy moment, the free **Boost resources**
  button gives temporary headroom.
