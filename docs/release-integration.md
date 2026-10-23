# Updating the formulae from the project releases

When a version is tagged in luau-shield, failstep, Ollama-C or ollama-c-rag, a job of its release
workflow updates the formula in this tap: it checks out `Topogamer0/homebrew-tap`, runs
[`scripts/bump-formula.py`](../scripts/bump-formula.py) and pushes the result to `main`.

The script rewrites every `url` of the formula to the new version (release binaries and source
archives, on every platform), downloads each file and puts its SHA-256 in the `sha256` line that
follows the `url`. If a file is missing (an asset was renamed or not uploaded), it fails before
writing anything, and the job fails. It does nothing when the formula is already at the version, so
re-running a release is safe. The commit (`luau-shield 0.3.0`, ...) then runs the tap's
[CI](../.github/workflows/ci.yml), which installs and tests the new version on every platform.

Pre-release tags (`v1.2.0-rc.1`) are skipped.

## The `HOMEBREW_TAP_TOKEN` secret

The jobs push with a token that can write to this repository:

1. GitHub, Settings, Developer settings, Personal access tokens, **Fine-grained tokens**, Generate
   new token.
2. Resource owner `Topogamer0`; Repository access: **Only select repositories**,
   `Topogamer0/homebrew-tap`; Repository permissions: **Contents: Read and write** (Metadata: Read
   is added automatically). Choose an expiration and note when to renew it.
3. In each of the four project repositories: Settings, Secrets and variables, Actions, New
   repository secret, name `HOMEBREW_TAP_TOKEN`, value the token.

If `main` of the tap is protected so that it only accepts pull requests, the push fails: allow the
token's owner to bypass the rule, or leave `main` unprotected.

## luau-shield

File: `.github/workflows/release.yml`. Add this job at the end, under `jobs:`, after the `release`
job (same indentation as `release:`). It runs once the release is published, so the archives it
hashes are the ones users download. The formula uses the macOS arm64, macOS x86_64 and Linux x86_64
binaries, and the source archive of the tag on Linux arm64.

```yaml
  homebrew:
    name: Update the Homebrew formula
    needs: [prepare, release]
    if: ${{ !contains(needs.prepare.outputs.version, '-') }}
    runs-on: ubuntu-latest
    permissions: {}
    steps:
      - name: Check out the tap
        uses: actions/checkout@v4
        with:
          repository: Topogamer0/homebrew-tap
          token: ${{ secrets.HOMEBREW_TAP_TOKEN }}
          path: homebrew-tap
          fetch-depth: 0

      - name: Update Formula/luau-shield.rb
        working-directory: homebrew-tap
        env:
          VERSION: ${{ needs.prepare.outputs.version }}
        run: python3 scripts/bump-formula.py Formula/luau-shield.rb "$VERSION"

      - name: Commit and push
        working-directory: homebrew-tap
        env:
          FORMULA: luau-shield
          VERSION: ${{ needs.prepare.outputs.version }}
        run: |
          set -euo pipefail
          if git diff --quiet; then
            echo "Formula/$FORMULA.rb is already at $VERSION."
            exit 0
          fi
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git commit --all --message "$FORMULA $VERSION"
          # Another release may have pushed to the tap meanwhile: rebase and retry.
          for attempt in 1 2 3 4 5; do
            if git push origin HEAD:main; then exit 0; fi
            sleep $((attempt * 5))
            git pull --rebase origin main
          done
          echo "::error::Could not push to Topogamer0/homebrew-tap."
          exit 1
```

## failstep

File: `.github/workflows/release.yml`. Add this job at the end, under `jobs:`, after the `build`
job. `needs: build` waits for every platform of the matrix to upload its archive. The formula uses
the macOS arm64 and Linux x86_64 archives, and builds the source archive of the tag on macOS x86_64
and Linux arm64.

```yaml
  homebrew:
    name: Update the Homebrew formula
    needs: build
    if: ${{ !contains(github.ref_name, '-') }}
    runs-on: ubuntu-latest
    permissions: {}
    steps:
      - name: Check out the tap
        uses: actions/checkout@v5
        with:
          repository: Topogamer0/homebrew-tap
          token: ${{ secrets.HOMEBREW_TAP_TOKEN }}
          path: homebrew-tap
          fetch-depth: 0

      - name: Update Formula/failstep.rb
        working-directory: homebrew-tap
        env:
          TAG: ${{ github.ref_name }}
        run: python3 scripts/bump-formula.py Formula/failstep.rb "${TAG#v}"

      - name: Commit and push
        working-directory: homebrew-tap
        env:
          FORMULA: failstep
          TAG: ${{ github.ref_name }}
        run: |
          set -euo pipefail
          VERSION="${TAG#v}"
          if git diff --quiet; then
            echo "Formula/$FORMULA.rb is already at $VERSION."
            exit 0
          fi
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git commit --all --message "$FORMULA $VERSION"
          # Another release may have pushed to the tap meanwhile: rebase and retry.
          for attempt in 1 2 3 4 5; do
            if git push origin HEAD:main; then exit 0; fi
            sleep $((attempt * 5))
            git pull --rebase origin main
          done
          echo "::error::Could not push to Topogamer0/homebrew-tap."
          exit 1
```

