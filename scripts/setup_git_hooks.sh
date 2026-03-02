#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"
git config core.hooksPath .githooks

echo "Configured git hooks path: .githooks"
