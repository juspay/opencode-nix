# opencode-nix

OpenCode releases several times a day while nixpkgs can lag weeks; this flake follows tagged releases within a day using upstream’s own binaries.

```sh
nix run github:juspay/opencode-nix
```

Add it to your flake:

```nix
inputs.opencode = {
  url = "github:juspay/opencode-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
# Use opencode.packages.${system}.default in your package list.
```

Supports `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`.

## How it stays current

At **10:00 UTC** daily, the updater refreshes the latest tagged release and nixpkgs.
Changes open a PR with release hashes and the updated lockfile.
Auto-merge lands it after the Ubuntu and macOS build/version checks pass.

## Repository settings

- Allow GitHub Actions to create and approve pull requests.
- Enable auto-merge and squash merging.
- Protect `main` with required checks **`Build (ubuntu-latest)`** and **`Build (macos-latest)`**.
