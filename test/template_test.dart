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
}
