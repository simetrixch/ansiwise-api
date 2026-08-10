import 'package:ansiwise_checks/audits.dart';

/// case-sensitivity — every directive of THIS repository spells the on-disk name byte for byte.
///
/// `import 'Foo.dart'` for a file named `foo.dart` compiles on Windows and fails on Linux, which is
/// the machine the product runs on. Nothing else catches it: the analyzer resolves the import
/// through the filesystem, and the Windows filesystem opens the wrong case without complaint.
///
/// [auditCaseSensitivity] decides it and plants the trees that prove the scan can go red; what is
/// here is this repository's own tree, which is what the audit takes when it is given none.
void main() => auditCaseSensitivity();
