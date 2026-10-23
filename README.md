# Topogamer0 Homebrew Tap

[![CI](https://github.com/Topogamer0/homebrew-tap/actions/workflows/ci.yml/badge.svg)](https://github.com/Topogamer0/homebrew-tap/actions/workflows/ci.yml)

[Homebrew](https://brew.sh) formulae for my projects, on macOS (Apple Silicon and Intel) and Linux.

| Formula | What it installs | Project |
| --- | --- | --- |
| `luau-shield` | `luau-shield`, a static security analyzer for Roblox games written in Luau | [Topogamer0/luau-shield](https://github.com/Topogamer0/luau-shield) |
| `failstep` | `failstep`, systematic allocation-failure testing for C, with its runtime library, headers, CMake package and pkg-config file | [Topogamer0/failstep](https://github.com/Topogamer0/failstep) |
| `ollama-c` | `libollama`, a C client library for [Ollama](https://ollama.com), with `ollama.h`, CMake package and pkg-config file | [Topogamer0/Ollama-C](https://github.com/Topogamer0/Ollama-C) |
| `ollama-c-rag` | `ragc`, local retrieval-augmented generation over your documents, and the `libollama-rag` library | [Topogamer0/ollama-c-rag](https://github.com/Topogamer0/ollama-c-rag) |

## Install

```sh
brew install topogamer0/tap/luau-shield
brew install topogamer0/tap/failstep
brew install topogamer0/tap/ollama-c
brew install topogamer0/tap/ollama-c topogamer0/tap/ollama-c-rag
```

`ollama-c-rag` uses the `ollama-c` formula of this tap, so name both in the same command (see
[Tap trust](#tap-trust) below).

Update with `brew update && brew upgrade`, remove with `brew uninstall <formula>` (and
`brew untap topogamer0/tap` to remove the tap).

### Tap trust

Since Homebrew 6.0, formulae from taps outside Homebrew must be
[trusted](https://docs.brew.sh/Tap-Trust) before Homebrew loads them. Installing a fully qualified
name (`brew install topogamer0/tap/<formula>`) trusts that formula only. That is why
`ollama-c-rag` is installed together with `ollama-c`: otherwise Homebrew refuses to load its
dependency with `Refusing to load formula topogamer0/tap/ollama-c from untrusted tap`.

To use short names (`brew install luau-shield`, `brew upgrade ollama-c-rag`...), trust the tap, or
only the formulae you use:

```sh
brew tap topogamer0/tap
brew trust topogamer0/tap                          # every formula of this tap
brew trust --formula topogamer0/tap/luau-shield    # or a single one
```

### Platforms

| | macOS arm64 | macOS x86_64 | Linux x86_64 | Linux arm64 |
| --- | --- | --- | --- | --- |
| `luau-shield` | release binary | release binary | release binary (static) | built from source (Rust) |
| `failstep` | release binary | built from source (CMake) | release binary | built from source (CMake) |
| `ollama-c` | built from source | built from source | built from source | built from source |
| `ollama-c-rag` | built from source | built from source | built from source | built from source |

For builds from source Homebrew installs CMake (and Rust for `luau-shield` on Linux arm64) first.

## luau-shield

```sh
brew install topogamer0/tap/luau-shield
luau-shield check src            # analyse the Luau files of a Rojo project
luau-shield rules                # list the rules
```

See the [luau-shield README](https://github.com/Topogamer0/luau-shield#usage) for the options,
configuration and CI integration.

## failstep

```sh
brew install topogamer0/tap/failstep
```

The formula installs the `failstep` CLI and everything needed to build programs under it:
`libfailstep.a`, `failstep/failstep.h` and `failstep/override.h`, the CMake package (with
`failstep_instrument()`) and `failstep.pc`.

```sh
cc -g -fsanitize=address -include failstep/override.h \
   $(pkg-config --cflags failstep) myprog.c $(pkg-config --libs failstep) -o myprog
failstep enumerate -- ./myprog
```

```cmake
find_package(failstep REQUIRED)
add_executable(mytests mytests.c)
failstep_instrument(mytests)
```

`pkg-config` comes with `brew install pkgconf`. CMake finds Homebrew packages by itself when
Homebrew's `bin` directory is on `PATH`; otherwise pass `-DCMAKE_PREFIX_PATH=$(brew --prefix)`.

## ollama-c

```sh
brew install topogamer0/tap/ollama-c
```

A shared library (`libollama`), `ollama.h`, the CMake package `ollama-c` and `ollama-c.pc`. It uses
the system libcurl on macOS and Homebrew's `curl` on Linux.

```cmake
find_package(ollama-c REQUIRED)
target_link_libraries(my_app PRIVATE ollama::ollama)
```

```sh
cc my_app.c $(pkg-config --cflags --libs ollama-c) -o my_app
```

## ollama-c-rag

```sh
brew install topogamer0/tap/ollama-c topogamer0/tap/ollama-c-rag
ollama pull embeddinggemma && ollama pull gemma3    # the default models, with Ollama running
ragc index ~/notes
ragc ask "When do we go to Sicily?"
```

The formula installs `ragc` and the shared library `libollama-rag` with `ollama_rag.h`, the CMake
package `ollama-rag-c` and `ollama-rag-c.pc`. It links the `ollama-c` formula and SQLite (the
system one on macOS, Homebrew's `sqlite` on Linux) instead of the copies the project can bundle.

```cmake
find_package(ollama-rag-c REQUIRED)
target_link_libraries(my_app PRIVATE ollama::rag)
```

```sh
cc my_app.c $(pkg-config --cflags --libs ollama-rag-c) -o my_app
```

Ollama itself is not a dependency: install it from [ollama.com](https://ollama.com) or with
`brew install ollama`.

## How the formulae are tested

[CI](.github/workflows/ci.yml) runs on every push and pull request:

- `brew style` and `brew audit --strict --online` for every formula, loaded as macOS and Linux on
  both architectures;
- for each formula, on macOS arm64 (`macos-15`), macOS x86_64 (`macos-15-intel`), Linux x86_64
  (`ubuntu-24.04`) and Linux arm64 (`ubuntu-24.04-arm`): `brew install --build-from-source`
  (which installs the release binary where the formula uses one), `brew test`,
  `brew audit --strict --online` and `brew linkage --test`.

The `test` blocks do real work rather than checking `--version`: `luau-shield` must report a
`loadstring` reached by a client value in a small Luau script and nothing in its fixed version;
`failstep` must find the missing NULL check of a C program built through pkg-config and through
its CMake package, and accept the fixed program; `ollama-c` and `ollama-c-rag` run against a fake
Ollama server started by the test, which checks the requests and answers them, and their libraries
are built against through CMake and pkg-config.

## Releasing a new version

The release workflows of luau-shield, failstep, Ollama-C and ollama-c-rag update their formula
here when a version is tagged, with [`scripts/bump-formula.py`](scripts/bump-formula.py): new URLs
and version, and the SHA-256 of every downloaded file. See
[docs/release-integration.md](docs/release-integration.md) for the workflow jobs and the
`HOMEBREW_TAP_TOKEN` secret they need.

To update a formula by hand:

```sh
python3 scripts/bump-formula.py Formula/luau-shield.rb 0.3.0
```

## "Install with Homebrew" sections for the project READMEs

To paste into the README of each project.

### luau-shield

Inside `## Installation`, after the Rokit, Aftman and Foreman instructions:

````markdown
### Install with Homebrew

On macOS (Apple Silicon and Intel) and Linux:

```sh
brew install topogamer0/tap/luau-shield
```

The formula installs the release binary (on Linux arm64 it builds luau-shield from source).
Update it with `brew upgrade luau-shield`.
````

### failstep

At the beginning of `## Installation`:

````markdown
### Install with Homebrew

On macOS (Apple Silicon and Intel) and Linux:

```sh
brew install topogamer0/tap/failstep
```

This installs the `failstep` CLI, `libfailstep`, the headers and the CMake and pkg-config files,
so `find_package(failstep)` and `pkg-config failstep` work without building failstep yourself.
````

### Ollama-C

Before `## Building`:

````markdown
## Install with Homebrew

On macOS (Apple Silicon and Intel) and Linux:

```sh
brew install topogamer0/tap/ollama-c
```

This builds and installs the shared library, `ollama.h` and the CMake and pkg-config files. Use it
with `find_package(ollama-c)` and `ollama::ollama`, or with
`pkg-config --cflags --libs ollama-c` (no `--static` needed: Homebrew installs a shared library).
````

### ollama-c-rag

Before `## Building`:

````markdown
## Install with Homebrew

On macOS (Apple Silicon and Intel) and Linux:

```sh
brew install topogamer0/tap/ollama-c topogamer0/tap/ollama-c-rag
```

This installs `ragc` and the library (`ollama_rag.h`, CMake and pkg-config files), built with the
Ollama-C formula of the same tap and with SQLite from the system (macOS) or from Homebrew (Linux).
Naming `ollama-c` too lets Homebrew 6 or later load it: formulae from third-party taps must be
[trusted](https://docs.brew.sh/Tap-Trust), and installing a fully qualified name trusts that
formula only. You still need [Ollama](https://ollama.com) running, with an embedding model and a
chat model.
````
