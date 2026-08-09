import '../domain/http.dart';
import '../domain/step.dart';
import '../domain/step_context.dart';
import '../model/failures.dart';
import '../model/step_plan.dart';

/// A step whose work is one request.
///
/// It supplies the plan and the apply; the step supplies the request and its own check. As with a
/// command, the check cannot be derived: what proves that a record was published is not the status
/// code of the call that published it.
base mixin HttpStep on Step {
  /// The request this step sends.
  HttpRequest requestFor(StepContext context);

  /// Which statuses count as the request having worked.
  ///
  /// Anything in the two hundreds by default. A step that treats a `409 Conflict` as "it was
  /// already there" says so here rather than swallowing every status.
  bool accepts(int status) => status >= 200 && status < 300;

  @override
  Future<StepPlan> plan(StepContext context) async {
    final HttpRequest request = requestFor(context);
    return StepPlan.request(request.method, request.url, body: request.body);
  }

  @override
  Future<void> apply(StepContext context) async {
    final HttpRequest request = requestFor(context);
    final HttpAnswer answer = await context.http.send(request);
    if (!accepts(answer.status)) {
      throw RequestRefused(
        method: request.method,
        url: request.url,
        status: answer.status,
        body: answer.body,
      );
    }
  }
}
