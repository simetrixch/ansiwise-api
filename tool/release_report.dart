/// What a person reads when they run tool/release.dart, what the release page says, and the one line
/// that says what the run did.
///
/// The text is here rather than written where the work happens, so a check can assert what a person
/// sees without a git, a remote or a terminal — a screen nothing can read is a screen nobody can hold
/// to anything.
///
/// WHAT A RELEASE OF THIS PACKAGE IS, and why nothing is attached to it. This package is compiled
/// into nothing: it is a library, and every consumer resolves it as a git dependency. So the tree at
/// the tag IS what a consumer gets, and the release carries no file — what makes the release usable
/// is that the tag exists and can be named. [thePin] is the line a consumer changes to name it, and
/// it is spelled here because it is the only thing a release of a library hands anybody.
library;

import 'release_tag_filter.dart';
import 'release_versions.dart';

/// The line a consumer writes to resolve this release, as pubspec.yaml spells a git dependency.
///
/// A git dependency resolves whatever its `ref` names, so the ref IS the pin. Every consumer of this
/// package says `ref: master` today, which is a pin on a moving branch: a push reaches all of them at
/// once and nobody decided that it should. What a release offers instead is this line.
String thePin(String tag) => 'ref: $tag';

/// What one invocation of the release program did.
final class ReleaseOutcome {
  /// [text] is everything the person reads, and [isGreen] whether the run did what it was asked.
  const ReleaseOutcome({required this.text, required this.isGreen});

  /// Nothing was done, and [why] says what was wrong.
  factory ReleaseOutcome.refused(String why) =>
      ReleaseOutcome(text: 'release: FAIL — $why', isGreen: false);

  /// [listing] was shown and nothing was touched.
  factory ReleaseOutcome.shown(String listing) => ReleaseOutcome(
    text:
        '$listing\n'
        'release: OK — nothing was pushed; a release starts when a version and a channel are typed',
    isGreen: true,
  );

  /// The tag [tag] was pushed to [remote], which is the whole of what starts a release.
  ///
  /// [bumped] says what happened to the version the manifest declares, because a person who typed a
  /// version has to know whether a commit was made in their name before the tag was put on it.
  factory ReleaseOutcome.pushed({
    required String tag,
    required String remote,
    required ReleaseChannel channel,
    required String bumped,
  }) => ReleaseOutcome(
    text:
        'release: OK — the tag $tag is on $remote, and pushing it is the whole of what starts a '
        'release\n'
        '  $bumped\n'
        "  $releaseWorkflowPath runs this repository's own gate on the tag and creates a GitHub\n"
        '  Release named $tag,\n'
        '  ${channel.isPreRelease ? 'marked as a pre-release because ${channel.name} is not the ripest channel' : 'published plainly, because ${channel.name} is the ripest channel'}\n'
        '  NOTHING IS ATTACHED TO IT: this package is compiled into nothing, and what a consumer\n'
        '  resolves is the tree at the tag itself\n'
        '  gh run watch --repo simetrixch/ansiwise-core   follows it\n'
        '  THE CHANNEL IS A CEILING, NOT A DEPLOYMENT: ${channel.name} reaches ${channel.reaches}.\n'
        '  Nothing in this repository enforces that ceiling — it is enforced where deployments\n'
        '  are written (hostyour-manager/shared/release.ts:8)\n'
        '  NO CONSUMER RESOLVES IT YET: every consumer names this package as a git dependency and\n'
        '  gets whatever the `ref` it states names. Moving one onto this release is\n'
        '  "${thePin(tag)}" in that consumer\'s pubspec.yaml, which is an edit in that repository\n'
        '  and not something this run did',
    isGreen: true,
  );

  /// Everything the person reads.
  final String text;

  /// Whether the run did what it was asked.
  final bool isGreen;
}

/// What one run of the notes program produced: the page, or the reason there is none.
final class NotesOutcome {
  /// [page] is what the release page carries, and [isPreRelease] how the release is to be marked.
  const NotesOutcome.written({required this.page, required this.isPreRelease}) : refusal = null;

