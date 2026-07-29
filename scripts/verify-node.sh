#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"
swift package dump-package >/dev/null
swift test
swift run saturn-node
echo "Bootstrap verification completed. No live node was contacted."
