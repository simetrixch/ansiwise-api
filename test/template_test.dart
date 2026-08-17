import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

void main() {
  group('template rendering', () {
    test('renders standard required slots', () {
      const Template template = Template(path: 't.yaml', text: 'hello <world>');
      expect(template.filledWith(<String, String>{'world': 'earth'}), 'hello earth');
    });

    test('drops line for missing optional slot', () {
      const Template template = Template(
        path: 't.yaml',
        text: 'line 1\noptional <foo?> here\nline 3',
      );
      expect(template.filledWith(<String, String>{}), 'line 1\nline 3');
    });

    test('fills optional slot if present', () {
      const Template template = Template(
        path: 't.yaml',
        text: 'line 1\noptional <foo?> here\nline 3',
      );
      expect(
        template.filledWith(<String, String>{'foo': 'bar'}),
        'line 1\noptional bar here\nline 3',
      );
    });

    test('a carried slot with no earlier line to carry from refuses, and names the line', () {
      // It used to drop the line, and that is the failure this asserts against: the file comes out
      // written, the step reports done, and a line the template says belongs in it is simply not
      // in it. Nothing anywhere says so.
      const Template template = Template(path: 't.yaml', text: 'line 1\ncarry <foo!> here\nline 3');
      expect(
        () =>
            template.filledWith(<String, String>{}, previousText: 'line 1\nno match here\nline 3'),
        throwsA(
          isA<TemplateRefused>().having(
            (TemplateRefused refused) => refused.toString(),
            'reason',
            allOf(contains('t.yaml'), contains('line 2'), contains('<foo!>')),
          ),
        ),
      );
    });

    test('the first write of a file refuses rather than carrying nothing over', () {
      // The state every first run is in: there is no earlier content at all. Dropping every carried
      // line here would write a file missing all of them and report success, and the second run
      // would read that file back and report there was nothing left to do.
      const Template template = Template(path: 't.yaml', text: 'line 1\ncarry <foo!> here\nline 3');
      expect(
        () => template.filledWith(<String, String>{}),
        throwsA(
          isA<TemplateRefused>().having(
            (TemplateRefused refused) => refused.toString(),
            'reason',
            contains('first time this file is written'),
          ),
        ),
      );
    });

    test('two carried slots on one line are refused rather than resolved at random', () {
      // Each becomes `(.*)` in the expression built from the line, and `(.*)` is greedy: the first
      // would take everything up to the last fixed piece and the second whatever is left. That is
      // an answer nobody can predict from reading the template.
      const Template template = Template(path: 't.yaml', text: 'a <foo!> b <bar!> c');
      expect(
        () => template.filledWith(<String, String>{}, previousText: 'a one b two c'),
        throwsA(
          isA<TemplateRefused>().having(
            (TemplateRefused refused) => refused.toString(),
            'reason',
            allOf(contains('at most one'), contains('<foo!>'), contains('<bar!>')),
          ),
        ),
      );
    });

    test('keeps line for carried slot and replaces with previous value', () {
      const Template template = Template(path: 't.yaml', text: 'line 1\ncarry <foo!> here\nline 3');
      expect(
        template.filledWith(
          <String, String>{},
          previousText: 'line 1\ncarry old_value here\nline 3',
        ),
        'line 1\ncarry old_value here\nline 3',
      );
    });

    test('carried slot refuses provided value from run', () {
      const Template template = Template(path: 't.yaml', text: 'carry <foo!>');
      expect(
        () => template.filledWith(<String, String>{'foo': 'val'}),
        throwsA(
          isA<TemplateRefused>().having(
            (e) => e.message,
            'message',
            contains('they are carried slots, which never take values from a run'),
          ),
        ),
      );
    });
  });

  group('a slot that is carried AND optional', () {
    // The one case a plain carried slot cannot state: a value written by a LATER act, and therefore
    // absent the first time the file is made. A pinned version is the shape of it — a fresh
    // installation has nothing pinned, and a rewrite must hand back whatever was pinned since.
    const Template template = Template(
      path: 't.yaml',
      text: 'name: <name>\nrelease: <release!?>\n',
    );

    test('THE INNOCENT NEIGHBOUR: it carries the value where the file has one', () {
      // Without this, a version that always dropped the line would pass every assertion below and
      // silently throw away the value the whole slot exists to keep.
      expect(
        template.filledWith(<String, String>{
          'name': 'one',
        }, previousText: 'name: something-else\nrelease: v1.2.3\n'),
        'name: one\nrelease: v1.2.3\n',
      );
    });

    test('its line is DROPPED on the very first write, rather than refusing', () {
      expect(template.filledWith(<String, String>{'name': 'one'}), 'name: one\n');
    });

    test('its line is dropped where the earlier content has no line of that shape', () {
      expect(
        template.filledWith(<String, String>{
          'name': 'one',
        }, previousText: 'name: something-else\n'),
        'name: one\n',
      );
    });

    test('THE GUARD IS NOT LOST: a PLAIN carried slot still refuses on a first write', () {
      // The widening must not reach the slot beside it. Without this, making one kind droppable
      // could quietly make both, and every template pointed at the wrong file would write itself
      // out short and report success.
      const Template plain = Template(path: 't.yaml', text: 'release: <release!>\n');

      expect(
        () => plain.filledWith(const <String, String>{}),
        throwsA(
          isA<TemplateRefused>().having(
            (TemplateRefused refused) => refused.message,
            'message',
            contains('first time this file is written'),
          ),
        ),
      );
    });

    test('a run may not hand it a value either, exactly as a carried slot may not', () {
      expect(
        () => template.filledWith(<String, String>{'name': 'one', 'release': 'v9'}),
        throwsA(isA<TemplateRefused>()),
      );
    });

    test('it is not required, so a run holding nothing for it is not "unfilled"', () {
      expect(() => template.filledWith(<String, String>{'name': 'one'}), returnsNormally);
    });
  });
}
