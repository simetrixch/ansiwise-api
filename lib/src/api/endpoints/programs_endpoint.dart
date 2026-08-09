import '../../domain/arguments.dart';
import '../../domain/catalogue.dart';
import '../../domain/registry.dart';
import '../../domain/resolved_program.dart';
import '../../domain/step.dart';
import '../../model/names.dart';
import '../api_message.dart';

/// What the client renders its form and its step list from.
///
/// The client has no hard-coded field and no hard-coded list of programs. It asks here and shows
/// what `deployment/` declares, so a new input appears in the form without a line of the client
/// changing — and a client pointed at a different deployment shows that one's programs.
final class ProgramsEndpoint {
  /// Answers from [catalogue].
  const ProgramsEndpoint(this.catalogue);

  /// The programs this deployment declares.
  final Catalogue catalogue;

  /// `GET /programs` — every program, with its steps.
  ApiResponse list() => Answered(<String, Object?>{
    'programs': <Object?>[
      for (final ResolvedProgram program in catalogue.programs) _describe(program),
    ],
  });

  /// `GET /programs/{name}` — one program.
  ApiResponse one(ProgramName name) {
    final ResolvedProgram? program = catalogue.byName(name);
    if (program == null) {
      return Refused.notFound('no program is called "$name"');
    }
    return Answered(_describe(program));
  }

  Map<String, Object?> _describe(ResolvedProgram program) => <String, Object?>{
    'name': program.declared.name.value,
    'roles': <String>[for (final Role role in program.declared.roles) role.value],
    'steps': <Object?>[for (final ResolvedStep step in program.steps) _describeStep(step)],
    // What the client builds its form out of. A field is described here or it does not exist, which
    // is what lets one app stand in front of any plugin.
    'answers': <Object?>[
      for (final ArgumentSpec spec in program.declared.answers.specs)
        <String, Object?>{
          'name': spec.name,
          'kind': spec.kind.name,
          'describes': spec.describes,
          'required': spec.required,
          'secret': spec.secret,
          // Absent where anything of the kind will do, so a client tells "one of these" from "any
          // text" by whether the key is there rather than by an empty list it has to interpret.
          if (spec.allowed.isNotEmpty) 'allowed': spec.allowed,
          // A secret has no default — the loader refuses one — so this can never carry a
          // credential out.
          if (spec.hasDefault) 'default': spec.defaultValue,
        },
    ],
  };

  Map<String, Object?> _describeStep(ResolvedStep resolved) {
    // The step is built in order to ask it whether it can be undone. The registry holds a factory
    // and not an instance, so there is no other way to know — and this is the one thing the client
    // cannot derive for itself, because it is a property of the class rather than of the program
    // file. It is also what lets a dry run name the point beyond which there is no going back.
    final Step step = resolved.registered.create(resolved.entry.arguments);
    return <String, Object?>{
      'step': resolved.entry.step.value,
      'source': resolved.registered.source,
      'on_failure': resolved.entry.onFailure.name,
      'when': <String>[
        for (final RegisteredPredicate predicate in resolved.when) predicate.name.value,
      ],
      'reversible': step is ReversibleStep,
      if (step is IrreversibleStep) 'irreversible_reason': step.irreversibleReason,
      'arguments': <Object?>[
        for (final ArgumentSpec spec in resolved.registered.arguments)
          <String, Object?>{
            'name': spec.name,
            'kind': spec.kind.name,
            'describes': spec.describes,
            'required': spec.required,
            'secret': spec.secret,
            // A secret is reported as set or unset and never by value. The client that typed it
            // does not need it back, and the description travels further than the run does.
            if (spec.secret)
              'set': resolved.entry.arguments.has(spec.name)
            else
              'value': resolved.entry.arguments.raw(spec.name) ?? spec.defaultValue,
          },
      ],
    };
  }
}
