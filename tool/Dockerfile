# The one environment the checks of this repository are true in.
#
# Every version is pinned, so a red run is a finding in the tree and not a tool that moved underneath
# it. The versions arrive as build arguments with NO default: a default here would be a second copy
# of each pin, and tool/gate/pins.dart derives the image TAG from its own copy — the two would drift
# and the tag would then name an image built from something else. Without --build-arg the FROM below
# resolves to `debian:` and the build stops.
#
# ONE tool, and it is Dart. This framework drives a machine through four ports and its tests replace
# all four with fakes, so nothing here needs a second toolchain. An image that installs a tool no
# check runs is a pin nobody verifies and a download everybody pays for.
ARG DEBIAN_TAG
FROM debian:${DEBIAN_TAG}

ARG DART_VERSION

# From the official archive rather than a third-party image: the same discipline as every other pin,
# and a zip whose name carries the version cannot quietly become another one.
#
# `dart --version` runs at BUILD time. A download that answered with an error page, a version that
# does not exist and a binary for the wrong architecture all fail the build here, where the cause is
# on screen, instead of failing a check later, where it reads as a finding about the tree.
#
# curl and unzip fetch and open that archive. ca-certificates is what lets curl and `dart pub get`
# verify the hosts they download from. bash is here for `dart run tool/ci.dart --shell` and for
# nothing else: it is the interactive shell a developer types in when a check answers differently
# inside the container than outside. No program of this repository is written in it.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends bash curl ca-certificates unzip; \
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

# Nothing else is installed and nothing else is scripted here. Getting the tree in off the read-only
# mount, resolving it, judging it and saying what it decided are all tool/ci.dart, which this
# container is told to run with --inside. That program is what the gate IS; an image that also
# carried a copy of any part of it would be a second description to keep in step with the first, and
# the two would answer differently the first time somebody edited one of them.
WORKDIR /work
