<!-- The rules for this repository, read before writing a line in it and before reviewing one.
     They live here rather than in a central directory because they govern THIS code: a rule
     that has to be mirrored onto a machine before it takes effect is a rule that silently does
     not apply on the machine nobody mirrored. -->

# ansiwise-api

A typed step engine that runs a declared program against a machine, records what happened, refuses
what must not run, and serves all of it as REST. Read this before writing a line in it, and before
reviewing one.

## Stack baseline

**Plain `dart:io`, no HTTP framework.** That is a departure from the usual Dart server advice and it
has one cause, which every other decision here follows from:

> **Nothing may listen.** The server runs inside an SSH session the client opened, speaking HTTP
> over that channel's own standard input and output. There is no port, no socket, and no service
> that stays alive.

| considered | why not |
|---|---|
| `dart_frog` | `dart_frog dev`/`build` produce a server that binds a port. Its file-system routing and dev loop are built around that. |
| `shelf` | `shelf_io.serveRequests` would in fact work over our channel — it takes a request stream rather than binding. It was measured and left out anyway: the only thing it buys here is chunked streaming, and `dart:io`'s `HttpResponse` already emits `transfer-encoding: chunked` by itself. A dependency for a benefit that exists without it is a dependency for nothing. |
| `serverpod` | binds ports, and brings Postgres and Redis. |
| `conduit`, `vania`, `jaguar` | all bind ports. |

Two reasons the constraint is worth this much:

- **SSH is already the authentication.** A listener needs one of its own, with keys to issue, expire
  and revoke — for a caller that does not exist. Both callers come in over SSH.
- **It has to work on a machine with nothing on it.** `deploy-host` runs against a fresh Ubuntu
  reached with a username and a password. A service cannot serve the first run, because it is not
  there yet.

