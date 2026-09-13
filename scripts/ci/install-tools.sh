#!/usr/bin/env bash
set -euo pipefail

# Release asset SHA-256 digests from the upstream GitHub release metadata.
# Update these together with the versions in Makefile.
mkdir -p .tools/ci/bin
export PATH="$PWD/.tools/ci/bin:$PATH"
if [[ -x .tools/ci/bin/swiftlint && -x .tools/ci/bin/swiftformat ]] && make tools; then
  exit 0
fi

download_dir=$(mktemp -d)
trap 'rm -rf "$download_dir"' EXIT
curl --fail --location --retry 3 \
  https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip \
  -o "$download_dir/swiftlint.zip"
curl --fail --location --retry 3 \
  https://github.com/nicklockwood/SwiftFormat/releases/download/0.62.1/swiftformat.zip \
  -o "$download_dir/swiftformat.zip"
(
  cd "$download_dir"
  shasum -a 256 --check <<'CHECKSUMS'
c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0  swiftlint.zip
7cb1cb1fae04932047c7015441c543848e8e60e1572d808d080e0a1f1661114a  swiftformat.zip
CHECKSUMS
  unzip -q swiftlint.zip -d swiftlint
  unzip -q swiftformat.zip -d swiftformat
)
install -m 755 "$download_dir/swiftlint/swiftlint" .tools/ci/bin/swiftlint
install -m 755 "$download_dir/swiftformat/swiftformat" .tools/ci/bin/swiftformat
make tools
