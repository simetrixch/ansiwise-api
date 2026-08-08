/// The one environment the checks of this repository are true in.
///
/// Every version is pinned, so a red run is a finding in the tree and not a tool that moved
/// underneath it. Each was read from the source named beside it, on the date given: a version
/// recalled from memory is as old as whoever recalled it, which is why the source is part of the
/// record.
///
/// The image TAG is derived from these rather than written a second time. Two copies of a pin
/// drift, and an image tag that outlives the versions inside it is the one failure a pin exists to
/// prevent: a raised pin would leave the existing image in place and the run would report green
/// against the previous toolchain, exactly when the version change is what needs proving.
library;

/// The Debian release the container is built from.
///
/// hub.docker.com/v2/repositories/library/debian/tags — the current stable, read 2026-08-08.
const String debianTag = 'trixie-slim';

/// The Dart SDK the container installs, and the only tool in it.
///
/// storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION — read 2026-08-08.
const String dartVersion = '3.12.2';

/// The image the gate runs in, named after what it holds.
String get imageTag => 'ansiwise-api-ci:${_slug('dart$dartVersion-debian$debianTag')}';

/// Where the pub cache lives between runs, so a resolution is downloaded once per SDK.
String get pubCacheVolume => 'ansiwise-api-ci-pub-cache-${_slug(dartVersion)}';

/// [text] with everything a container tag may not carry replaced by a dash.
String _slug(String text) => text.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