  /// Nothing was written, and [refusal] says what could not be read.
  const NotesOutcome.refused(this.refusal) : page = '', isPreRelease = false;

  /// What the release page carries.
  final String page;

  /// Whether the release is to be marked as a pre-release.
  final bool isPreRelease;

  /// Why there is no page, or null when there is one.
  final String? refusal;

  /// Whether the run did what it was asked.
  bool get isGreen => refusal == null;
}

/// The page a GitHub Release named by [release]'s tag carries.
///
/// [previous] is the release this one follows, or null when it is the first, and [subjects] are the
/// commit subjects between the two. AN EMPTY RANGE IS SAID OUT LOUD rather than left as a heading
/// with nothing under it: a release whose tag names the same commit as the last one is a real thing
/// — the same code cut on a riper channel — and a page that simply showed no changes would read as a
/// page nobody generated.
///
/// THE PAGE SAYS WHAT THE RELEASE HANDS ANYBODY, because a release with no file attached says
/// nothing about itself. What it hands anybody is the line that names it.
String notesFor({
  required ReleasedTag release,
  required ReleaseChannel channel,
  required String? previous,
  required List<String> subjects,
}) {
  final StringBuffer page = StringBuffer()
    ..writeln('Channel **${channel.name}** — this release may run in ${channel.reaches}.')
    ..writeln('')
    ..writeln(
      'The ceiling is enforced where deployments are written, not by this release '
      '(hostyour-manager/shared/release.ts:8).',
    )
    ..writeln('')
    ..writeln(
      'Nothing is attached: this package is compiled into nothing, and the tree at this tag is what '
      'a consumer resolves. A consumer names this release by putting `${thePin(release.tag)}` in the '
      'git dependency that declares this package.',
    )
    ..writeln('')
    ..writeln(
      previous == null
          ? '## Changes — every commit up to this tag, because nothing was released before it'
          : '## Changes since $previous',
    )
    ..writeln('');
  if (subjects.isEmpty) {
    page.writeln(
      previous == null
          ? 'No commit was found behind this tag, which is a history nobody could read.'
          : 'Nothing changed since $previous: this tag names the same code, cut again.',
    );
  }
  for (final String subject in subjects) {
    page.writeln('- $subject');
  }
  if (previous != null) {
    page
      ..writeln('')
      ..writeln('`git log --format=%s $previous..${release.tag}` is the range this was read from.');
  }
  return page.toString();
}

/// The screen shown when the program is run with no arguments: what the workflow releases on, what
/// has been released, what a tag would name, and what could come next.
///
/// [branch] and [commit] describe what HEAD is, because the tag a release pushes names THIS commit —
/// a person deciding a version is deciding which commit becomes a release, and a screen that hid it
/// would hide half the decision.
String listingOf(
  Releases releases, {
  required TagFilter filter,
  required String? declaredVersion,
  required String remote,
  required String branch,
  required String commit,
}) {
  final StringBuffer screen = StringBuffer()
    ..writeln('a tag starts a release when $releaseWorkflowPath triggers on it, which is:');
  for (final String pattern in filter.stated) {
    screen.writeln('  $pattern');
  }
  screen
    ..writeln('')
    ..writeln('released so far, read from the tags on $remote:');
  if (releases.releases.isEmpty) {
    screen.writeln('  nothing — no version of this package has been released');
  } else {
    for (final ReleasedTag released in releases.releases.reversed) {
      screen.writeln('  ${released.tag}');
    }
  }
  if (releases.otherTags.isNotEmpty) {
    screen
      ..writeln('')
      ..writeln('tags on $remote this screen could not place as a release:');
    for (final String tag in releases.otherTags) {
      screen.writeln('  $tag');
    }
  }
  screen
    ..writeln('')
    ..writeln('a release would name this commit:')
    ..writeln('  $branch at $commit')
    ..writeln('')
    ..writeln('possible next versions, none of them chosen:');
  final List<Proposal> proposals = releases.proposals(declaredVersion: declaredVersion);
  if (proposals.isEmpty) {
    screen.writeln('  none — pubspec.yaml declares no version to offer as the first release');
  }
  for (final Proposal proposal in proposals) {
    screen.writeln('  ${proposal.version.padRight(16)}${proposal.because}');
  }
  screen
    ..writeln('')
    ..writeln('and the channel, which is a ceiling on where the tag may run:');
  for (final ReleaseChannel channel in ReleaseChannel.values) {
    screen.writeln('  ${channel.name.padRight(16)}reaches ${channel.reaches}');
  }
  screen
    ..writeln('')
    ..writeln('type the version and the channel you decided on:')
    ..writeln('  dart run tool/release.dart <version> <channel>')
    ..writeln('  dart run tool/release.dart help     what a release is, and what it is not');
  return screen.toString();
}

