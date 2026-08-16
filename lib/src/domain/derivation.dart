library;

import 'package:meta/meta.dart';

/// The rules by which one answer is worked out from another, as a CLOSED set of names.
///
/// **Why this exists at all.** Some values an installation needs are not questions anybody should be
/// asked, because they follow from a question already answered. A cluster's short name is the first
/// label of its domain; asking for both invites somebody to type a pair that does not match, and a
/// selector built on the mismatch then finds nothing and says nothing.
///
/// **Why it is a closed set of NAMES and not an expression.** A program file may not compute — the
/// moment it can, what is being debugged stops being the code and becomes the configuration. So a
/// file names a rule and the rule is Dart: typed, tested, and the same for everybody. The file
/// carries a name and a reference; there is no place in it for a concatenation, a condition, or a
/// second value.
///
/// **Why it happens BEFORE the first step and not during the run.** A run in the mode that changes
/// things is admitted only where a run in the mode that changes nothing came back green for the same
/// fingerprint, and that fingerprint is built from the resolved program plus the ANSWERS, before any
/// step runs. A value worked out here is part of it. A value worked out later would not be, and a
/// real run would then be admitted against a dry run that had used different values.
///
/// Adding a rule is adding a member here, with its own test. It is deliberately a small act with a
/// visible cost: a set nobody can extend from a program file is a set that cannot grow into a
/// language by accident.

/// One rule by which an answer is worked out from another.
enum DerivationRule {
  /// The first DNS label of a name — `m1.example.com` gives `m1`.
  ///
  /// What a cluster is called inside a fleet, everywhere a full domain would be too long or would
  /// not be a legal name. A value with no dot in it is its own first label and comes back unchanged;
  /// what this must never do is refuse, because whether the source is a domain at all is the shape
  /// check's question and not this one's.
  firstDnsLabel('first_dns_label_of', _firstDnsLabel),

  /// The name with its first DNS label taken off — `m1.example.com` gives `example.com`.
  ///
  /// The zone a name sits in, which is what tells two names apart that share a fleet. A value with
  /// no dot has nothing to take off and comes back unchanged.
  withoutFirstDnsLabel('without_first_dns_label_of', _withoutFirstDnsLabel),

  /// The value itself, unchanged.
  ///
  /// For the case where an answer is only ever ANOTHER answer when nobody supplied it — a cluster
  /// naming which one keeps the books, where leaving it out means "this one". Written as a default
  /// rather than as a derivation, it fills only what was not answered, and the two are the same rule
  /// under two triggers: `derived` always, `default_from` where nothing was given.
  itself('itself', _itself);

  /// Declares a rule under the name a program file writes.
  const DerivationRule(this.written, this._apply);

  /// The name a program file writes for this rule.
  final String written;

  final String Function(String) _apply;

  /// [source] under this rule.
  String applyTo(String source) => _apply(source);

  /// The rule [written] names, or null when nothing here is called that.
  ///
  /// Null and not a throw: the LOADER asks this to refuse a program file naming a rule that does not
  /// exist, and that refusal reads better than a stack trace. Everything past the loader holds a
  /// rule rather than a name.
  static DerivationRule? named(String written) {
    for (final DerivationRule rule in values) {
      if (rule.written == written) {
        return rule;
      }
    }
    return null;
  }

  /// Every rule's name, for a refusal that has to list them.
  static List<String> get allWritten => <String>[
    for (final DerivationRule rule in values) rule.written,
  ];
}

String _itself(String source) => source;

String _firstDnsLabel(String source) => source.split('.').first;

String _withoutFirstDnsLabel(String source) {
  final int dot = source.indexOf('.');
  return dot < 0 ? source : source.substring(dot + 1);
}

/// How one declared answer is worked out from another.
@immutable
final class Derivation {
  /// Declares that this answer is [rule] applied to the answer named [from].
  const Derivation({required this.rule, required this.from});

  /// The rule that works it out.
  final DerivationRule rule;

  /// The name of the answer it is worked out from.
  final String from;
}
