# minizinc-vendor

Reproducible builds of the third-party solvers and dependencies that ship with
MiniZinc (CBC, HiGHS, OR-Tools CP-SAT, Gecode, Gecode+Gist, Chuffed), for every
supported platform.

Unlike the previous GitLab setup — where solver versions floated and downstream
projects consumed "latest" — every version here is **explicitly pinned** in a
single manifest, each build is **published individually** as a release asset, and
upstream updates arrive as **Dependabot-style pull requests**.

## Model

Each `(dependency, platform)` build is published as one asset on a **per-dependency
GitHub Release** tagged `<dep>-<version>`:

```
Release  gecode-eebbc1bfaef1decd3ab6a3c583c7b55f5fe29600
  asset    gecode-eebbc1b…-x86_64-linux-gnu.tar.gz
  asset    gecode-eebbc1b…-aarch64-linux-gnu.tar.gz
  asset    gecode-eebbc1b…-aarch64-apple-darwin.tar.gz
  ...
```

There is **no compose/bundle step and no separate artifact registry**: the release
*is* the artifact, and "already built?" is simply "does that asset exist?". So
bumping one dependency rebuilds only that dependency (its new-version assets are
missing); every other dependency's assets already exist and are skipped. Old
versions stay published, so any pinned build can be re-downloaded without rebuilding.

Consumers (e.g. libminizinc) keep a per-dependency lock file and download each
dependency's asset for their system triple individually.

## Layout

- **`dependencies.toml`** — the single source of truth: pins every solver
  version/commit and every toolchain version (coinbrew, Bazel, bazelisk, rules_pkg,
  OpenSSL), plus each platform's runner, (digest-pinnable) container, and system triple.
- **`recipes/*.sh`** — build one dependency each; versions come from the environment
  (injected from the manifest), never hard-coded.
- **`scripts/manifest.py`** — expands the `(dependency × platform)` matrix, computes
  each cell's release tag / asset name / recipe env, and emits the resolved lockfile.
- **`scripts/update_check.py`** — the update bot: resolves the newest upstream version
  of each tracked entry and rewrites a single pin.

### Workflows

| Workflow | Trigger | Does |
|---|---|---|
| `build.yml` | reusable / dispatch | matrix build; build + (optionally) publish each missing asset |
| `publish.yml` | push to `main` / dispatch | build & publish all missing assets, then open per-dep bump PRs in libminizinc |
| `update-bot.yml` | weekly / dispatch | one PR per outdated dependency (bumps this manifest) |
| `pr-validate.yml` | PR touching manifest/recipes/resources | build only the changed dependencies (no publish) |

### System triples

`x86_64-linux-gnu`, `aarch64-linux-gnu`, `x86_64-linux-musl`, `aarch64-linux-musl`,
`aarch64-apple-darwin`, `x86_64-windows`, `wasm32-emscripten`.

## One-time setup (TODOs before the first publish)

1. **Pin container images by digest.** Replace the `# TODO: pin @sha256:...` tags in
   `dependencies.toml` (`[platforms.*].container`, `gecode_gist.container_override`).
2. **Fill bazelisk `sha256`** for each asset in `[toolchain.bazelisk.sha256]`.
3. **GitHub App for bump PRs.** Register one GitHub App in the org (Contents +
   Pull requests: read/write), installed on `minizinc-vendor` and `libminizinc`, and
   store its App ID / private key as org secrets **`MINIZINC_BOT_APP_ID`** and
   **`MINIZINC_BOT_APP_KEY`**. `update-bot.yml` and `publish.yml` mint short-lived
   tokens from it so their bump PRs trigger CI (`GITHUB_TOKEN`-created PRs don't, and
   it can't write cross-repo). Publishing this repo's own releases uses the built-in
   `GITHUB_TOKEN`.
4. **Self-hosted runners (optional).** Everything starts on GitHub-hosted runners.
   If `or-tools:win64` (Bazel + MSVC) exhausts the hosted disk/time, point that
   platform's `runner` in the manifest at a self-hosted label — no workflow edit needed.

## Local use

```sh
pip install tomli           # only needed on Python < 3.11
python3 scripts/manifest.py versions           # dep -> pinned version
python3 scripts/manifest.py release-tag --dep gecode
python3 scripts/manifest.py asset --dep cbc --platform win64
python3 scripts/manifest.py matrix | python3 -m json.tool
python3 scripts/update_check.py check          # what's outdated upstream
python3 scripts/manifest.py lock               # resolved lockfile
```
