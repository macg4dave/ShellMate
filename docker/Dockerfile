# syntax=docker/dockerfile:1
#
# Disposable test environments for ShellMate.
#
# Build one target with:
#   docker build -f docker/Dockerfile --build-arg TARGET=fedora -t shellmate-test:fedora .
# or just use:  scripts/docker-test.sh [ubuntu|debian|fedora|bash32|all]
#
# Targets:
#   ubuntu  - CI baseline (Supported); full toolset incl. shellcheck
#   debian  - Best-effort distro; slim image, few optional tools
#   fedora  - Best-effort distro; dnf-based, ShellCheck available
#   bash32  - Bash 3.2 (same major/minor as macOS /bin/bash) on Alpine/busybox.
#             Catches Bash 4+ syntax; NOT a macOS substitute (no BSD tools).

ARG TARGET=ubuntu

# --- ubuntu -------------------------------------------------------------------
FROM docker.io/library/ubuntu:24.04 AS base-ubuntu
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash make shellcheck ca-certificates curl iproute2 procps \
      unzip xz-utils bzip2 file \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash tester

# --- debian -------------------------------------------------------------------
FROM docker.io/library/debian:12-slim AS base-debian
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash make procps \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash tester

# --- fedora -------------------------------------------------------------------
FROM docker.io/library/fedora:41 AS base-fedora
RUN dnf install -y --setopt=install_weak_deps=False \
      bash make ShellCheck iproute procps-ng findutils unzip xz which \
 && dnf clean all \
 && useradd -m -s /bin/bash tester

# --- bash 3.2 -----------------------------------------------------------------
FROM docker.io/library/bash:3.2 AS base-bash32
# The official image puts bash 3.2 at /usr/local/bin/bash; make /bin/bash point
# at it too so nothing silently falls back to a newer shell.
RUN apk add --no-cache make coreutils \
 && ln -sf /usr/local/bin/bash /bin/bash \
 && adduser -D -s /usr/local/bin/bash tester

# --- shared tail --------------------------------------------------------------
FROM base-${TARGET}
ARG TARGET
ENV SHELLMATE_TEST_TARGET=${TARGET}
COPY --chown=tester docker/run-tests.sh /usr/local/bin/shellmate-run-tests
COPY --chown=tester . /src
USER tester
WORKDIR /home/tester
ENTRYPOINT ["bash", "/usr/local/bin/shellmate-run-tests"]
