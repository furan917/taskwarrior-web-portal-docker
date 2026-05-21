# syntax=docker/dockerfile:1
#
# Two-stage build:
#   tw-builder  — compiles Taskwarrior 3.x from source (Rust + CMake)
#   runtime     — Ubuntu 24.04 with the task binary + taskwarrior-web-portal
#
# Taskwarrior 3.x has no upstream pre-built Linux binaries; it is a C++ binary
# that links against a Rust (taskchampion) library, so both toolchains are
# required at build time. The rust:bookworm image provides a current stable
# Rust; we add cmake/clang on top for the C++ layer.

ARG TASK_VERSION=3.4.2

# ---------------------------------------------------------------------------
# Stage 1: build Taskwarrior 3.x from source
# ---------------------------------------------------------------------------
FROM rust:1-bookworm AS tw-builder

ARG TASK_VERSION

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential cmake git clang uuid-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "v${TASK_VERSION}" \
    https://github.com/GothenburgBitFactory/taskwarrior.git /task

WORKDIR /task

# Strip the integration-test suite from the Cargo manifest — it requires a
# live sync server and will fail in a network-isolated build environment.
RUN sed -i '/\[\[test\]\]/,/integration/d' Cargo.toml

RUN cargo build --release
RUN cmake -DCMAKE_BUILD_TYPE=Release . \
    && make -j"$(nproc)" \
    && make install

# ---------------------------------------------------------------------------
# Stage 2: runtime image
# ---------------------------------------------------------------------------
FROM ubuntu:26.04

ARG TWP_VERSION=v1.6.0
ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       gosu \
       curl \
       ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Taskwarrior binary compiled in the builder stage.
COPY --from=tw-builder /usr/local/bin/task /usr/local/bin/task

# Download the pre-built taskwarrior-web-portal binary for the target arch.
# Binaries are published as tarballs by the build.yml workflow in the
# taskwarrior-web-portal repo on every tagged release.
RUN set -ex; \
    case "$TARGETARCH" in \
        arm64) GOARCH=arm64 ;; \
        *)     GOARCH=amd64 ;; \
    esac; \
    archive="taskwarrior-web-portal-${TWP_VERSION}-linux-${GOARCH}"; \
    curl -fsSL \
        "https://github.com/furan917/taskwarrior-web-portal/releases/download/${TWP_VERSION}/${archive}.tar.gz" \
        | tar -xz --strip-components=1 -C /usr/local/bin "${archive}/taskwarrior-web-portal"; \
    chmod +x /usr/local/bin/taskwarrior-web-portal

ENV TASKRC=/config/taskrc

# Optional: set BUGWARRIOR_BIN to the absolute path of the bugwarrior binary
# if you have installed it in a custom location or a mounted virtualenv.
# When unset the portal probes PATH and common install directories
# (~/.local/bin, /usr/local/bin, etc.) automatically.
# Example: -e BUGWARRIOR_BIN=/venv/bin/bugwarrior
ENV BUGWARRIOR_BIN=

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/config"]

EXPOSE 5050

ENTRYPOINT ["/entrypoint.sh"]
