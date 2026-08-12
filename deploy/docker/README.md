# Docker deploy

Single-container Phoenix deploy for one VPS. SQLite and uploaded previews live in Docker volumes.

Two modes are included:

- `docker-compose.yml`: build on the server
- `docker-compose.image.yml`: pull a prebuilt image, for CI/GHCR deploys

## Files that must persist

- SQLite: `/app/data/bot_machine.db`
- Upload previews: `/app/storage/uploads/bot/*`

Both are mounted by `docker-compose.yml`.

## Setup for server builds

```bash
cd deploy/docker
cp .env.example .env
# edit .env, generate SECRET_KEY_BASE with: mix phx.gen.secret
```

## First deploy, server build

Build the image, run migrations before the app starts, seed once, then start:

```bash
docker compose build app
docker compose run --rm app /app/bin/bot_machine eval "BotMachine.Release.migrate()"
docker compose run --rm app /app/bin/bot_machine eval "BotMachine.Release.seed()"
docker compose up -d app
```

## Later deploys, server build

```bash
docker compose build app
docker compose run --rm app /app/bin/bot_machine eval "BotMachine.Release.migrate()"
docker compose up -d app
```

## CI/GHCR deploy

Copy the example workflow in a real bot project:

```bash
mkdir -p .github/workflows
cp .github/workflows/docker-image.yml.example .github/workflows/docker-image.yml
```

Edit:

```yaml
IMAGE_NAME: ghcr.io/xamelon/photo-booth-new
```

On the VPS:

```bash
cd deploy/docker
cp .env.image.example .env
# edit IMAGE_NAME, IMAGE_TAG and runtime env
```

If the GHCR package is private, login once on the VPS:

```bash
echo "$GITHUB_PAT" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

First deploy from image:

```bash
docker compose -f docker-compose.image.yml pull
docker compose -f docker-compose.image.yml run --rm app /app/bin/bot_machine eval "BotMachine.Release.migrate()"
docker compose -f docker-compose.image.yml run --rm app /app/bin/bot_machine eval "BotMachine.Release.seed()"
docker compose -f docker-compose.image.yml up -d app
```

Later deploys from image:

```bash
docker compose -f docker-compose.image.yml pull
docker compose -f docker-compose.image.yml run --rm app /app/bin/bot_machine eval "BotMachine.Release.migrate()"
docker compose -f docker-compose.image.yml up -d app
```

Do not run `seed` on every deploy unless you want to reset/update demo data.

## Logs

```bash
docker compose logs -f app
```

## Reverse proxy

Put Caddy, nginx, Traefik, or your host proxy in front of `HOST_PORT`.

For Caddy on the host:

```caddy
bot.example.com {
  reverse_proxy 127.0.0.1:4000
}
```

Set:

```env
PHX_HOST=bot.example.com
PUBLIC_BASE_URL=https://bot.example.com
```
