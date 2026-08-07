# Contributing

Contributions are welcome, and the copyright question is settled before you write the code rather
than after.

## What happens to your copyright

By opening a pull request you agree that Simetrix GmbH may use your contribution under any terms,
including the terms this project is licensed under and any commercial license Simetrix GmbH grants.
You keep your own copyright and may use your contribution however you like.

This is what lets a single entity license the project commercially. Without it, every commercial
license would need the agreement of everyone who ever contributed a line.

## What a contribution has to carry

The gate is `tools/ci.sh`, and it has to say `ci: OK — every check green` before a pull request is
looked at. It builds a pinned container and runs six checks and the whole test suite inside it, so a
green run on your machine means the same thing as a green run on anyone else's.

```
bash tools/ci.sh
```

Two of those checks are worth knowing about before you start:

**api-purity** scans `lib`, `test`, `bin` and `programs` to the byte and fails on the name of any
platform: microk8s, vault, argocd, cloudflare, helm, snap, digita, tenant, consumer, zot, tekton,
kubectl, netplan, hetzner, authentik. There is no exempt path. This framework runs a declared program
against a machine and knows nothing about what is being deployed — that is the whole point of it, and
knowledge of a platform arrives one word at a time, in a doc comment that explains a port by the tool
the author had in mind. Everything platform-specific belongs in a plugin.

**exec-confinement** fails when anything in the shipped library outside `lib/src/infrastructure/`
references `dart:io`, `Process`, `File` or `HttpClient`. The four ports are the only way any code
reaches outside, and that is what makes a dry run provable rather than intended.

## What a step, a port or an engine change has to prove

- every public member carries a doc comment, and `dart analyze --fatal-infos --fatal-warnings` is
  clean — no `dynamic`, no raw types, no implicit casts, and `!` is not used
- a check that cannot go red proves nothing, so a new check comes with a counter-probe that plants
  the thing it forbids and asserts it is reported
- a test asserts behaviour rather than the shape of an implementation

## Reporting something

Open an issue. If it is a defect, the useful shape is: what you ran, what the record says, and what
you expected instead — a run record is on disk under `/var/lib/ansiwise/runs` and names the step, its
source file and line, and every command that reached the machine.
