# Next steps

Materialized app:

- Module: `PhotoBoothBot`
- App logic: `lib/photo_booth_bot`
- App admin UI: `lib/photo_booth_bot_web`
- Image: `ghcr.io/xamelon/photo-booth-new`

Run:

```bash
mix format
mix test
```

Git remotes:

This task configured:

```text
template = original template remote
origin   = git@github.com:xamelon/photo_booth_new.git
```

Push when ready:

```bash
git push -u origin main
```


Commit prefixes for future backports:

- `core:` generic template changes that may be cherry-picked back to the template
- `app:` project-specific bot/business changes, never backport
- `ops:` deploy/env/CI for this concrete project
- `docs:` documentation-only changes
- `mixed:` only when explicitly requested, do not backport directly

Keep `core:` and `app:` changes in separate commits. Backport only `core:` commits to the template.

Edit your real bot flow/actions in:

```text
lib/photo_booth_bot/app.ex
```

Deploy from GHCR with:

```bash
cd deploy/docker
docker compose -f docker-compose.image.yml pull
docker compose -f docker-compose.image.yml run --rm app /app/bin/bot_machine eval "BotMachine.Release.migrate()"
docker compose -f docker-compose.image.yml up -d app
```
