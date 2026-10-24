#!/usr/bin/env python3
"""Move a formula of this tap to a new version.

Usage: bump-formula.py <Formula/name.rb> <version>

Every `url` of the formula (release binaries and source archives, in any
on_macos/on_linux/on_arm/on_intel block) is rewritten from the current
version to <version>, each file is downloaded, and the `sha256` that follows
the `url` is set to the checksum of that file. A `version` line, if the
formula has one, is updated too.

At the version the formula already has, the files are downloaded again and
the checksums that changed are rewritten, so re-running a release that
rebuilt its assets, or moving a tag, keeps the formula installable. A version
older than the formula's is refused (nothing is written, exit status 0), so a
re-run of an old release cannot move the formula back. The file is written
only when something changed, and only after every download succeeded.

Used by the release workflows of the projects (see docs/release-integration.md).
Only the Python standard library is needed.
"""

import hashlib
import http.client
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
            with urllib.request.urlopen(request, timeout=120) as response:
                # read() of the whole body raises IncompleteRead when the connection
                # drops early; reading it in blocks would hash a truncated file.
                return hashlib.sha256(response.read()).hexdigest()
        # URLError and HTTPError are OSErrors; IncompleteRead is an HTTPException.
        except (OSError, http.client.HTTPException) as e:
            if attempt == attempts:
                sys.exit(f"error: cannot download {url}: {e}")
            print(f"  {url}: {e}, retrying", file=sys.stderr)
            time.sleep(10 * attempt)


def version_key(version):
    return tuple(int(part) for part in version.split("."))


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2])
    path, new = sys.argv[1], sys.argv[2].removeprefix("v")
    release_version = re.compile(r"\d+(\.\d+)+")
    if not release_version.fullmatch(new):
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
    if release_version.fullmatch(old) and version_key(new) < version_key(old):
        print(f"{path} is at {old}, newer than {new}: left unchanged")
        return

    original = list(lines)
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

    if lines == original:
        print(f"{path} is already at {new}, with the same checksums")
        return
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"{path}: {old} -> {new}" if old != new else f"{path}: checksums of {new} updated")


if __name__ == "__main__":
    main()
