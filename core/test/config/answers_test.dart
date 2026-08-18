import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:test/test.dart';

/// What a program has to be told before it runs, and what happens when it is told the wrong thing.
///
/// This is what makes the client agnostic: the app renders a form out of these declarations and
/// hard-codes no field, so an input added to a program file appears in the app without a line
/// changing there, and an app in front of a different plugin shows that plugin's questions.
void main() {
  Program load(String yaml) => loadProgram(yaml, where: 'test.yaml');

  // A program with no steps at all is refused by the loader, and rightly: it would do nothing. The
  // step name here is never resolved — loadProgram parses, and binding to the registry is later.
  const String head =
      'name: deploy-thing\nroles: [master]\nsteps:\n  - step: a_step\n    on_failure: exit\n';

  group('declaring them', () {
    test('reads a declaration in the order the file wrote it', () {
      final Program program = load(
        '${head}answers:\n'
        '  - name: fqdn\n'
        '    kind: text\n'
        '    describes: the domain name this installation is reached under\n'
        '  - name: workers\n'
        '    kind: integer\n'
        '    describes: how many workers to run\n',
      );

      expect(program.answers.specs.map((ArgumentSpec s) => s.name), <String>['fqdn', 'workers']);
      expect(program.answers.specs.first.kind, ArgumentKind.text);
      expect(program.answers.specs.last.kind, ArgumentKind.integer);
    });

    test('a program that declares nothing needs nothing', () {
      expect(load(head).answers.specs, isEmpty);
    });

    test('names the secret ones', () {
      final Program program = load(
        '${head}answers:\n'
        '  - name: fqdn\n    kind: text\n    describes: the domain\n'
        '  - name: repo_pat\n    kind: text\n    describes: a credential\n    secret: true\n',
      );

      expect(program.answers.secretNames, <String>['repo_pat']);
    });

    test('refuses a secret with a default', () {
      // A default for a secret is a credential written into a file that ships to every
      // installation, which is the one thing this must never make easy.
      expect(
        () => load(
          '${head}answers:\n'
          '  - name: repo_pat\n    kind: text\n    describes: a credential\n'
          '    secret: true\n    default: hunter2\n',
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid p) => p.message,
            'message',
            contains('is secret, so it cannot have a default'),
          ),
        ),
      );
    });

    test('refuses a declaration with no describes, because the form would show a bare name', () {
      expect(
        () => load('${head}answers:\n  - name: fqdn\n    kind: text\n'),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid p) => p.message,
            'message',
            contains('it is what the form shows the operator'),
          ),
        ),
      );
    });

    test('refuses two declarations under one name', () {
      expect(
        () => load(
          '${head}answers:\n'
          '  - name: fqdn\n    kind: text\n    describes: one\n'
          '  - name: fqdn\n    kind: integer\n    describes: two\n',
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid p) => p.message,
            'message',
            contains('declared twice'),
          ),
        ),
      );
    });

    test('refuses an unknown kind, and says which kinds there are', () {
      expect(
        () => load(
          '${head}answers:\n  - name: fqdn\n    kind: hostname\n    describes: the domain\n',
        ),
        throwsA(
          isA<ProgramInvalid>()
              .having((ProgramInvalid p) => p.message, 'message', contains('needs a "kind"'))
              .having((ProgramInvalid p) => p.message, 'message', contains('text')),
        ),
      );
    });

    test('refuses a key nobody declared rather than ignoring it', () {
      expect(
        () => load(
          '${head}answers:\n'
          '  - name: fqdn\n    kind: text\n    describes: the domain\n    hidden: true\n',
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid p) => p.message,
            'message',
            contains('has no key "hidden"'),
          ),
        ),
      );
    });

    test('refuses a default of the wrong kind', () {
      expect(
        () => load(
          '${head}answers:\n  - name: workers\n    kind: integer\n'
          '    describes: how many\n    default: many\n',
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid p) => p.message,
            'message',
            contains('holds integer'),
          ),
        ),
      );
    });

    test('reads the values an answer may hold', () {
      final Program program = load(
        '${head}answers:\n'
        '  - name: role\n    kind: text\n    allowed: [master, slave]\n'
        '    describes: what this machine is\n',
      );

      expect(program.answers.specs.single.allowed, <String>['master', 'slave']);
    });

    test('an answer with no closed set permits anything of its kind', () {
      final Program program = load(
        '${head}answers:\n  - name: fqdn\n    kind: text\n    describes: the domain\n',
      );

      expect(program.answers.specs.single.allowed, isEmpty);
      expect(program.answers.specs.single.permits('anything at all'), isTrue);
    });

    test('only text may name allowed values', () {
      // A flag already has two values, and a number or a list of text has no small closed set worth
      // writing out — so declaring one there is a mistake, refused rather than quietly ignored.
      expect(
        () => load(
          '${head}answers:\n  - name: workers\n    kind: integer\n'
          '    allowed: ["1", "2"]\n    describes: how many\n',
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid p) => p.message,
            'message',
            contains('only text may name allowed values'),
          ),
        ),
      );
    });

    test('refuses an empty allowed list, which would permit nothing at all', () {
      expect(
        () => load(
          '${head}answers:\n  - name: role\n    kind: text\n'
          '    allowed: []\n    describes: what this machine is\n',
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid p) => p.message,
            'message',
            contains('non-empty list'),
          ),
        ),
      );
    });

    test('refuses a default outside the set the same file declares', () {
      // A value the file itself calls illegal, standing in wherever a program says nothing.
      expect(
        () => load(
          '${head}answers:\n  - name: role\n    kind: text\n'
          '    allowed: [master, slave]\n    default: gateway\n'
          '    describes: what this machine is\n',
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid p) => p.message,
            'message',
            contains('holds one of master, slave'),
          ),
        ),
      );
    });

    test('names every bad declaration at once', () {
      // One refusal per run is an operator running it three times to learn three things.
      expect(
        () => load(
          '${head}answers:\n'
          '  - name: a\n    kind: nope\n    describes: one\n'
          '  - name: b\n    kind: text\n'
          '  - kind: text\n    describes: three\n',
        ),
        throwsA(
          isA<ProgramInvalid>()
              .having((ProgramInvalid p) => p.message, 'message', contains('"a" needs a "kind"'))
              .having((ProgramInvalid p) => p.message, 'message', contains('"b" needs "describes"'))
              .having(
                (ProgramInvalid p) => p.message,
                'message',
                contains('an answer needs a "name"'),
              ),
        ),
      );
    });
  });

  group('answering them', () {
    const DeclaredAnswers declared = DeclaredAnswers(<ArgumentSpec>[
      ArgumentSpec(name: 'fqdn', kind: ArgumentKind.text, describes: 'the domain'),
      ArgumentSpec(
        name: 'workers',
        kind: ArgumentKind.integer,
        describes: 'how many',
        required: false,
        defaultValue: 3,
      ),
      ArgumentSpec(
        name: 'repo_pat',
        kind: ArgumentKind.text,
        describes: 'a credential',
        secret: true,
      ),
    ]);

    // An answer whose legal values are a closed set, kept apart from [declared] so the tests around
    // it keep measuring exactly what they measured before.
    const DeclaredAnswers closed = DeclaredAnswers(<ArgumentSpec>[
      ArgumentSpec(
        name: 'role',
        kind: ArgumentKind.text,
        describes: 'what this machine is',
        allowed: <String>['master', 'slave'],
      ),
    ]);

    test('takes a value the declaration names', () {
      expect(
        closed.validate(<String, Object?>{'role': 'slave'}, program: 'deploy-thing').text('role'),
        'slave',
      );
    });

    test('refuses a value outside the set, and says what the set is', () {
      // Naming the set is the difference between an operator fixing it and an operator guessing:
      // the values live in the program file and nowhere the message would otherwise reach.
      expect(
        () => closed.validate(<String, Object?>{'role': 'gateway'}, program: 'deploy-thing'),
        throwsA(
          isA<AnswersRejected>()
              .having(
                (AnswersRejected r) => r.message,
                'message',
                contains('holds one of master, slave'),
              )
              .having((AnswersRejected r) => r.message, 'message', contains('"gateway"')),
        ),
      );
    });

    test('a wrong kind and a wrong value are two different sentences', () {
      // Both are "that will not do", and an operator who is told the wrong one looks in the wrong
      // place: one is a value of the right sort that this answer does not offer, the other is not
      // even that sort of value.
      String refusalFor(Object value) {
        try {
          closed.validate(<String, Object?>{'role': value}, program: 'deploy-thing');
        } on AnswersRejected catch (rejected) {
          return rejected.message;
        }
        return 'nothing was refused';
      }

      expect(refusalFor(7), contains('holds text'));
      expect(refusalFor(7), isNot(contains('holds one of')));
      expect(refusalFor('gateway'), contains('holds one of'));
    });

    test('takes what was supplied and fills in what was not', () {
      final Arguments answered = declared.validate(<String, Object?>{
        'fqdn': 'm1.example.com',
        'repo_pat': 'a-credential',
      }, program: 'deploy-thing');

      expect(answered.text('fqdn'), 'm1.example.com');
      expect(answered.integer('workers'), 3);
    });

    test('refuses a missing required answer, naming what it is for', () {
      expect(
        () =>
            declared.validate(<String, Object?>{'fqdn': 'm1.example.com'}, program: 'deploy-thing'),
        throwsA(
          isA<AnswersRejected>()
              .having((AnswersRejected r) => r.message, 'message', contains('"repo_pat"'))
              .having((AnswersRejected r) => r.message, 'message', contains('a credential')),
        ),
      );
    });

    test('refuses a value of the wrong kind', () {
      expect(
        () => declared.validate(<String, Object?>{
          'fqdn': 'm1.example.com',
          'repo_pat': 'a-credential',
          'workers': 'three',
        }, program: 'deploy-thing'),
        throwsA(
          isA<AnswersRejected>().having(
            (AnswersRejected r) => r.message,
            'message',
            contains('holds integer'),
          ),
        ),
      );
    });

    test('refuses an answer nobody declared rather than ignoring it', () {
      // Ignoring it turns a typo into a value that silently went missing, which is exactly the
      // failure a declaration exists to prevent.
      expect(
        () => declared.validate(<String, Object?>{
          'fqdn': 'm1.example.com',
          'repo_pat': 'a-credential',
          'fqnd': 'm1.example.com',
        }, program: 'deploy-thing'),
        throwsA(
          isA<AnswersRejected>().having(
            (AnswersRejected r) => r.message,
            'message',
            contains('has no answer "fqnd"'),
          ),
        ),
      );
    });

    test('names every problem at once', () {
      expect(
        () => declared.validate(<String, Object?>{
          'workers': 'three',
          'nonsense': 1,
        }, program: 'deploy-thing'),
        throwsA(
          isA<AnswersRejected>()
              .having((AnswersRejected r) => r.message, 'message', contains('"fqdn"'))
              .having((AnswersRejected r) => r.message, 'message', contains('"repo_pat"'))
              .having((AnswersRejected r) => r.message, 'message', contains('holds integer'))
              .having((AnswersRejected r) => r.message, 'message', contains('"nonsense"')),
        ),
      );
    });

    const DeclaredAnswers shaped = DeclaredAnswers(<ArgumentSpec>[
      ArgumentSpec(
        name: 'color',
        kind: ArgumentKind.text,
        describes: 'the color',
        denied: <String>['black', 'white'],
      ),
      ArgumentSpec(
        name: 'email',
        kind: ArgumentKind.text,
        describes: 'the email',
        shape: 'mailbox',
      ),
      ArgumentSpec(name: 'use_db', kind: ArgumentKind.flag, describes: 'whether to use a db'),
      ArgumentSpec(
        name: 'db_host',
        kind: ArgumentKind.text,
        describes: 'the database host',
        statedWhen: StatedWhen(answer: 'use_db', equals: 'true'),
      ),
    ]);

    test('refuses a value on the denied list', () {
      expect(
        () => shaped.validate(<String, Object?>{
          'color': 'black',
          'email': 'a@b.com',
          'use_db': false,
        }, program: 'deploy-thing'),
        throwsA(
          isA<AnswersRejected>().having(
            (AnswersRejected r) => r.message,
            'message',
            contains('must not be one of black, white'),
          ),
        ),
      );
    });

    test('refuses a value with wrong shape', () {
      expect(
        () => shaped.validate(<String, Object?>{
          'color': 'red',
          'email': 'not_an_email',
          'use_db': false,
        }, program: 'deploy-thing'),
        throwsA(
          isA<AnswersRejected>().having(
            (AnswersRejected r) => r.message,
            'message',
            contains('is of the wrong shape (must be mailbox)'),
          ),
        ),
      );
    });

    test('validates stated_when trigger', () {
      // Condition met, but not provided
      expect(
        () => shaped.validate(<String, Object?>{
          'color': 'red',
          'email': 'a@b.com',
          'use_db': true,
        }, program: 'deploy-thing'),
        throwsA(
          isA<AnswersRejected>().having(
            (AnswersRejected r) => r.message,
            'message',
            contains('needs the answer "db_host"'),
          ),
        ),
      );

      // Condition not met, but provided
      expect(
        () => shaped.validate(<String, Object?>{
          'color': 'red',
          'email': 'a@b.com',
          'use_db': false,
          'db_host': 'localhost',
        }, program: 'deploy-thing'),
        throwsA(
          isA<AnswersRejected>().having(
            (AnswersRejected r) => r.message,
            'message',
            contains('is given but its trigger does not hold'),
          ),
        ),
      );

      // Correctly provided
      expect(
        shaped
            .validate(<String, Object?>{
              'color': 'red',
              'email': 'a@b.com',
              'use_db': true,
              'db_host': 'localhost',
            }, program: 'deploy-thing')
            .text('db_host'),
        'localhost',
      );
    });
  });
}