Verified before it was designed in: `HttpServer.listenOn` takes a `ServerSocket`, so two small
adapters (a `Socket` and a `ServerSocket` over the channel's pipes) carry it, and a spike ran a
request through end to end.

## The one non-negotiable: contract before implementation

**`another caller` is TypeScript** and calls this API. That makes the contract a shared artifact
rather than a byproduct of the endpoint code: before implementing or changing an endpoint, the
OpenAPI definition changes first, and the endpoint follows.

A check verifies that every route the router serves appears in the spec and the other way round. The
Dart side does not generate from it — six routes are not worth a generator — but the TypeScript side
may, and either way the two cannot silently disagree.

Read `ansiwise-docs/ansiwise/deployment/README.md` before designing or changing any endpoint,
error shape or versioning decision.

## Layering

One direction of dependency, top depends on lower, never the reverse:

| Layer | Lives in | May do | May never do |
|---|---|---|---|
| Endpoint | `lib/src/api/` | read the request, call one thing, map the result to a response | business rules, `dart:io`, touching a machine |
| Engine | `lib/src/engine/` | run a program, apply the failure policy, unwind, record, gate | know about HTTP, know what microk8s is |
| Step | `lib/src/steps/steps/` | one thing to a machine, through the four ports | reach outside except through the ports |
| Port | `lib/src/domain/` | declare `Shell`, `Files`, `Http`, `Clock`, `Recorder`, `RunStore` | contain an implementation |
| Model | `lib/src/model/` | the types the client also depends on | import anything above it |
| Infrastructure | `lib/src/infrastructure/` | `dart:io`, the real ports, the record on disk | business rules |

Two consequences worth stating, because they are where it slips:

- **An endpoint should be boring.** If it is longer than about twenty lines or contains an `if` about
  what a run means, that belongs in the engine.
- **Nothing under `lib/src/api/` imports `dart:io`.** The test: the API layer compiles and every
  endpoint is tested by calling it with a request object. If it needs an HTTP fixture, the layering
  has leaked.

Enforced, not intended:

| rule | check |
|---|---|
| no word of `tool/api-purity.words` appears anywhere under `lib/`, `test/`, `bin/` or `programs/` | `test/checks/api_purity_test.dart` |
| `dart:io`, `Process`, `File`, `HttpClient`, `SSHClient` only under an `infrastructure/` directory, plus `test/`, `bin/` and `tool/` | `test/checks/exec_confinement_test.dart` |
| imports point inward | `test/checks/layering_test.dart` |
| `install`, `setup`, `desktop` are abolished as program, sub-command and directory names | `test/checks/naming_test.dart` |

These are checks because a package boundary used to keep the first two and no longer does. Widening
one is a decision, not a fix.

## Project layout

**Two folders in the repository and nothing else** — no melos, no `apps/`, no `packages/`.

```
ansiwise/
  ansiwise-api/
    lib/src/model/          the contract the client also depends on
    lib/src/domain/         interfaces only — no implementation, no dart:io
    lib/src/engine/         Runner, planning ports, recording ports, Redactor, resolver, Gate
    lib/src/config/         the program-file loader and the catalogue
    lib/src/api/            the REST surface — pure, testable by calling it
    lib/src/steps/          the BASE classes: CommandStep, FileStep, HttpStep, WaitStep
    lib/src/infrastructure/ the real ports and the record on disk — the ONLY dart:io
    lib/src/testing/        the fakes, shipped so both halves share them
    lib/src/steps/     the concrete steps and the registry — the ONLY platform knowledge
    programs/               the program files
    bin/                    the command line, and `serve`
  ansiwise-client/      the Flutter app
```

The Dart package name is `ansiwise_api`, with underscores, because a package name may not carry
a hyphen.

## The five properties everything rests on

**1. Four ports are the whole outside world.** `Shell`, `Files`, `Http`, `Clock`. A step never starts
a process, opens a file or sends a request itself. That single fact is what makes a dry run provable,
a record complete without anyone logging, and every step testable against a fake.

**2. A verdict comes from a checked postcondition, never from an exit code.** `check()` runs again
after `apply()`, and a step whose check does not then answer `Satisfied` has failed — whatever the
command returned. The shell this replaced had eleven phases that reported success over a real
failure, every one by trusting an exit code.

**3. A dry run cannot change anything, and it is guaranteed twice.** The engine calls `plan()` and
never `apply()`; and the ports handed to the step throw on anything not declared `observes`. The
second guarantee is the one that does not depend on the step being written correctly.

**4. Every step says whether it can be taken back.** `ReversibleStep`, `IrreversibleStep` (with a
reason written for the operator, not for a reviewer), or `ObservingStep` for a gate that changes
nothing. `Step`'s constructor is private, so the compiler refuses a step that says none of the three.

**5. YAML is data, never logic.** No loops, no expressions, no templating, no anchors, no aliases. A
program file names steps, gives them arguments, puts named predicates behind `when:`, and declares
`on_failure:`. The moment it can compute, what gets debugged is the file instead of the code.

## Dependency injection

**Constructor injection everywhere. No globals, no statics, no singletons, no service locator** —
including `Clock`, or no timeout is deterministically testable.

There is one composition root, in `bin/`. Nothing constructs a real port, a recorder or a store
inline: that makes the dependency invisible and the code untestable. A step receives a
`StepContext` holding the four ports, already scoped to that step, and has no way to reach anything
else.

Expensive resources are built once at startup, never per request.

## Errors: sealed values at the boundary, exceptions inside

Business outcomes are **values**. Exceptions are for a step's own failure and for genuinely
exceptional faults.

```dart
sealed class CheckResult { }        // Ready · Satisfied · Blocked
sealed class Verdict { }            // Succeeded · Skipped · Warned · Issued · Died
sealed class StepPlan { }           // ArgvPlan · DiffPlan · RequestPlan · NothingPlan
sealed class EngineFailure implements Exception { }
```

Because each is sealed, an exhaustive `switch` means adding a variant produces a compile error at
every site that reacts to it, instead of a silent wrong answer in production. `CheckResult` has
three answers and not two for exactly this reason: `Satisfied` is both how idempotence is expressed
and how success is proven.

The endpoint does one thing with a failure: map it to HTTP, in one place.

**One departure from the usual rule, stated because it looks like a mistake otherwise.** The usual
rule is that no exception message reaches the client. Here the client is the operator of that
machine, and a deployment record exists so the person fixing it can read it — a generic 500 would
make it worthless. What makes that safe is the `Redactor`: everything on its way into the record
passes through one place that removes secrets, and that is why the record may be world-readable.
The control is the same, applied at the right boundary.

Uncaught exceptions still close the record before the process ends, because a run that crashed
without leaving its record is the one outcome worse than failing.

## The wire format and the model

**The model IS the contract, deliberately, and there are no DTOs.** `RunRecord` and `RunEvent` are
read by three readers: the file on the machine, the client over the network, and the operator
opening `events.jsonl` by hand. One shape serves all three, which is why an exported run can be
opened later by the same reader.

That is a departure from separating DTO and domain, and it is a departure with a cost: the day the
wire needs to diverge from what is stored, two shapes appear and the mapping has to live in one
place per type. Until that day, two shapes that must not drift are a liability rather than an asset.

Serialisation is hand-written, by an exhaustive `switch` on each sealed family, so a new variant
breaks the build until somebody serialises it. `freezed` and `json_serializable` would give the same
guarantee and also `==` and `copyWith` — at the price of `build_runner` in the pinned container and
generated files in the tree. Dart 3's sealed classes already give the exhaustiveness that was
freezed's main draw, so what is left did not pay for the build step. `==` is genuinely missing and
is the one place to reconsider.

## Cross-cutting concerns

- **Config**: read once at startup into a typed value; fail fast on a missing one rather than
  discovering it on the first request. Never reach for the environment deep inside a step.
- **Correlation**: stronger than a request id here. Every event carries a dense sequence number that
  is never reused, and every step's record names the range of events belonging to it — which is what
  lets a client that lost its connection ask for everything after the last one it holds.
- **Timeouts**: every outbound call gets an explicit one. `Command.timeout` and `HttpRequest.timeout`
  exist for it. Dart's default is to wait forever, which turns one slow dependency into a hung run
  that nobody can tell from a working one.
- **Authentication is SSH**, and there is nothing else to arrange. **Authorization** — whether a run
  may start — is the `Gate`, and it lives in the engine rather than in the API, because the command
  line and `another caller` must meet the same door. A gate in a user interface is a gate that can
  be walked around.
- **Isolates**: only for genuinely CPU-bound work. Everything here is I/O and already async.

## Writing a step

One class, one file, one record line, one test beside it. The filename is the step's registered name
in `snake_case`; the class is the same name in `PascalCase`.

```dart
final class RequireMachineSize extends ObservingStep {
  const RequireMachineSize({required this.vcpu, required this.memoryKilobytes});

  factory RequireMachineSize.fromArguments(Arguments arguments) => ...;

  static const List<ArgumentSpec> arguments = <ArgumentSpec>[...];

  @override
  Future<CheckResult> check(StepContext context) async { ... }
}
```

Then register it in `lib/src/steps/registry.dart` — by hand, because Dart compiled ahead of
time has no reflection. That is what lets a check count the registry against the classes on disk in
both directions. The `source:` is the line the class is declared on, and a check verifies it,
because a number nobody checks drifts within a week.

**Everything a step does comes from its declared arguments.** A step reaching for a constant baked
into its constructor or read from the environment is invisible to the gate's fingerprint, and two
runs differing only in that value would count as the same input.

**A command that only looks must say so** — `Command.observing(...)`. The default is that a command
changes something, so a command nobody thought about is refused by a dry run rather than run by it.

**A step with no target state is not a step.** `apt-get update` always does work and nothing about a
machine says whether it has been done, so it can never answer whether it still needs to run. It is
how another step reaches its target state instead.

## Writing a refusal

**Report everything wrong at once, never the first thing.** The resolver does it, the program loader
does it, and `require_commands` does it. An operator fixing a file one refusal per run is an operator
running it five times to learn five things.

A refusal names what is wrong in the operator's words and what to do about it. *"htpasswd is not on
the path — it comes from the apache2-utils package"* beats *"missing tool"*.

## Style, and it is enforced

- `dart analyze --fatal-infos` clean, with `strict-casts`, `strict-inference`, `strict-raw-types`
- `dart format` at page width 100
- **No `dynamic`, no raw types, no implicit casts, and `!` is forbidden.** Needing a null assertion
  means the type was chosen wrong. Use `if (x case final T y)` or an explicit `as` on a value
  already tested.
- Every public member carries a doc comment. Tests are exempt via `test/analysis_options.yaml`.
- `final class` and `const` constructors by default; `sealed` wherever a caller must handle every
  case.
- `avoid_catches_without_on_clauses` is on: catch `Exception`, let `Error` through.

A comment explains the mechanism, what breaks without it, or why an obvious-looking alternative
fails. It never defends a decision to an imagined critic, and it never names a ticket, a phase or a
plan — those live on the board and outlive their meaning in a file.

## Packages

In: `yaml`, `path`, `args`, `meta`, `collection`, `crypto`. Dev: `test`, `lints`.

**Never write a version from memory.** Query pub.dev's API, the Docker Hub tag API or the GitHub
releases API, and say in a comment where the number came from and when. A tag list is paginated and
unsorted, so one page is not an answer and the highest on a page is not the latest.

**Judge a package by its release history, not by its reputation.** `shelf` at 1.4.2 from 2024 with
7.8 million monthly downloads and full pub points is finished, not abandoned; a package with a
recent version and fifty downloads is neither.

## Running the checks

**`dart test` is the gate.** Four of the five checks are tests under `test/checks/` — api-purity,
exec-confinement, layering and naming. Each reads the tree through `test/checks/source_tree.dart`,
which serves the repository on disk and a planted scratch tree through the same interface, so the
scan that judges this repository is the scan its counter-probe proves can go red.

The fifth is `dart run tool/analysis.dart`, and it is a program rather than a test because it cannot
be one: a test runs inside the package it would judge, so it is compiled by the very analysis it is
meant to fail on. What it decides is `tool/gate/analysis_check.dart`, behind a `DartToolchain` port,
and `test/checks/analysis_check_test.dart` is its counter-probe — a scripted answer for the parsing
and the real analyzer and formatter over a planted package for the day either tool changes what it
writes.

`dart run tool/ci.dart` is the faithful run, and there is no shell anywhere in it. It builds the
pinned container and starts itself inside it with `--inside`, which copies the tree off the
read-only mount and then runs `dart pub get` per package, `dart run tool/analysis.dart` once over
the tree, and `dart test` per package. `--rebuild` forces a fresh image; `--shell` hands you the
container with the tree already in place.

**It is the only CI.** Checks run locally, in Docker or WSL. No hosted workflow is created for them —
a standing rule of this project, not a workaround.

Every check carries a counter-probe: it plants the thing it forbids and asserts that it is reported,
and it plants the correct neighbour and asserts that it is not. A check that always passes is the
worst kind, because it reads as coverage.

Adding a check means adding a `*_test.dart` under `test/checks/`. `dart test` discovers it, and a
check that fails to compile is a red run rather than a member the runner walked past.

The gate itself is checked the same way. `test/checks/container_gate_test.dart`,
`test/checks/package_gate_test.dart` and `test/checks/gate_tree_test.dart` drive the two halves of
`tool/ci.dart` against a fake container engine and a fake toolchain, so the image tag, the decision
to build, what the container is told to run, the order of the steps and the verdict line are facts
rather than things somebody checks by watching a container start.

## Review checklist

- [ ] The endpoint contains no business logic and calls one thing
- [ ] Nothing under `lib/src/api/` imports `dart:io`
- [ ] Every dependency is a constructor parameter; nothing is constructed inline
- [ ] A step reaches outside only through `Shell`, `Files`, `Http`, `Clock`
- [ ] Every command that only looks is declared `observing`
- [ ] The step's verdict comes from `check()` after `apply()`, not from an exit code
- [ ] The step extends `ReversibleStep`, `IrreversibleStep` or `ObservingStep`, and an irreversible
      reason says what cannot be reversed rather than that no undo was written
- [ ] A second run of the step reports that there is nothing to do, and a test proves it
- [ ] Everything the step does comes from its declared arguments
- [ ] The step is in the registry, and its `source:` line is right
- [ ] Every refusal names all the problems, not the first
- [ ] Every outbound call has a timeout
- [ ] The OpenAPI spec changed in the same commit as the endpoint
- [ ] No secret can reach the record other than through the `Redactor`
- [ ] `dart run tool/ci.dart` ends with `ci: OK — every check green`

## Reference files

- `ansiwise-docs/ansiwise/deployment/README.md` — the architecture, the two folders, the REST
  surface, and the eight places the plan was wrong and the harvest was right
- `ansiwise-docs/ansiwise/deployment/checks.md` — the 35 checks of the shell suite, each marked
  as surviving the rewrite or needing to be reborn as a Dart test
- the four program chapters beside them — 407 steps and over 250 incident comments, verbatim, each
  anchored into `ansiwise@legacy-master`. Every incident there becomes a test.
