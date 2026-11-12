"""Derive release versions from the triggering tag and validate release notes.

vMAJOR.MINOR.PATCH maps to MAJOR * 10000 + MINOR * 100 + PATCH.
Minor/patch occupy two digits each. The shared build number must fit the
Windows version resource's 16-bit revision as well as mobile version codes.
pubspec.yaml remains a local-development default and is not read by this tool.
"""
import os
import re
from pathlib import Path


def metadata(tag, notes):
    match = re.fullmatch(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", tag)
    if not match:
        raise ValueError("Release tag must be a stable vMAJOR.MINOR.PATCH version")
    major, minor, patch = map(int, match.groups())
    if minor > 99 or patch > 99:
        raise ValueError("Tag minor and patch versions must be between 0 and 99")
    build = major * 10000 + minor * 100 + patch
    if not 1 <= build <= 65535:
        raise ValueError("Tag-derived build number must fit the shared platform range 1..65535")
    if not re.match(rf"\A#\s+{re.escape(tag)}\s*\n", notes) or not notes.strip().splitlines()[1:]:
        raise ValueError("RELEASE_NOTE.md must start with '# <tag>' and contain release notes")
    return {"version": tag[1:], "build": str(build), "tag": tag}


if __name__ == "__main__":
    values = metadata(os.environ["RELEASE_TAG"], Path("RELEASE_NOTE.md").read_text(encoding="utf-8"))
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for name, value in values.items():
            output.write(f"{name}={value}\n")
