---
name: flutter-check
description: Run Flutter formatting, static analysis, tests, and builds to validate the project
disable-model-invocation: true
---

Validate the current Flutter project.

Run:

1. `dart format --set-exit-if-changed .`
2. `flutter analyze`
3. `flutter test`

When relevant, also run:

- Android: `flutter build apk --debug`
- Web: `flutter build web`

Do not ignore warnings or failures.

For every failure:

- Explain the probable cause.
- Show the affected file.
- Recommend the smallest safe fix.

Finish with:

- Formatting result
- Analysis result
- Test result
- Build result
- Overall PASS or FAIL
