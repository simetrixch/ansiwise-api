# The one environment the checks of this repository are true in.
#
# Every version is pinned, so a red run is a finding in the tree and not a tool that moved underneath
# it. The versions arrive as build arguments with NO default: a default here would be a second copy
# of each pin, and tools/ci.sh derives the image TAG from its own copy — the two would drift and the
# tag would then name an image built from something else. Without --build-arg the FROM below resolves
# to `debian:` and the build stops.
#
# ONE tool, and it is Dart. This framework drives a machine through four ports and its tests replace
# all four with fakes, so nothing here needs helm, kubectl, yq or a Flutter SDK. An image that
# installs a tool no check runs is a pin nobody verifies and a download everybody pays for.
ARG DEBIAN_TAG
FROM debian:${DEBIAN_TAG}

ARG DART_VERSION

# From the official archive rather than a third-party image: the same discipline as every other pin,
# and a zip whose name carries the version cannot quietly become another one.
#
# `dart --version` runs at BUILD time. A download that answered with an error page, a version that
# does not exist and a binary for the wrong architecture all fail the build here, where the cause is
# on screen, instead of failing a check later, where it reads as a finding about the tree.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends bash git curl ca-certificates unzip; \
    rm -rf /var/lib/apt/lists/*; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) dart_arch=x64 ;; \
      arm64) dart_arch=arm64 ;; \
      *) echo "the Dart SDK is published for x64 and arm64; this is $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/dart.zip \
      "https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/dartsdk-linux-${dart_arch}-release.zip"; \
    unzip -q /tmp/dart.zip -d /opt; \
    rm /tmp/dart.zip; \
    /opt/dart-sdk/bin/dart --version

ENV PATH="/opt/dart-sdk/bin:${PATH}"

# The one definition of how the tree gets in, so a check run and an interactive `--shell` can never
# be looking at different things.
#
# The tree is COPIED rather than bind-mounted. A bind mount of a Windows directory into Linux Docker
# is slow enough to change results and not just timing, and a gate that invents red findings is worse
# than a slow one. /host is read-only and is never the working copy.
#
# .dart_tool is left behind deliberately. It holds absolute paths into the HOST filesystem — the
# package_config.json written by `dart pub get` on Windows points at C:\… — so a copy of it makes the
# analyzer resolve packages that are not in this container. `pub get` rebuilds it here against the
# pub cache volume.
RUN printf '%s\n' \
  '#!/bin/sh' \
  'set -e' \
  'mkdir -p /work' \
  'tar -C /host -cf - --exclude=.dart_tool ansiwise-api | tar -C /work -xf -' \
  > /usr/local/bin/copy-in && chmod +x /usr/local/bin/copy-in

WORKDIR /work
