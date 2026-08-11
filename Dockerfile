# syntax=docker/dockerfile:1

ARG ELIXIR_IMAGE=hexpm/elixir:1.18.4-erlang-27.3.4.16-debian-bookworm-20260803-slim
ARG DEBIAN_IMAGE=debian:bookworm-slim

FROM node:20-bookworm-slim AS node_deps

WORKDIR /app
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm ci --prefix assets

FROM ${ELIXIR_IMAGE} AS build

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod && mix deps.compile

COPY priv priv
COPY assets assets
COPY --from=node_deps /app/assets/node_modules ./assets/node_modules
RUN mix assets.deploy

COPY lib lib
RUN mix compile
RUN mix release

FROM ${DEBIAN_IMAGE} AS app

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends openssl libstdc++6 ca-certificates ncurses-bin \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV HOME=/app \
    PHX_SERVER=true \
    PORT=4000 \
    DATABASE_PATH=/app/data/bot_machine.db \
    STORAGE_DIR=/app/storage/uploads \
    ELIXIR_ERL_OPTIONS=+fnu

COPY --from=build /app/_build/prod/rel/bot_machine ./

RUN mkdir -p /app/data /app/storage/uploads \
  && chown -R nobody:nogroup /app

USER nobody:nogroup

EXPOSE 4000
CMD ["/app/bin/bot_machine", "start"]
