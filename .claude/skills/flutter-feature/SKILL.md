---
name: flutter-feature
description: Implement Flutter application functionality, state management, repositories, services, APIs, models, validation, synchronization, and tests
---

Implement the functionality described in $ARGUMENTS.

Before editing:

1. Read CLAUDE.md and pubspec.yaml.
2. Inspect related models, repositories, services, and state-management code.
3. Follow the project's current architecture.
4. Present a concise implementation plan.
5. Identify privacy and security risks.

Implementation rules:

- Keep business logic outside widgets.
- Separate data, domain, and presentation responsibilities.
- Reuse the existing state-management system.
- Validate all external input.
- Handle offline, timeout, authentication, and server errors.
- Never log clipboard contents, passwords, tokens, or private data.
- Never hardcode secrets.
- Do not add dependencies unless necessary.
- Add unit or widget tests for important behavior.
- Avoid changing unrelated files.

After editing:

- Run `dart format .`
- Run `flutter analyze`
- Run relevant tests.
- Summarize changes, commands run, failures, and risks.
