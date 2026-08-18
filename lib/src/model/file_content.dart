import 'package:meta/meta.dart';

/// What a file step answers when it is asked what its file should hold.
///
/// **Two answers, because there are two.** Usually it is text. Sometimes the machine has no business
/// with the file at all — a routing rule set where nothing is steered, a registry mirror where there
/// is no registry to mirror — and on such a machine there is nothing to write, nothing to plan, and
/// nothing an undo could take back.
///
/// **That is not the same as the file already holding the right thing**, which is what a check
/// answers by comparing. This is the file having no place on this machine in the first place.
///
/// Sealed, and one method rather than two, because the second answer usually comes from the same
/// reading as the first: a step composes its text out of what it found, and where it found nothing
/// there is no text to compose. Asked as two questions, the reading happens twice, and the step is
/// left writing a branch it can prove is unreachable and the compiler cannot.
@immutable
sealed class FileContent {
  const FileContent();

  /// The file holds [text].
  const factory FileContent.text(String text) = TextContent;

  /// This machine needs no such file, because [because].
  const factory FileContent.nothing(String because) = NothingToWrite;
}

/// The file holds this text. See [FileContent.text].
@immutable
final class TextContent extends FileContent {
  /// Answers with the text the file should hold.
  const TextContent(this.text);

  /// What the file should hold, byte for byte.
  final String text;
}

/// This machine needs no such file. See [FileContent.nothing].
///
/// The reason is written for the operator: it is what they read in the plan beside a step that did
/// nothing, and beside the check that was satisfied without anything happening.
@immutable
final class NothingToWrite extends FileContent {
  /// Answers that there is nothing to write, because [because].
  const NothingToWrite(this.because);

  /// Why this machine has no business with the file, in the operator's words.
  final String because;
}
