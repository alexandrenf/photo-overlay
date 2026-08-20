# Contributing to Overlay

Thanks for helping make clipboard image editing faster on macOS.

## Development setup

You need macOS 14 or newer, Swift 5.9 or newer, and the Xcode Command Line
Tools. Fork and clone the repository, then verify your checkout:

```bash
make build
make test
make run
```

## Making a change

1. Create a focused branch from `main`.
2. Keep UI work native to SwiftUI/AppKit and preserve the clipboard-first,
   keyboard-friendly workflow.
3. Add or update XCTest coverage for behavior that can be tested reliably.
4. Run `make build`, `make test`, and `make app` before opening a pull request.
5. Explain the user-facing effect and include screenshots for visual changes.

Please keep pull requests small enough to review, avoid unrelated formatting
changes, and do not add telemetry, analytics, or a network dependency without
prior discussion.

## Code style

- Follow Swift API Design Guidelines and existing formatting.
- Prefer clear, small types and explicit names over clever abstractions.
- Keep AppKit bridges isolated from editor state where practical.
- Make keyboard and VoiceOver behavior part of UI changes, not an afterthought.

## Reporting bugs

Include your macOS version, exact reproduction steps, expected and actual
behavior, and—when safe—a screenshot or short screen recording. Never attach a
sensitive clipboard image to a public issue.

By contributing, you agree that your contributions are licensed under the
project's MIT License.
