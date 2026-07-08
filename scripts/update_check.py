#!/usr/bin/env python3
"""The upstream-update bot: a generalization of the old check-*-version.sh scripts.

For every dependency and toolchain entry that declares a `track`, resolve the
latest available upstream version and compare it to what the manifest pins.

Subcommands
-----------
check  [--json]        Print the list of outdated items as JSON (default) or text.
apply  --name N --to V  Rewrite dependencies.toml in place, bumping entry N's pinned
                        `version` (tag-tracked) or `commit` (branch-tracked) to V.

Resolution per `track.kind`:
  git-tags       git ls-remote --tags; newest tag matching `pattern`
  branch-head    git ls-remote <branch>; the current tip commit SHA
  github-release GitHub API; newest release tag matching `pattern`
  bcr-module     Bazel Central Registry; newest module version
  manual         not auto-bumpable (bot opens an advisory issue instead)

Only the network calls below reach out; `apply` is a pure in-place text edit that
touches a single `version =`/`commit =` line within the target section, leaving
inline sub-tables (e.g. cbc's per-platform env) untouched.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(HERE, "dependencies.toml")

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore


# --------------------------------------------------------------------------- #
# Resolution helpers
# --------------------------------------------------------------------------- #
def _version_tuple(s: str) -> tuple[int, ...]:
    return tuple(int(x) for x in s.split("."))


def _ls_remote(repo: str, *refs: str, options: tuple[str, ...] = ()) -> list[str]:
    # git ls-remote [options] <repo> [<refs>...]  — options precede the repo,
    # refspecs follow it.
    out = subprocess.run(
        ["git", "ls-remote", *options, repo, *refs],
        capture_output=True, text=True, check=True,
    ).stdout.strip().splitlines()
    return out


def resolve_git_tags(track: dict) -> str:
    """Newest numeric tag matching `pattern` (capture group 1 = version)."""
    pat = re.compile(track["pattern"])
    best: tuple[int, ...] | None = None
    best_ver: str | None = None
    for line in _ls_remote(track["repo"], options=("--tags", "--refs")):
        ref = line.split("\t", 1)[1]  # refs/tags/<...>
        name = ref[len("refs/tags/"):]
        mobj = pat.search(name)
        if not mobj:
            continue
        ver = mobj.group(1)
        try:
            vt = _version_tuple(ver)
        except ValueError:
            continue
        if best is None or vt > best:
            best, best_ver = vt, ver
    if best_ver is None:
        raise RuntimeError(f"no tag matched {track['pattern']} in {track['repo']}")
    return best_ver


def resolve_branch_head(track: dict) -> str:
    """Current tip commit SHA of the tracked branch."""
    lines = _ls_remote(track["repo"], f"refs/heads/{track['branch']}")
    if not lines:
        raise RuntimeError(f"branch {track['branch']} not found in {track['repo']}")
    return lines[0].split("\t", 1)[0]


def _http_json(url: str) -> dict | list:
    req = urllib.request.Request(url, headers={"Accept": "application/json",
                                               "User-Agent": "minizinc-vendor-bot"})
    token = os.environ.get("GITHUB_TOKEN")
    if token and "api.github.com" in url:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def resolve_github_release(track: dict) -> str:
    pat = re.compile(track["pattern"])
    data = _http_json(f"https://api.github.com/repos/{track['repo']}/releases?per_page=100")
    best: tuple[int, ...] | None = None
    best_ver: str | None = None
    for rel in data:
        if rel.get("draft") or rel.get("prerelease"):
            continue
        mobj = pat.search(rel.get("tag_name", ""))
        if not mobj:
            continue
        try:
            vt = _version_tuple(mobj.group(1))
        except ValueError:
            continue
        if best is None or vt > best:
            best, best_ver = vt, mobj.group(1)
    if best_ver is None:
        raise RuntimeError(f"no release matched {track['pattern']} for {track['repo']}")
    return best_ver


def resolve_bcr_module(track: dict) -> str:
    data = _http_json(f"https://raw.githubusercontent.com/bazelbuild/bazel-central-registry"
                      f"/main/modules/{track['module']}/metadata.json")
    versions = data.get("versions", [])
    return max(versions, key=_version_tuple)


RESOLVERS = {
    "git-tags": resolve_git_tags,
    "branch-head": resolve_branch_head,
    "github-release": resolve_github_release,
    "bcr-module": resolve_bcr_module,
}


# --------------------------------------------------------------------------- #
# Manifest walk
# --------------------------------------------------------------------------- #
def _iter_tracked(m: dict):
    """Yield (name, section, entry, current_value, field) for tracked entries."""
    for section in ("deps", "toolchain"):
        for name, entry in m.get(section, {}).items():
            track = entry.get("track")
            if not track:
                continue
            if "version" in entry:
                yield name, section, entry, entry["version"], "version"
            elif "commit" in entry:
                yield name, section, entry, entry["commit"], "commit"


def check(m: dict) -> list[dict]:
    outdated = []
    for name, section, entry, current, field in _iter_tracked(m):
        track = entry["track"]
        kind = track["kind"]
        item = {"name": name, "section": section, "kind": kind,
                "field": field, "current": current}
        if kind == "manual":
            continue
        resolver = RESOLVERS.get(kind)
        if resolver is None:
            item["error"] = f"unknown track kind {kind}"
            outdated.append(item)
            continue
        try:
            latest_raw = resolver(track)
        except Exception as exc:  # keep going; one flaky upstream shouldn't block the rest
            item["error"] = str(exc)
            outdated.append(item)
            continue
        latest = _format_latest(field, current, latest_raw)
        if latest != current:
            item["latest"] = latest
            outdated.append(item)
    return outdated


def _format_latest(field: str, current: str, latest_raw: str) -> str:
    """Render the resolved value in the same format the manifest currently stores."""
    if field == "commit":
        return latest_raw  # bare SHA
    # tag-tracked: preserve a leading 'v' if the current pin uses one.
    if current.startswith("v") and not latest_raw.startswith("v"):
        return "v" + latest_raw
    if not current.startswith("v") and latest_raw.startswith("v"):
        return latest_raw[1:]
    return latest_raw


# --------------------------------------------------------------------------- #
# In-place apply
# --------------------------------------------------------------------------- #
def apply(name: str, to: str) -> None:
    with open(MANIFEST, "rb") as f:
        m = tomllib.load(f)
    # Find which section and field to edit.
    target_section = target_field = None
    for n, section, entry, _current, field in _iter_tracked(m):
        if n == name:
            target_section, target_field = section, field
            break
    if target_section is None:
        raise SystemExit(f"'{name}' is not a tracked entry")

    header = f"[{target_section}.{name}]"
    with open(MANIFEST, "r") as f:
        lines = f.readlines()

    in_section = False
    field_re = re.compile(rf"^(\s*){target_field}(\s*)=\s*.*$")
    changed = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("["):
            in_section = stripped == header
            continue
        if in_section and field_re.match(line):
            indent = field_re.match(line).group(1)
            lines[i] = f'{indent}{target_field} = "{to}"\n'
            changed = True
            break
    if not changed:
        raise SystemExit(f"could not find `{target_field}` in {header}")
    with open(MANIFEST, "w") as f:
        f.writelines(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("check")
    p.add_argument("--json", action="store_true")
    p = sub.add_parser("apply")
    p.add_argument("--name", required=True)
    p.add_argument("--to", required=True)
    args = ap.parse_args()

    if args.cmd == "check":
        with open(MANIFEST, "rb") as f:
            m = tomllib.load(f)
        out = check(m)
        # Only surface genuinely-actionable bumps (has `latest`, no `error`) in JSON;
        # errors are logged to stderr so the workflow can see them.
        actionable = [o for o in out if "latest" in o]
        for o in out:
            if "error" in o:
                print(f"WARN {o['name']}: {o['error']}", file=sys.stderr)
        if args.json:
            print(json.dumps(actionable))
        else:
            for o in actionable:
                print(f"{o['name']}: {o['current']} -> {o['latest']}")
    elif args.cmd == "apply":
        apply(args.name, args.to)
    return 0


if __name__ == "__main__":
    sys.exit(main())