If a release adds a macOS x86_64 archive (`failstep-vX.Y.Z-macos-x86_64.tar.gz`), the formula can
use it instead of building from source: that is a manual change to its `on_intel` block in
`on_macos`.

## ollama-c-rag

File: `.github/workflows/release.yml`. Add this job at the end, under `jobs:`, after the `windows`
job. The formula builds the source archive of the tag; waiting for `windows` means the formula is
only updated when the tag passed its version check and the release was created. The `if` skips
manual runs of the workflow (`workflow_dispatch`) and pre-releases.

```yaml
  homebrew:
    name: Update the Homebrew formula
    needs: windows
    if: ${{ github.ref_type == 'tag' && !contains(github.ref_name, '-') }}
    runs-on: ubuntu-latest
    permissions: {}
    steps:
      - name: Check out the tap
        uses: actions/checkout@v4
        with:
          repository: Topogamer0/homebrew-tap
          token: ${{ secrets.HOMEBREW_TAP_TOKEN }}
          path: homebrew-tap
          fetch-depth: 0

      - name: Update Formula/ollama-c-rag.rb
        working-directory: homebrew-tap
        env:
          TAG: ${{ github.ref_name }}
        run: python3 scripts/bump-formula.py Formula/ollama-c-rag.rb "${TAG#v}"

      - name: Commit and push
        working-directory: homebrew-tap
        env:
          FORMULA: ollama-c-rag
          TAG: ${{ github.ref_name }}
        run: |
          set -euo pipefail
          VERSION="${TAG#v}"
          if git diff --quiet; then
            echo "Formula/$FORMULA.rb is already at $VERSION."
            exit 0
          fi
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git commit --all --message "$FORMULA $VERSION"
          # Another release may have pushed to the tap meanwhile: rebase and retry.
          for attempt in 1 2 3 4 5; do
            if git push origin HEAD:main; then exit 0; fi
            sleep $((attempt * 5))
            git pull --rebase origin main
          done
          echo "::error::Could not push to Topogamer0/homebrew-tap."
          exit 1
```

The formula depends on `ollama-c` and passes `-DRAG_USE_SYSTEM_OLLAMA_C=ON`. If a release of
ollama-c-rag needs a newer Ollama-C (its `find_package(ollama-c X.Y)`), release Ollama-C first so
that the `ollama-c` formula is already at that version.

## Ollama-C

Ollama-C has no release workflow yet: create `.github/workflows/release.yml` with the content
below. On a tag `v*`, it checks that the tag matches `VERSION` in `project()` of `CMakeLists.txt`,
then updates the `ollama-c` formula, which builds the source archive of the tag. Creating the
GitHub release stays as it is now (by hand); the workflow only needs the tag.

```yaml
name: Release

# A tag vX.Y.Z updates the ollama-c formula of the Homebrew tap
# (https://github.com/Topogamer0/homebrew-tap) to the source archive of the tag.
on:
  push:
    tags: ['v*']

permissions:
  contents: read

jobs:
  homebrew:
    name: Update the Homebrew formula
    if: ${{ !contains(github.ref_name, '-') }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - name: Compare the tag with the project version
        env:
          TAG: ${{ github.ref_name }}
        run: |
          set -euo pipefail
          # project(ollama-c
          #     VERSION 0.2.0
          version="$(sed -n 's/^[[:space:]]*VERSION[[:space:]]\{1,\}\([0-9][0-9.]*\).*/\1/p' CMakeLists.txt | head -n 1)"
          if [ "v$version" != "$TAG" ]; then
            echo "::error::Tag $TAG does not match the version in CMakeLists.txt (${version:-not found})."
            exit 1
          fi

      - name: Check out the tap
        uses: actions/checkout@v5
        with:
          repository: Topogamer0/homebrew-tap
          token: ${{ secrets.HOMEBREW_TAP_TOKEN }}
          path: homebrew-tap
          fetch-depth: 0

      - name: Update Formula/ollama-c.rb
        working-directory: homebrew-tap
        env:
          TAG: ${{ github.ref_name }}
        run: python3 scripts/bump-formula.py Formula/ollama-c.rb "${TAG#v}"

      - name: Commit and push
        working-directory: homebrew-tap
        env:
          FORMULA: ollama-c
          TAG: ${{ github.ref_name }}
        run: |
          set -euo pipefail
          VERSION="${TAG#v}"
          if git diff --quiet; then
            echo "Formula/$FORMULA.rb is already at $VERSION."
            exit 0
          fi
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git commit --all --message "$FORMULA $VERSION"
          # Another release may have pushed to the tap meanwhile: rebase and retry.
          for attempt in 1 2 3 4 5; do
            if git push origin HEAD:main; then exit 0; fi
            sleep $((attempt * 5))
            git pull --rebase origin main
          done
          echo "::error::Could not push to Topogamer0/homebrew-tap."
          exit 1
```

The checkout of Ollama-C itself is only there for the version check; the formula is updated from
the tap checkout in `homebrew-tap/`.
