<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

# Deployment rule — never build on the production server

Production (securemojo.in) runs on Hostinger's shared plan, where a
server-side `next build` spikes the process ceiling and returns 503 to
every request until it clears. The build therefore runs in GitHub
Actions ([`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)),
and Hostinger only runs the pre-built app. Before shipping any change:

- Do **not** re-enable Hostinger's Git auto-deploy/auto-build. Deploys
  go through the Actions workflow, which builds in CI and rsyncs the
  artifact over SSH.
- Keep `ENCRYPTION_KEY` identical between local `.env.local` and
  Hostinger — both share one Supabase database, and the WhatsApp token
  is encrypted with it. Changing it in one place breaks the other.
- A change that adds a file under `supabase/migrations/` must be applied
  by hand in the Supabase SQL editor (numeric order) before the deploy
  that depends on it — code deploys never run SQL.

Full runbook and one-time setup: [`docs/deployment.md`](docs/deployment.md).
