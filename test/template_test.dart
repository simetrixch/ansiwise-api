import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

void main() {
  group('template rendering', () {
    test('renders standard required slots', () {
      const Template template = Template(
        path: 't.yaml',
        text: 'hello <world>',
      );
      expect(
        template.filledWith(<String, String>{'world': 'earth'}),
        'hello earth',
      );
    });

    test('drops line for missing optional slot', () {
      const Template template = Template(
        path: 't.yaml',
        text: 'line 1\noptional <foo?> here\nline 3',
      );
      expect(
        template.filledWith(<String, String>{}),
        'line 1\nline 3',
      );
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

    test('drops line for carried slot if no previous match', () {
      const Template template = Template(
        path: 't.yaml',
        text: 'line 1\ncarry <foo!> here\nline 3',
      );
      expect(
        template.filledWith(<String, String>{}, previousText: 'line 1\nno match here\nline 3'),
        'line 1\nline 3',
      );
    });

    test('keeps line for carried slot and replaces with previous value', () {
      const Template template = Template(
        path: 't.yaml',
        text: 'line 1\ncarry <foo!> here\nline 3',
      );
      expect(
        template.filledWith(<String, String>{}, previousText: 'line 1\ncarry old_value here\nline 3'),
        'line 1\ncarry old_value here\nline 3',
      );
    });

    test('carried slot refuses provided value from run', () {
      const Template template = Template(
        path: 't.yaml',
        text: 'carry <foo!>',
      );
      expect(
        () => template.filledWith(<String, String>{'foo': 'val'}),
        throwsA(isA<TemplateRefused>().having(
          (e) => e.message,
          'message',
          contains('they are carried slots, which never take values from a run'),
        )),
      );
    });
  });
}
