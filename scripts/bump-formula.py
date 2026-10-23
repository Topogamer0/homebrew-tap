#!/usr/bin/env python3
"""Move a formula of this tap to a new version.

Usage: bump-formula.py <Formula/name.rb> <version>

Every `url` of the formula (release binaries and source archives, in any
on_macos/on_linux/on_arm/on_intel block) is rewritten from the current
version to <version>, each file is downloaded, and the `sha256` that follows
the `url` is replaced with the checksum of the new file. A `version` line, if
the formula has one, is updated too. Nothing changes when the formula is
already at <version>.

Used by the release workflows of the projects (see docs/release-integration.md).
Only the Python standard library is needed.
"""

import hashlib
import re
import sys
import time
import urllib.request

URL_LINE = re.compile(r'^(\s*)url "([^"]+)"')
SHA256_LINE = re.compile(r'^(\s*)sha256 "[0-9a-f]{64}"')
VERSION_LINE = re.compile(r'^(\s*)version "([^"]+)"')
# The version is the tag of a release download or of a source archive:
#   .../releases/download/v1.2.3/...    .../archive/refs/tags/v1.2.3.tar.gz
URL_VERSION = re.compile(r'/releases/download/v([^/]+)/|/archive/refs/tags/v(.+)\.tar\.gz$')


def url_version(url):
    match = URL_VERSION.search(url)
    if not match:
        sys.exit(f"error: cannot find the version in {url}")
    return match.group(1) or match.group(2)


def sha256_of(url, attempts=5):
    """Downloads url and returns its SHA-256; retries while a new release asset is not served yet."""
    for attempt in range(1, attempts + 1):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "homebrew-tap-bump"})
            digest = hashlib.sha256()
            with urllib.request.urlopen(request, timeout=120) as response:
                for block in iter(lambda: response.read(1 << 16), b""):
                    digest.update(block)
            return digest.hexdigest()
        except OSError as e:  # URLError and HTTPError are OSErrors
            if attempt == attempts:
                sys.exit(f"error: cannot download {url}: {e}")
            print(f"  {url}: {e}, retrying", file=sys.stderr)
            time.sleep(10 * attempt)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2])
    path, new = sys.argv[1], sys.argv[2].removeprefix("v")
    if not re.fullmatch(r"\d+(\.\d+)+", new):
        sys.exit(f"error: '{new}' is not a release version such as 1.2.3")

    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines(keepends=True)

    urls = [m.group(2) for m in map(URL_LINE.match, lines) if m]
    if not urls:
        sys.exit(f"error: no url in {path}")
    versions = {url_version(url) for url in urls}
    if len(versions) != 1:
        sys.exit(f"error: the urls of {path} name several versions: {', '.join(sorted(versions))}")
    old = versions.pop()
    if old == new:
        print(f"{path} is already at {new}")
        return

    checksums = {}
    pending_sha = None  # the new url whose sha256 line comes next
    for i, line in enumerate(lines):
        if m := URL_LINE.match(line):
            url = m.group(2).replace(old, new)
            if url not in checksums:
                checksums[url] = sha256_of(url)
                print(f"{checksums[url]}  {url}")
            lines[i] = f'{m.group(1)}url "{url}"\n'
            pending_sha = url
        elif (m := SHA256_LINE.match(line)) and pending_sha:
            lines[i] = f'{m.group(1)}sha256 "{checksums[pending_sha]}"\n'
            pending_sha = None
        elif (m := VERSION_LINE.match(line)) and m.group(2) == old:
            lines[i] = f'{m.group(1)}version "{new}"\n'
    if pending_sha:
        sys.exit(f"error: no sha256 after the url {pending_sha}")

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"{path}: {old} -> {new}")


if __name__ == "__main__":
    main()
