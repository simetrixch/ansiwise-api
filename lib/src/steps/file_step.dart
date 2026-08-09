import '../domain/step.dart';
import '../domain/step_context.dart';
import '../model/check_result.dart';
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

  /// What the file should hold.
  ///
  /// Computed rather than stored, because it may depend on what the machine says. It is read in
  /// every mode including a dry run, so it must not change anything — the ports enforce that.
  Future<String> contentFor(StepContext context);

  @override
  Future<CheckResult> check(StepContext context) async {
    final String path = pathFor(context);
    final String wanted = await contentFor(context);
    if (!await context.files.exists(path)) {
      return const CheckResult.ready();
    }
    final String current = await context.files.read(path);
    return current == wanted
        ? CheckResult.satisfied('$path already holds what this step writes')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String path = pathFor(context);
    final String wanted = await contentFor(context);
    final String current = await context.files.exists(path) ? await context.files.read(path) : '';
    return StepPlan.diff(path, before: current, after: wanted);
  }

  @override
  Future<void> apply(StepContext context) async {
    await context.files.write(pathFor(context), await contentFor(context), mode: mode);
  }
}
