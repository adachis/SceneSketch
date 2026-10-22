#!/usr/bin/env python3
"""Validate version metadata before promoting development work to a release."""
import argparse
import os
import re
import subprocess
import sys


def metadata(revision):
    source = subprocess.check_output(["git", "show", f"{revision}:project.yml"], text=True)
    version = re.search(r"CFBundleShortVersionString:\s*['\"]([0-9]+\.[0-9]+\.[0-9]+)['\"]", source)
    build = re.search(r"CFBundleVersion:\s*['\"]([0-9]+)['\"]", source)
    if not version or not build:
        raise ValueError("Set a three-part release version and numeric build in project.yml.")
    return tuple(map(int, version[1].split("."))), int(build[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--candidate", default="HEAD")
    parser.add_argument("--head", default=os.environ.get("GITHUB_HEAD_REF") or os.environ.get("GITHUB_REF_NAME", "dev"))
    args = parser.parse_args()
    if args.head != "dev" and not args.head.startswith("release/"):
        raise ValueError("Release pull requests must come from dev or a release/ branch.")
    previous, previous_build = metadata(args.base)
    current, current_build = metadata(args.candidate)
    if current <= previous or current_build <= previous_build:
        raise ValueError("Increase both the release version and build before merging into main.")
    print("Release policy passed: version and build increase from the released baseline.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f"Release policy: {error}", file=sys.stderr)
        sys.exit(1)
