# Overlay

Overlay is a fast, native macOS image editor for the moment between taking a
screenshot and sharing it. Copy an image, press **Command-Shift-2**, annotate it
in a focused floating overlay, then copy or save the result. No document setup,
no heavyweight editor, and no detour through a browser.

## Why Overlay

- **Clipboard-first:** the global shortcut opens the current clipboard image
  immediately.
- **Complete annotation toolkit:** select, pencil, pen, highlighter, arrow,
  line, rectangle, ellipse, text, blur, and pixelate.
- **Quick image edits:** crop, rotate, and flip without leaving the overlay.
- **Fast iteration:** undo and redo freely, then copy the finished image or
  save it to disk.
- **Native and private:** built with SwiftUI and AppKit, runs locally, and has
  no accounts, analytics, or telemetry.
- **Mac-first details:** menu-bar operation, a floating all-Spaces editor,
  trackpad zoom, drag-and-drop import, keyboard tool switching, and a native
  app icon generated as part of packaging.

## Requirements

- macOS 14 Sonoma or newer
- Swift 5.9 or newer and Xcode Command Line Tools when building from source

## Getting started

1. Copy a screenshot or image to the macOS clipboard.
2. Launch Overlay.
3. Press **Command-Shift-2** from anywhere.
4. Choose a tool, adjust its color and stroke, and edit the image.
5. Copy the result back to the clipboard or save it as a file.

Overlay is a menu-bar-style utility (`LSUIElement`) and stays out of the Dock
while it waits for the shortcut.

## Build from source

```bash
git clone https://github.com/alexandrenf/photo-overlay.git
cd photo-overlay
make run
```

To build a standalone, ad-hoc-signed app bundle:

```bash
make app
open dist/Overlay.app
```

Create the same zip used by CI and GitHub Releases with `make zip`. Development
builds are ad-hoc signed rather than Apple-notarized, so macOS may ask you to
confirm opening the app the first time.

Other useful commands:

```bash
make build
make test
make clean
```

## Keyboard workflow

| Action | Shortcut |
| --- | --- |
| Open clipboard image | Command-Shift-2 |
| Undo | Command-Z |
| Redo | Command-Shift-Z |
| Copy result | Command-C |
| Save | Command-S |
| Close overlay | Escape |

## Privacy

Images never leave your Mac. Overlay has no telemetry, analytics, advertising,
or network-backed editing features.

## Contributing

Bug reports and focused pull requests are welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow.

## License

Overlay is available under the [MIT License](LICENSE).
