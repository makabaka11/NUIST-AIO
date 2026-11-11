"""Validate the tag, version code, and checked-in release notes before building."""
import os
import re
from pathlib import Path


def metadata(tag, pubspec, notes):
    if not re.fullmatch(r"v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", tag):
        raise ValueError("Release tag must be a stable vMAJOR.MINOR.PATCH version")
    version = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$", pubspec, re.M)
    if not version or version[1] != tag[1:]:
        raise ValueError("Tag must match pubspec.yaml version; include a positive build number")
    if int(version[2]) > 2100000000:
        raise ValueError("Build number exceeds Android versionCode limit")
    if not re.match(rf"\A#\s+{re.escape(tag)}\s*\n", notes) or not notes.strip().splitlines()[1:]:
        raise ValueError("RELEASE_NOTE.md must start with '# <tag>' and contain release notes")
    return {"version": version[1], "build": version[2], "tag": tag}


if __name__ == "__main__":
    values = metadata(os.environ["RELEASE_TAG"], Path("pubspec.yaml").read_text(), Path("RELEASE_NOTE.md").read_text())
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for name, value in values.items():
            output.write(f"{name}={value}\n")
