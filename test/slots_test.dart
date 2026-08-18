import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:test/test.dart';

/// The one slot notation every filling goes through, in the framework and in every plugin above it.
void main() {
  group('what counts as a slot', () {
    test('a lower-case name in angle brackets, and nothing else', () {
      expect(slotsIn('releases/<stage>/root.yaml'), <Slot>[const Slot('stage', SlotKind.required)]);
      expect(slotsIn('<a>/<b-2>/<a>'), <Slot>[
        const Slot('a', SlotKind.required),
        const Slot('b-2', SlotKind.required),
      ], reason: 'each name once, in order');
      expect(
        slotsIn('<Stage> <STAGE> <under_score> <>'),
        isEmpty,
        reason: 'the grammar is the notation — what it rejects is not a slot',
      );
    });

    test('optional and carried slots', () {
      expect(slotsIn('<stage?>'), <Slot>[const Slot('stage', SlotKind.optional)]);
      expect(slotsIn('<stage!>'), <Slot>[const Slot('stage', SlotKind.carried)]);
      expect(slotsIn('<a> <a?> <a!>'), <Slot>[
        const Slot('a', SlotKind.required),
        const Slot('a', SlotKind.optional),
        const Slot('a', SlotKind.carried),
      ]);
    });
  });

  group('filling', () {
    test('every named slot gets its value, a value without a slot changes nothing', () {
      expect(
        filledSlots('https://idp.<master-domain>/o/<client>/', <String, String>{
          'master-domain': 'm1.example.com',
          'client': 'headlamp',
          'unused': 'x',
        }),
        'https://idp.m1.example.com/o/headlamp/',
      );
    });
  });

  group('the leftover scan', () {
    test('reports what still looks like a slot, misspellings included', () {
      // Broader than the grammar on purpose: a mis-cased or misspelled name matches no declared
      // slot, and a scan that only knew the grammar would wave it through to the tool.
      expect(leftoverSlotIn('a <verison> b'), '<verison>');
      expect(leftoverSlotIn('a <Stage> b'), '<Stage>');
      expect(leftoverSlotIn('nothing here'), isNull);
    });
  });

  group('the mark that is two characters', () {
    test('<name!?> is read as one slot, carried and optional', () {
      expect(slotsIn('a <release!?> b'), <Slot>[const Slot('release', SlotKind.carriedOptional)]);
    });

    test('it writes itself back exactly as it was read, or a replace would miss it', () {
      // The text is used to find and replace the slot in a line. A round trip that lost a character
      // would leave the literal slot in the file, which is the failure the whole notation avoids.
      expect(const Slot('release', SlotKind.carriedOptional).text, '<release!?>');
      expect(slotsIn('<release!?>').single.text, '<release!?>');
    });

    test('THE INNOCENT NEIGHBOURS: the three older marks still read as they did', () {
      expect(slotsIn('<a>').single.kind, SlotKind.required);
      expect(slotsIn('<a?>').single.kind, SlotKind.optional);
      expect(slotsIn('<a!>').single.kind, SlotKind.carried);
    });

    test('the marks in the other order are not a slot at all', () {
      // `?!` is not the notation. It matches nothing, so what it leaves behind is caught by the
      // broader scan for anything in angle brackets rather than being read as something it is not.
      expect(slotsIn('<a?!>'), isEmpty);
      expect(leftoverSlotIn('<a?!>'), '<a?!>');
    });
  });
}
