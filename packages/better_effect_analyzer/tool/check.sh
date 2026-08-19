#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
