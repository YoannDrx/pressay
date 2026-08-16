# Contributing to Pressay

Pressay is developed in a private repository. All changes must go through a
short-lived branch and a pull request into `main`.

## Workflow

1. Start from an up-to-date `main`.
2. Create `codex/<subject>` (or another documented work branch).
3. Make one coherent change and add the smallest relevant tests.
4. Run the checks listed in `BUILD.md`.
5. Push to `origin` and open a Pressay pull request.

`origin` is the only push destination. `upstream` points to Handy for audited,
fetch-only comparison and has pushing disabled. Never merge `upstream/main`
automatically. Follow `UPSTREAM.md` for every upstream review.

## Product constraints

- Local transcription and BYOK must remain usable without an account.
- No transcript, audio, clipboard content, prompt, authorization header, or API
  key may be written to logs.
- A remote processing route must always be an explicit user choice.
- No user content may be written when local history is disabled.
- The Store build must not contain the external updater, Stripe purchase UI, or
  private APIs.
- Keep CJ Pais's MIT copyright notice and the Pressay `NOTICE` attribution.

## Pull requests

Use the repository template. Describe privacy and security impact, list the
verification performed, and call out any release blocker that remains. Upstream
ports must identify the exact Handy commit or pull request and explain why the
behavior was reimplemented or cherry-picked.
