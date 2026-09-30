# opencode-nix

A Nix flake packaging [OpenCode](https://github.com/anomalyco/opencode) from upstream
GitHub release binaries, with daily version updates. Supports `x86_64-linux`,
`aarch64-linux`, `aarch64-darwin`, and `x86_64-darwin`.

```sh
nix run github:juspay/opencode-nix
```

Use it as a flake input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    opencode.url = "github:juspay/opencode-nix";
    opencode.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, opencode, ... }: {
    devShells.x86_64-linux.default =
      let pkgs = nixpkgs.legacyPackages.x86_64-linux;
      in pkgs.mkShell {
        packages = [ opencode.packages.x86_64-linux.default ];
      };
  };
}
```

Replace `x86_64-linux` with your system. Both `packages.<system>.default` and
`packages.<system>.opencode` expose `version` and `meta.mainProgram = "opencode"`.
The corresponding `apps` outputs launch OpenCode. Alternatively, import nixpkgs
with `overlays = [ opencode.overlays.default ];` and use `pkgs.opencode`.

The lock file pins a 2026-06-19 revision of `nixpkgs-unstable` that still supports
Intel macOS. Newer unstable revisions have removed `x86_64-darwin`; retain a
compatible nixpkgs revision when updating this lock or using `follows` on Intel
macOS. The daily updater changes only the OpenCode pin in `sources.json`.

The wrapper supplies ripgrep on `PATH` to avoid its runtime download, adds
`sysctl` on macOS, and disables OpenCode self-updates with
`OPENCODE_DISABLE_AUTOUPDATE=true`. Update the flake input to upgrade OpenCode.

Linux uses the upstream musl assets. These are dynamically linked in 1.18.33, so
the wrapper invokes Nix's musl loader with its C++ runtime libraries. The upstream
Bun executable is preserved without stripping or patching its ELF interpreter.

## Updates and verification

`sources.json` holds the release version and SRI hashes for all four platforms.
With Nix, GitHub CLI (`gh`), and `jq` installed, run:

```sh
bash scripts/update.sh
nix build .#default -L
./result/bin/opencode --version
nix flake check --all-systems
```

The updater resolves the latest stable GitHub release and only moves forward.
It downloads every asset before replacing `sources.json`, so a failed download
leaves the existing pin intact. When `GITHUB_OUTPUT` is set, it writes `before`
and `after` version outputs, including on a no-op.

The update workflow runs daily at **10:00 UTC** (one hour before agent-distro's
updater) or manually through Actions. It opens or updates a PR from `update`,
links the release notes, and enables squash auto-merge after required CI passes.
CI builds and checks the exact version on Ubuntu and macOS. Because PRs created
with `GITHUB_TOKEN` do not trigger `pull_request` workflows, the updater explicitly
dispatches CI on the update branch; no additional token secret is required.

## Repository settings

An organization/repository administrator must enable:

- **Actions → General → Workflow permissions → Allow GitHub Actions to create
  and approve pull requests** (the organization policy must permit it).
- **General → Pull Requests → Allow auto-merge**, and allow squash merging.
- A branch protection rule or ruleset for **`main`** requiring both CI checks:
  **`Build (ubuntu-latest)`** and **`Build (macos-latest)`**, so auto-merge waits
  for both builds and version checks. Run CI once to populate the check picker.

The updater requests `contents: write` and `pull-requests: write` to maintain its
PR, plus `actions: write` to dispatch CI. The CI workflow only needs
`contents: read`.

Layout inspired by [codex-cli-nix](https://github.com/sadjow/codex-cli-nix) and
[claude-code-nix](https://github.com/sadjow/claude-code-nix).