/// What `help` writes.
///
/// IT DOES NOT SPELL OUT WHICH TAGS ARE ADMITTED. The one place that decides is `on.push.tags` in the
/// workflow; the program reads it every run and the screen prints what it says today, so a help text
/// carrying its own copy would be a second spelling of the grammar.
const String helpText =
    '''
release — show what has been released, and start a release of a version and a channel you type.

  dart run tool/release.dart                        what has been released, and what could come next
  dart run tool/release.dart <version> <channel>    push the tag, which starts the release
  dart run tool/release.dart help                   this

WHAT A RELEASE OF THIS PACKAGE IS. This package is compiled into nothing and nobody downloads it:
every consumer names it as a git dependency and gets whatever the `ref` that dependency states names.
So a release is a TAG a consumer can name, and the tree at that tag is the whole of what it gets. The
GitHub Release the workflow then creates carries no file — it carries the notes and the marking.

WITH NO ARGUMENTS IT CHANGES NOTHING. It reads the tags on origin, prints what has been released,
names the commit a release would carry and proposes what could come next. It never picks a version:
which release a change deserves is a decision, and a program that took it would hide it.

WHAT THE TWO ARGUMENTS COMPOSE. The tag is <major>.<minor>.<patch>-<channel>-<ts14>, where the ts14
is the UTC yyyyMMddHHmmss this program stamps at the moment you run it — never typed, which is what
makes one version cut twice on one channel two tags instead of one name pushed twice. The grammar is
hostyour-manager/shared/release.ts:22, one grammar for every release of everything.

THE CHANNEL IS A CEILING ON WHERE THE TAG MAY RUN — alpha reaches dev, beta reaches dev and test, stable
reaches everywhere — and NOTHING HERE ENFORCES IT. It is enforced where deployments are written
(hostyour-manager/shared/release.ts:8). What the channel decides here is only whether the release
page marks the release as a pre-release.

WHICH TAGS ARE ADMITTED IS NOT WRITTEN IN THIS PROGRAM. $releaseWorkflowPath triggers on
`on.push.tags` and on nothing else, so a tag that filter does not match starts nothing — no gate, no
release. The filter is read out of that file on every run and the composed tag is held against it;
run with no arguments to see what it states today. The one thing this program refuses that the filter
cannot is a leading zero in a number, because a filter pattern has no alternation and `01.2.3` is no
version.

WHAT HAPPENS WHEN YOU TYPE THEM. The working tree has to be clean. The version pubspec.yaml declares
is set to the one you typed and that bump is committed — and when the manifest already declares it,
nothing is committed and the tag names HEAD as it stands. An ANNOTATED tag is then created, HEAD is
pushed and the tag is pushed, and that is all that happens here. The workflow runs the gate on the
tag and creates the GitHub Release.

WHAT DOES NOT HAPPEN. No release is created here — the workflow creates it, writes its notes and
marks a pre-release. AND NO CONSUMER RESOLVES THE NEW TAG: what a consumer gets is what the `ref` in
its own pubspec.yaml names, and moving one onto this release is an edit in that repository.
''';
