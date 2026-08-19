#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

dart pub get
dart format .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
