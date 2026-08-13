#!/usr/bin/env bash
set -euo pipefail

flutter pub get
dart format .
flutter analyze --fatal-infos
flutter test
flutter pub publish --dry-run --ignore-warnings

(
  cd example
  flutter pub get
  flutter analyze --fatal-infos
  flutter test
)
