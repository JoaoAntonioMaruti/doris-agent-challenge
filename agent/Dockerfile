# Stage "dev": toolchain + deps, used by the test service (mix test / mix format).
FROM elixir:1.18 AS dev
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock* ./
RUN mix deps.get && MIX_ENV=test mix deps.compile && MIX_ENV=prod mix deps.compile
COPY . .

# Stage "build": compiled release.
FROM dev AS build
ENV MIX_ENV=prod
RUN mix compile && mix release

# Stage "runtime": only the release.
FROM debian:trixie-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates locales \
    && rm -rf /var/lib/apt/lists/* && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 MIX_ENV=prod PHX_SERVER=true PORT=8000
WORKDIR /app
COPY --from=build /app/_build/prod/rel/doris ./
EXPOSE 8000
CMD ["sh", "-c", "bin/doris eval 'Doris.Release.migrate()' && exec bin/doris start"]
