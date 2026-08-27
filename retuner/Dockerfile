ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm

# The add-on's build context is this directory, not the repository root, so the
# source is fetched rather than copied. Bump RETUNER_REF in build.yaml to move
# the add-on to a different revision.
FROM ${BUILD_FROM} AS builder

# libc6-dev and libsqlite3-dev are what the *linker* needs -- the base image is
# minimal and ships neither the C runtime startup objects nor the .so symlinks
# for -lc, -lpthread, -ldl, -lrt and -lsqlite3. Without them the compile
# succeeds and only the link fails.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates git zip \
      fp-compiler fp-units-fcl fp-units-net fp-units-db fp-units-misc \
      lazarus-src \
      libc6-dev libsqlite3-dev \
 && rm -rf /var/lib/apt/lists/*

ARG RETUNER_REPO=https://github.com/ollisulopuisto/YTuner.git
ARG RETUNER_REF=master
RUN git clone --depth 1 --branch "${RETUNER_REF}" "${RETUNER_REPO}" /src

WORKDIR /src
RUN ./script/build.sh

FROM ${BUILD_FROM}

# libssl is loaded at runtime by the Free Pascal OpenSSL unit, so it does not
# show up in the binary's link dependencies but is needed for HTTPS all the same.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates libsqlite3-0 libssl3 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/bin/*/ytuner /opt/retuner/ytuner
COPY --from=builder /src/cfg/ /opt/retuner/cfg/
COPY rootfs /

LABEL \
    org.opencontainers.image.title="Home Assistant Add-on: Retuner" \
    org.opencontainers.image.description="Internet radio for AV receivers whose vTuner service was shut down" \
    org.opencontainers.image.source="https://github.com/ollisulopuisto/YTuner" \
    org.opencontainers.image.licenses="MIT"
