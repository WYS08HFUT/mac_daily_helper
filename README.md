# Daily Help

A small native macOS app for the `Mac 文件命令` cheat sheet.

The window and menus are AppKit; the content is the existing HTML/CSS/JS page loaded in a `WKWebView`. The app is a real `.app` bundle with a Dock icon, native titlebar, menu bar, clipboard bridge, and window frame autosave.

## Requirements

- macOS 13 or later
- Command Line Tools (`xcode-select --install`)
- No full Xcode installation and no Xcode project are required.
- ImageMagick is only needed if you want to regenerate the app icon.

## Build

```bash
# from the repository root (the daily_help folder)
./build.sh
```

Output:

```text
build/DailyHelp.app
```

Double-click it in Finder, or run:

```bash
open build/DailyHelp.app
```

## Test

```bash
./test.sh
```

This builds the app, checks the bundle and ad-hoc signature, then runs a hidden-window smoke test. The smoke test verifies that the page loads, 26 command rows exist, `localStorage` works, and the native copy bridge writes the command to a dedicated test pasteboard (it does not touch your normal clipboard).

## Release

Git itself has tags, not releases. GitHub Releases attach a downloadable file (for example, a zipped `.app`) to a tag.

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Run `./test.sh`.
3. Build and zip the app:

   ```bash
   ./build.sh
   (cd build && zip -r -X ../DailyHelp-v1.0.0.zip DailyHelp.app)
   ```

4. Commit, tag, and push:

   ```bash
   git add .
   git commit -m "Release v1.0.0"
   git tag -a v1.0.0 -m "Daily Help v1.0.0"
   git push origin main
   git push origin v1.0.0
   ```

5. Publish the GitHub release:

   ```bash
   gh release create v1.0.0 DailyHelp-v1.0.0.zip \
     --title "Daily Help v1.0.0" \
     --notes "Native macOS app for the Mac file-command cheat sheet."
   ```

   Or use the web UI: **Releases → Draft a new release → choose the tag → attach `DailyHelp-v1.0.0.zip` → Publish release**.

`build/` is ignored by git. Keep compiled `.app` bundles in Releases rather than committing them. Users can also build from source with `./build.sh`.

## Edit and rebuild

- Page content: edit `web/index.html`, then run `./build.sh`.
- Native window/menu/bridge: edit `Sources/main.swift`, then run `./build.sh`.
- App metadata: edit `Resources/Info.plist`, then run `./build.sh`.
- Icon: edit/replace `Resources/icon-1024.png`, run `Resources/make-icon.sh`, then `./build.sh`.

The app loads the HTML bundled at build time. It does not read the source folder at launch, and it does not rebuild when opened.

You can also build from another HTML source:

```bash
HTML_SOURCE=/Users/wang/Documents/mac_daily_use.html ./build.sh
```

## Structure

```text
Sources/main.swift        AppKit window, WKWebView, menus, bridges
web/index.html            Page source bundled into the app
Resources/Info.plist      Bundle metadata
Resources/icon-1024.png   Icon source
Resources/make-icon.sh    Generates AppIcon.icns with ImageMagick
Resources/AppIcon.icns    Generated icon
build.sh                  Compile and assemble DailyHelp.app
test.sh                   Build + bundle checks + headless smoke test
build/DailyHelp.app       Build output (double-click this)
```

## Notes

- The bundle identifier is `local.dailyhelp.app`.
- The app is ad-hoc signed for local use. It is not notarized; copying it to another Mac may trigger a Gatekeeper warning.
- The page is loaded from an `https://dailyhelp.local/` base URL so WebKit provides a secure origin for `localStorage` and clipboard behavior. No network request is made.
- The native copy bridge writes to the system pasteboard in normal mode, and to `DailyHelpSmokeTest` during `--smoke-test`.
