import 'dart:convert';

import '../../domain/catalogue.dart';
import '../../domain/resolved_program.dart';
import '../../domain/run_launcher.dart';
import '../../domain/run_store.dart';
import '../../engine/fingerprint.dart';
import '../../engine/gate.dart';
import '../../model/failures.dart';
import '../../model/mode.dart';
import '../../model/names.dart';
import '../../model/run_record.dart';
import '../api_message.dart';
import '../record_json.dart';

/// Starting runs, listing them, and opening one.
///
/// The interesting one is starting. It returns as soon as the run is going rather than when it
/// finishes, because a deployment takes an hour and the session that asked for it may close in the
/// first minute. Everything after that is read from the record.
final class RunsEndpoint {
  /// Answers from [store], starting runs through [launcher].
  const RunsEndpoint({
    required this.store,
    required this.launcher,
    required this.catalogue,
    required this.gate,
    required this.json,
    required this.commit,
  });

  /// Where past and present runs are read from.
  final RunStore store;

  /// What starts a run.
  final RunLauncher launcher;

  /// The programs that may be started.
  final Catalogue catalogue;

  /// What decides whether a run may start at all.
  final Gate gate;

  /// What puts a record on the wire.
  final RecordJson json;

  /// The commit this installation's branch is on, which is part of what makes an input the same.
  final String commit;

  /// `GET /runs` — past runs, newest first.
  Future<ApiResponse> list(ApiRequest request) async {
    final String? programName = request.query('program');
    final String? modeName = request.query('mode');

    final Mode? mode = modeName == null ? null : _modeNamed(modeName);
    if (modeName != null && mode == null) {
      return Refused.badRequest('there is no mode called "$modeName"');
    }

    final List<RunRecord> runs = await store.list(
      program: programName == null ? null : ProgramName(programName),
      mode: mode,
      limit: request.queryInt('limit', orElse: 50),
    );
    return Answered(<String, Object?>{
      'runs': <Object?>[for (final RunRecord run in runs) json.run(run)],
    });
  }

  /// `GET /runs/{id}` — one run, with a row per step.
  Future<ApiResponse> one(RunId id) async {
    final RunRecord? run = await store.read(id);
    if (run == null) {
      return Refused.notFound('no run is called "$id"');
    }
    return Answered(json.run(run));
  }

  /// `POST /runs` — start one.
  ///
  /// The body is `{"program": "...", "mode": "test|dry|run"}`. Answers `202` with the run's
  /// identifier, because the run has been accepted and not finished.
  Future<ApiResponse> start(ApiRequest request) async {
    final Object? parsed = _parseBody(request.body);
    if (parsed is! Map<String, Object?>) {
      return const Refused.badRequest('the body must be a JSON object');
    }

    final Object? programName = parsed['program'];
    final Object? modeName = parsed['mode'];
    if (programName is! String || modeName is! String) {
      return const Refused.badRequest('the body needs "program" and "mode", both text');
    }

    final ResolvedProgram? program = catalogue.byName(ProgramName(programName));
    if (program == null) {
      return Refused.notFound('no program is called "$programName"');
    }
    final Mode? mode = _modeNamed(modeName);
    if (mode == null) {
      return Refused.badRequest('there is no mode called "$modeName"');
    }

    // Checked before the gate and before the launcher: a run that cannot succeed must not be
    // started at all, because a half-finished installation waiting on a value somebody could have
    // typed at the start is worse than a refusal.
    final Object? supplied = parsed['answers'];
    if (supplied != null && supplied is! Map<String, Object?>) {
      return const Refused.badRequest('"answers" must be a JSON object');
    }
    final Map<String, Object?> answers =
        (supplied as Map<String, Object?>?) ?? const <String, Object?>{};
    try {
      program.declared.answers.validate(answers, program: programName);
    } on AnswersRejected catch (refused) {
      return Refused.badRequest(refused.message);
    }

    final String fingerprint = fingerprintOf(program: program, commit: commit);

    // Refused here as well as in the run itself, and the duplication is the point: the run refuses
    // because the process that acts has to be sure, and this refuses so that an operator gets a
    // sentence back instead of a run that starts and dies where nobody is watching.
    final Object? continues = parsed['resumes'];
    RunId? resumes;
    if (continues != null) {
      if (continues is! String || continues.isEmpty) {
        return const Refused.badRequest(
          '"resumes" is the identifier of the run this one continues',
        );
      }
      final RunRecord? earlier = await store.read(RunId(continues));
      if (earlier == null) {
        return Refused.notFound('there is no run called "$continues" to continue');
      }
      if (earlier.fingerprint != fingerprint) {
        return Refused.badRequest(
          'run "$continues" was a different input, so this would not be continuing it — start a '
          'fresh run instead, or say why the input changed',
        );
      }
      resumes = earlier.id;
    }

    try {
      final RunRecord? satisfiedBy = await gate.admit(
        mode: mode,
        program: program.declared.name,
        fingerprint: fingerprint,
      );
      // What the operator supplied travels ON, not the validated copy: the run checks it again
      // against the program's own declaration, and the process that will ACT on a value is the
      // one that has to be sure of it. The check above is what stops a run that cannot succeed
      // from being started at all.
      final RunId id = await launcher.start(
        program: program.declared.name,
        mode: mode,
        answers: answers,
        resumes: resumes,
      );
      return Answered(<String, Object?>{
        'run': id.value,
        'program': program.declared.name.value,
        'mode': mode.name,
        'fingerprint': fingerprint,
        if (resumes case final RunId earlier) 'resumes': earlier.value,
        // Which dry run let this one through, so the operator can see they are acting on the one
        // they just read rather than on some older green run they have forgotten about.
        if (satisfiedBy != null) 'admitted_by': satisfiedBy.id.value,
      }, status: 202);
    } on GateNotMet catch (refusal) {
      return Refused.notYet(refusal.message);
    }
  }

  static Mode? _modeNamed(String name) {
    for (final Mode mode in Mode.values) {
      if (mode.name == name) {
        return mode;
      }
    }
    return null;
  }

  static Object? _parseBody(String? body) {
    if (body == null || body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
