#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

before=$(jq -er '.version' sources.json)
tag=$(gh release view --repo anomalyco/opencode --json tagName --jq .tagName)
after=${tag#v}

# Compare numeric components, without depending on GNU sort on macOS.
version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if [[ "$tag" != v* || ! "$before" =~ $version_pattern || ! "$after" =~ $version_pattern ]]; then
  echo "Expected stable vMAJOR.MINOR.PATCH release; got $tag (current: $before)" >&2
  exit 1
fi

if ! jq -en --arg before "$before" --arg after "$after" \
  '($after | split(".") | map(tonumber)) > ($before | split(".") | map(tonumber))' >/dev/null; then
  echo "Keeping OpenCode $before (latest release: $after)."
  after=$before
else
  systems=(x86_64-linux aarch64-linux aarch64-darwin x86_64-darwin)
  assets=(opencode-linux-x64-musl.tar.gz opencode-linux-arm64-musl.tar.gz opencode-darwin-arm64.zip opencode-darwin-x64.zip)
  hashes='{}'
  for i in "${!systems[@]}"; do
    echo "Prefetching ${assets[$i]} for OpenCode $after..."
    hash=$(nix store prefetch-file --json \
      "https://github.com/anomalyco/opencode/releases/download/$tag/${assets[$i]}" \
      | jq -er '.hash | select(test("^sha256-[A-Za-z0-9+/]{43}=$"))')
    hashes=$(jq --arg system "${systems[$i]}" --arg hash "$hash" \
      '. + {($system): $hash}' <<< "$hashes")
  done

  # Publish the new version only after all four downloads have succeeded.
  temporary=$(mktemp ./sources.json.XXXXXX)
  trap 'rm -f "$temporary"' EXIT
  jq -n --arg version "$after" --argjson hashes "$hashes" \
    '{version: $version, hashes: $hashes}' > "$temporary"
  chmod 644 "$temporary"
  mv "$temporary" sources.json
  echo "Updated OpenCode $before → $after."
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'before=%s\nafter=%s\n' "$before" "$after" >> "$GITHUB_OUTPUT"
fi
