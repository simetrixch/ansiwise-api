import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

/// An answer worked out from another, before the first step and inside the fingerprint.
///
/// Some values an installation needs are not questions anybody should be asked, because they follow
/// from a question already answered. Asking for both invites a pair that does not match, and a
/// selector built on the mismatch finds nothing and says nothing — which is the failure this exists
/// to remove, measured on a real tree before it was built.
void main() {
  ArgumentSpec text(String name) =>
      ArgumentSpec(name: name, kind: ArgumentKind.text, describes: 'the $name');

  ArgumentSpec derived(String name, DerivationRule rule, String from) => ArgumentSpec(
    name: name,
    kind: ArgumentKind.text,
    describes: 'the $name',
    required: false,
    derivation: Derivation(rule: rule, from: from),
  );

  const DeclaredAnswers nothing = DeclaredAnswers(<ArgumentSpec>[]);

  group('the rules themselves', () {
    test('the first DNS label is the piece before the first dot', () {
      expect(DerivationRule.firstDnsLabel.applyTo('m1.example.com'), 'm1');
      expect(DerivationRule.firstDnsLabel.applyTo('s1.a.b.example.com'), 's1');
    });

    test('a name with no dot is its own first label, and is not refused', () {
      // Whether the source is a domain at all is the shape check's question. A rule that also
      // refused would put the same judgement in two places, and they would disagree one day.
      expect(DerivationRule.firstDnsLabel.applyTo('localhost'), 'localhost');
      expect(DerivationRule.withoutFirstDnsLabel.applyTo('localhost'), 'localhost');
    });

    test('taking the first label off leaves the zone the name sits in', () {
      expect(DerivationRule.withoutFirstDnsLabel.applyTo('m1.example.com'), 'example.com');
      expect(DerivationRule.withoutFirstDnsLabel.applyTo('s1.a.b.example.com'), 'a.b.example.com');
    });

    test('a rule is looked up by the name a program file writes, and an unknown one is null', () {
      // Null rather than a throw, because the LOADER asks this in order to refuse a file naming a
      // rule that does not exist — and that refusal reads better than a stack trace.
      expect(DerivationRule.named('first_dns_label_of'), DerivationRule.firstDnsLabel);
      expect(DerivationRule.named('firstDnsLabel'), isNull);
      expect(DerivationRule.named('reverse'), isNull);
      expect(DerivationRule.allWritten.length, DerivationRule.values.length);
    });
  });

  group('what an operator supplies', () {
    test('a derived answer is worked out and stands beside the rest', () {
      const DeclaredAnswers declared = DeclaredAnswers(<ArgumentSpec>[]);
      final DeclaredAnswers program = DeclaredAnswers(<ArgumentSpec>[
        text('fqdn'),
        derived('cluster_name', DerivationRule.firstDnsLabel, 'fqdn'),
      ]);
      expect(declared.specs, isEmpty);

      final Arguments answers = program.validate(<String, Object?>{
        'fqdn': 'm1.example.com',
      }, program: 'p');

      expect(answers.text('fqdn'), 'm1.example.com');
      expect(answers.text('cluster_name'), 'm1');
    });

    test('it is NOT missing when nobody supplied it, which is the whole point', () {
      // Without holding it out of the required check, a program declaring one would refuse every
      // answer file that did not carry the value it exists to work out.
      final DeclaredAnswers program = DeclaredAnswers(<ArgumentSpec>[
        text('fqdn'),
        derived('cluster_name', DerivationRule.firstDnsLabel, 'fqdn'),
      ]);

      expect(
        () => program.validate(<String, Object?>{'fqdn': 'm1.example.com'}, program: 'p'),
        returnsNormally,
      );
    });

    test('supplying it as well is refused, naming it', () {
      // Two versions of one fact, and the pair not matching is exactly what deriving it prevents.
      final DeclaredAnswers program = DeclaredAnswers(<ArgumentSpec>[
        text('fqdn'),
        derived('cluster_name', DerivationRule.firstDnsLabel, 'fqdn'),
      ]);

      expect(
        () => program.validate(<String, Object?>{
          'fqdn': 'm1.example.com',
          'cluster_name': 'something-else',
        }, program: 'p'),
        throwsA(
          isA<AnswersRejected>().having(
            (AnswersRejected refused) => refused.message,
            'message',
            contains('cluster_name'),
          ),
        ),
      );
    });

    test('THE INNOCENT NEIGHBOUR: an ordinary answer is still required', () {
      // Without this, holding derived answers out of the check could quietly hold every answer out
      // of it, and a program would accept an answer file carrying nothing at all.
      final DeclaredAnswers program = DeclaredAnswers(<ArgumentSpec>[
        text('fqdn'),
        derived('cluster_name', DerivationRule.firstDnsLabel, 'fqdn'),
      ]);

      expect(
        () => program.validate(const <String, Object?>{}, program: 'p'),
        throwsA(
          isA<AnswersRejected>().having(
            (AnswersRejected refused) => refused.message,
            'message',
            contains('fqdn'),
          ),
        ),
      );
    });
  });

  group('what the declaration itself may not say', () {
    test('a source the program does not declare is refused, naming both', () {
      final DeclaredAnswers program = DeclaredAnswers(<ArgumentSpec>[
        derived('cluster_name', DerivationRule.firstDnsLabel, 'nowhere'),
      ]);

      expect(
        () => program.validate(const <String, Object?>{}, program: 'p'),
        throwsA(
          isA<AnswersRejected>().having(
            (AnswersRejected refused) => refused.message,
            'message',
            allOf(contains('cluster_name'), contains('nowhere')),
          ),
        ),
      );
    });

    test('a chain is refused, so no order of evaluation has to be understood', () {
      // One pass and not a chain. A chain is where an order of evaluation starts to matter, and an
      // order of evaluation is the beginning of the language a program file may not become.
      final DeclaredAnswers program = DeclaredAnswers(<ArgumentSpec>[
        text('fqdn'),
        derived('zone', DerivationRule.withoutFirstDnsLabel, 'fqdn'),
        derived('zone_label', DerivationRule.firstDnsLabel, 'zone'),
      ]);

      expect(
        () => program.validate(<String, Object?>{'fqdn': 'm1.example.com'}, program: 'p'),
        throwsA(
          isA<AnswersRejected>().having(
            (AnswersRejected refused) => refused.message,
            'message',
            allOf(contains('zone_label'), contains('itself worked out')),
          ),
        ),
      );
    });

    test('a source holding no text is refused rather than worked out from nothing', () {
      final DeclaredAnswers program = DeclaredAnswers(<ArgumentSpec>[
        const ArgumentSpec(name: 'count', kind: ArgumentKind.integer, describes: 'a count'),
        derived('label', DerivationRule.firstDnsLabel, 'count'),
      ]);

      expect(
        () => program.validate(<String, Object?>{'count': 3}, program: 'p'),
        throwsA(isA<AnswersRejected>()),
      );
    });

    test('a program with no answers at all is still fine', () {
      expect(nothing.validate(const <String, Object?>{}, program: 'p').names, isEmpty);
    });
  });

  group('an answer that falls back to another', () {
    ArgumentSpec fallsBack(String name, String from) => ArgumentSpec(
      name: name,
      kind: ArgumentKind.text,
      describes: 'the $name',
      required: false,
      defaultFrom: from,
    );

    test('takes the other value where nobody supplied it', () {
      // The case this exists for: a cluster naming which one keeps the books, where leaving it out
      // means this one. Without it the operator types the same domain twice and the two can differ.
      final DeclaredAnswers program = DeclaredAnswers(<ArgumentSpec>[
        text('fqdn'),
        fallsBack('books_cluster', 'fqdn'),
      ]);

      final Arguments answers = program.validate(<String, Object?>{
        'fqdn': 'm1.example.com',
      }, program: 'p');

      expect(answers.text('books_cluster'), 'm1.example.com');
    });

    test('keeps what was supplied, which is the half that makes it a fallback', () {
      final DeclaredAnswers program = DeclaredAnswers(<ArgumentSpec>[
        text('fqdn'),
        fallsBack('books_cluster', 'fqdn'),
      ]);

      final Arguments answers = program.validate(<String, Object?>{
        'fqdn': 's1.example.com',
        'books_cluster': 'm1.example.com',
      }, program: 'p');

      expect(answers.text('books_cluster'), 'm1.example.com');
    });

    test('a derivation may read one, because the fallback runs first', () {
      // A fallback is what the operator would have typed, so what is worked out from it is worked
      // out from an answer — not from another derivation.
      final DeclaredAnswers program = DeclaredAnswers(<ArgumentSpec>[
        text('fqdn'),
        fallsBack('books_cluster', 'fqdn'),
        derived('books_short', DerivationRule.firstDnsLabel, 'books_cluster'),
      ]);

      final Arguments answers = program.validate(<String, Object?>{
        'fqdn': 'm1.example.com',
      }, program: 'p');

      expect(answers.text('books_short'), 'm1');
    });

    test('a chain of fallbacks is refused', () {
      final DeclaredAnswers program = DeclaredAnswers(<ArgumentSpec>[
        text('fqdn'),
        fallsBack('one', 'fqdn'),
        fallsBack('two', 'one'),
      ]);

      expect(
        () => program.validate(<String, Object?>{'fqdn': 'm1.example.com'}, program: 'p'),
        throwsA(isA<AnswersRejected>()),
      );
    });

    test('a source nobody answered either is refused, not filled with nothing', () {
      final DeclaredAnswers program = DeclaredAnswers(<ArgumentSpec>[
        const ArgumentSpec(
          name: 'fqdn',
          kind: ArgumentKind.text,
          describes: 'the domain',
          required: false,
        ),
        fallsBack('books_cluster', 'fqdn'),
      ]);

      expect(
        () => program.validate(const <String, Object?>{}, program: 'p'),
        throwsA(isA<AnswersRejected>()),
      );
    });
  });
}
