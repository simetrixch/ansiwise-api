/// The fakes every test of a step or a program is written against.
///
/// Kept in the package rather than in its test directory, because the package that declares the
/// concrete steps needs them too — and a fake that has to be written twice is a fake that drifts.
library;

export 'src/testing/fake_machine.dart';
export 'src/testing/memory_recorder.dart';
