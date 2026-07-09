#!/usr/bin/env python3
"""Drop build-matrix cells whose asset is already published.

Reads the matrix (JSON list of cells) on stdin and writes the pruned matrix on
stdout, so the build only spawns jobs that still need to run. Each per-dependency
release's asset list is fetched once via `gh` (needs GITHUB_REPOSITORY + a token).
"""
import json
import os
import subprocess
import sys


def existing_assets(repo: str, tag: str) -> set[str]:
    try:
        out = subprocess.run(
            ["gh", "release", "view", tag, "--repo", repo,
             "--json", "assets", "--jq", ".assets[].name"],
            capture_output=True, text=True, check=True,
        ).stdout
        return set(out.split())
    except (subprocess.CalledProcessError, FileNotFoundError):
        return set()  # release absent (or no gh) => treat as nothing published


def main() -> int:
    cells = json.load(sys.stdin)
    repo = os.environ["GITHUB_REPOSITORY"]
    seen: dict[str, set[str]] = {}
    kept = []
    for c in cells:
        tag = c["release_tag"]
        if tag not in seen:
            seen[tag] = existing_assets(repo, tag)
        if c["asset_name"] not in seen[tag]:
            kept.append(c)
    json.dump(kept, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
