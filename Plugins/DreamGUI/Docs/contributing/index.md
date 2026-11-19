---
title: Contributing
description: How to report a problem, propose a change and get a pull request merged — the issue forms and the environment command, the repository's layout, building in a host project, the Quick test gate, what a stored pointer is allowed to be, what to update with a change, the docs and translation flow, and AI-assisted contributions.
---

DreamGUI takes bug reports, proposals, docs fixes and pull requests on
[GitHub](https://github.com/TypeDreamMoon/DreamGUI). This page is the overview. The checklist a pull request is held
to is [CONTRIBUTING.md](../../CONTRIBUTING.md) in the repository. An AI agent starts at [AGENTS.md](../../AGENTS.md).

## Reporting a problem

Issues are opened through forms; a blank issue is not offered.

| Form | For |
| --- | --- |
| Bug report | Wrong output, a crash, or behaviour that differs from these docs |
| Feature or syntax proposal | Something DreamGUI or `.dui` cannot express or do yet. Open one before a feature pull request |
| AI wrote it wrong | An AI tool wrote `.dui` that did not build, looked wrong, or used names that do not exist |
| Docs or translation | A page here that is wrong, unclear, missing, or badly translated |

The bug and AI forms ask for the output of the environment command. Run it from your game project's folder:

```text
pwsh -NoProfile -File Plugins/DreamGUI/Tools/Get-DreamGUIEnvironment.ps1
```

It prints the plugin's version and commit, the engine's version and kind, the system, its UI language and the shell.
It starts nothing and prints no paths. Pass `-Project <path to>/<Project>.uproject` when the plugin is not inside the
project's `Plugins` folder. Questions and ideas go to
[Discussions](https://github.com/TypeDreamMoon/DreamGUI/discussions).

## The repository

| Folder | What it holds |
| --- | --- |
| `Source/` | The thirteen modules: eight runtime, four editor-side (`UncookedOnly`) and the test module ([module layers](../getting-started/project-layout.md#module-layers)) |
| `Shaders/`, `Config/`, `Content/`, `Resources/` | What the modules load: shaders, default settings, fonts and other assets, icons and the UMG parity tables |
| `Docs/` | This manual. English is the source; `Docs/zh-CN/` is its translation |
| `Tools/Tests/` | The test runner, its presets, the static checks |
| `Tools/TestHost/` | The minimal host project the suite builds and runs in |
| `DLoc/` | The editor UI's translations, kept with DreamLoc |
| `ThirdParty/` | msdfgen, committed as a single-file copy, so a plain clone builds |

The whole layout is under [What is in the plugin folder](../getting-started/project-layout.md#what-is-in-the-plugin-folder).

## Building

You need Unreal Engine 5.8 (source or launcher), PowerShell 7.2 or later, Python 3.8 or later and git. Win64 is the
only platform built and run. Build in a project that has the checkout as `Plugins/DreamGUI`; the
[test host](../tools/tests.md#the-test-host) is a minimal one, with the plugin as a git worktree of your clone:

```text
pwsh -NoProfile -File Tools/TestHost/New-DreamGUITestHost.ps1 -Root <host folder> -RepoPath <your clone> -Branch <your branch> -Detach -EngineRoot <engine root>
```

Its defaults are the maintainer's machine, so pass all four values. Build the whole editor target, never with
`-Module=`: a restricted build leaves the plugin's module manifest stale, and the plugin then fails to load as a whole.

## The test gate

Every pull request runs the `Quick` preset first:

```text
pwsh -NoProfile -File Tools/Tests/Invoke-DreamGUITests.ps1 -Project "<Project>/<Project>.uproject" -Engine "<engine root>"
```

It runs the static checks, builds, checks the module manifest, and runs the headless suite in an unattended editor.
Close every editor of that project first. Exit code `0` is green, `1` is red, `2` means the run could not be judged.
It prints one line that starts with `RESULT`: paste that line into the pull request. The other presets (`Rhi` for
the pixel tests, `Designer`, `Pie`, `All`), the report, known issues and the static checks' rules are on
[The automation suite](../tools/tests.md). `python Tools/Tests/static_checks.py` runs the static checks alone,
without an engine.

## Changing what a stored pointer is

A member that holds a `UObject` is a `TWeakObjectPtr` unless something names it strongly: a raw pointer is an address
that cannot say the object has gone, and a `TObjectPtr` keeps nothing alive outside a `UPROPERTY`. A member that holds
an RHI resource is a counted reference (`FTextureRHIRef`, `FBufferRHIRef`, `TRefCountPtr<...>`); RHI objects have no
weak form, so the choice is to hold one or not to store it. A pointer kept only to answer "is this still the same
thing?" is not an identity: an address freed and handed out again compares equal. Keep a counted reference, or a serial
of your own -- never the address.

Changing one is mechanical, but only the compiler can find every caller. These are the shapes it reports, and the two
it does not:

| Shape | Before | After |
| --- | --- | --- |
| Passed to something taking a raw pointer | `DrawFrames(Ctx.World, 2)` | `DrawFrames(Ctx.World.Get(), 2)` |
| Assigned to a raw local | `UWorld* W = Scoped.World;` | `... = Scoped.World.Get();` |
| Compared with `nullptr` | `if (Kinds.Surface != nullptr)` | `if (Kinds.Surface.IsValid())` |
| An out parameter | `Place(..., Kinds.CanvasRoot)` | take it in a raw local, then store it |
| A braced list or a cast | `{ static_cast<AActor*>(Rendered), ... }` | `.Get()` first, then cast |
| **Used as a truth value** | `if (Member)`, `!Member`, `Member ? a : b` | **does not compile**: `TWeakObjectPtr` deletes `operator bool` on purpose, "to avoid resolving weak pointers too often -- use `Get()` once in a function" |
| **Dereferenced with `->`** | `Kinds.Actor->GetWidget()` | **compiles unchanged, and means something else** |

The last row is the one that costs an afternoon. `TWeakObjectPtr::operator->` returns `Get()`, so every `->` line goes
on compiling -- and where the object has gone it now dereferences null and crashes on the spot, instead of reading
freed memory and sometimes getting away with it. That is the better behaviour and the reason for the change, but it
turns "passes most of the time" into "fails every time", so a test that starts failing after a change like this is
usually reporting a lifetime bug that was always there. Record it, say which step it fails at, and fix it separately --
do not revert the pointer.

Two more differences in meaning, both intended: `Weak == nullptr` is `!IsValid()`, so it is also true for an object
that has been collected, where the raw comparison only asked whether the pointer was set; and comparing a weak pointer
with a raw one builds a `TWeakObjectPtrBase` to do it, so in a path that runs every frame write `Member.Get() == Other`
instead.

So in a struct whose members become weak, read every `->` on them before trusting the build, and prefer an explicit
`if (UWorld* World = Ctx.World.Get())` over leaning on `operator->`. Nothing else has to change: a line that only
calls through the pointer is already correct.

**What the check does not see.** `stored-raw-pointer` reads headers only, so a struct declared inside a `.cpp` is not
read at all. The same code scanned with `.cpp` as well reports about 531 further members -- 459 of them in the test
module, the rest spread over the runtime, editor, input, extensions and tween modules; of twelve sampled, every one was
a real stored member rather than a false positive. That batch has not been done, and is deliberately a pass of its own:
stacking it on a change that has not been built yet would make any failure impossible to attribute. **A clean run of
this rule therefore means the headers are clean, not that the plugin stores no raw pointers.**

## What to update with a change

- The page here that describes the behaviour you changed.
- `CHANGELOG.md`: a line under `## Unreleased`, in `### New`, `### Changed` or `### Fixed`, for anything a project can
  notice.
- A new diagnostic code: `EDreamUIDiagnosticCode`, and both tables, [Diagnostics](../diagnostics/index.md) and
  `Docs/diagnostics/codes.md`. Codes are never renumbered or reused.
- A changed reflected type: regenerate the [class reference](../Reference/index.md) with the `DreamGUIReferenceDocs`
  commandlet. It is never edited by hand.
- A new or moved runtime file: its row in `Tools/Tests/module-owners.csv`.
- New tests: a name of the form `DreamGUI.<Area>.<Sentence>`, and a higher floor for the preset in
  `Tools/Tests/presets.json`.
- A new property meta tag: the `DreamGUI_` prefix ([Property meta tags](../guides/property-meta.md)).

## Docs and translations

English under `Docs/` is the source of this site. After a change reaches `main`, CI translates what changed into
`Docs/zh-CN/` with [dreamdocs](https://github.com/TypeDreamMoon/dreamdocs) and opens a pull request of its own, so a
contribution changes the English only. A Chinese sentence is corrected by editing the Chinese page; the next run keeps
the edit. `Docs/zh-CN/.align/` records which English paragraph each Chinese one came from and is never edited by hand.

## AI-assisted contributions

They are welcome on the same terms as any other. Name the tool and model in the pull request, paste the `RESULT` line
of the test run, and review every line before you submit: the person who opens the pull request is responsible for
it. Bulk AI-generated pull requests without test evidence are closed. [Working with AI agents](../tools/ai-agents.md)
describes what an agent has to work with.

## License and conduct

Contributions are licensed under the plugin's [MIT license](../../LICENSE); there is no CLA. The
[code of conduct](https://github.com/TypeDreamMoon/.github/blob/main/CODE_OF_CONDUCT.md) and the
[security policy](https://github.com/TypeDreamMoon/.github/blob/main/SECURITY.md) apply to every repository of the
project.
