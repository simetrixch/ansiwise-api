import '../domain/step.dart';
import '../domain/step_context.dart';
import '../model/check_result.dart';
import '../model/file_content.dart';
import '../model/step_plan.dart';

/// A step whose work is writing one file.
///
/// This one supplies all three: the check, the plan and the apply. A file is the case where the
/// postcondition can be derived — the file holds what the step writes, or it does not — so the step
/// only has to say which file and what goes in it.
///
/// Idempotence comes out of that for free, and so does the diff a dry run shows. A step that writes
/// a file and gets these from here cannot be the kind of step that rewrites an identical file every
/// run and reports having changed something.
base mixin FileStep on Step {
  /// The file this step writes.
  ///
  /// Given the context rather than read off the step, because the name of the file is often part of
  /// what the run was told: a stage config is `config.<stage>` and a cluster map is named for the
  /// domain, and both of those arrive as answers rather than as arguments a program file could
  /// write.
  String pathFor(StepContext context);

  /// The permission bits it ends up with.
  ///
  /// No default. A file this framework writes either holds something anyone may read or something
  /// only its owner may, and there is no sensible guess between the two.
  int get mode;

  /// What the file should hold, or why this machine needs no such file.
  ///
  /// Computed rather than stored, because it may depend on what the machine says. It is read in
  /// every mode including a dry run, so it must not change anything — the ports enforce that.
  ///
  /// **[FileContent.nothing] is the answer for a machine that has no business with the file at
  /// all** — a routing rule set where nothing is steered, a registry mirror where there is no
  /// registry to mirror. Without it a step in that position could not use this mixin: there is no
  /// text that means "no file", so each wrote its own check, plan and apply instead, three copies of
  /// what is here differing in exactly that one case.
  ///
  /// One question and not two, because both answers usually come from the same reading: a step
  /// composes its text out of what it found, and where it found nothing there is no text to compose.
  /// Asked separately, the reading happens twice and the step is left writing a branch it can prove
  /// unreachable and the compiler cannot.
  Future<FileContent> contentFor(StepContext context);

  @override
  Future<CheckResult> check(StepContext context) async {
    switch (await contentFor(context)) {
      case NothingToWrite(:final String because):
        return CheckResult.satisfied(because);
      case TextContent(:final String text):
        final String path = pathFor(context);
        if (!await context.files.exists(path)) {
          return const CheckResult.ready();
        }
        return await context.files.read(path) == text
            ? CheckResult.satisfied('$path already holds what this step writes')
            : const CheckResult.ready();
    }
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    switch (await contentFor(context)) {
      case NothingToWrite(:final String because):
        return StepPlan.nothing(because);
      case TextContent(:final String text):
        final String path = pathFor(context);
        final String current = await context.files.exists(path)
            ? await context.files.read(path)
            : '';
        return StepPlan.diff(path, before: current, after: text);
    }
  }

  @override
  Future<void> apply(StepContext context) async {
    // A machine with nothing to write is left alone. The engine only applies a step whose check
    // answered Ready, so this cannot be reached through a run — it is here because the mixin is
    // what a plugin author overrides one method of, and an apply that wrote regardless would put a
    // file on a machine whose own check had just said it has no business with one.
    if (await contentFor(context) case TextContent(:final String text)) {
      await context.files.write(pathFor(context), text, mode: mode);
    }
  }

  /// What the file held before this step wrote it, or null when it was not there.
  ///
  /// The whole of what a reversible file step needs in order to put the machine back: the text goes
  /// back, and null means the file was not there so the undo deletes it. It is here rather than
  /// written out in every such step because each would write the same three lines, and the one that
  /// got them subtly wrong would be the one whose undo mattered.
  ///
  /// It reads and changes nothing, so it is safe in every mode.
  Future<String?> contentBefore(StepContext context) async {
    final String path = pathFor(context);
    return await context.files.exists(path) ? context.files.read(path) : null;
  }
}
