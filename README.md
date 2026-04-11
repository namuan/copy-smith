# Copy Smith

A native macOS writing-assistant popup built in Swift + AppKit.  
Reads the clipboard, runs your text through eight rewriting modes concurrently against a local OpenAI-compatible API, lets you pick the best result, and copies it back to the clipboard.

## Requirements

| Requirement | Version |
|---|---|
| macOS | 13 Ventura or later |
| Swift | 5.9+ (ships with Xcode 15+) |
| Local LLM server | OpenAI-compatible, listening at `http://localhost:2276` |

## Build

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run directly (debug)
swift run

# Run the release binary
.build/release/CopySmithMac
```

No Xcode project file is required. Everything is driven by `Package.swift`.

## Tests

```bash
swift test
```

Covers: SSE line parser, chat-mode prompt construction, refine-prompt assembly, and generation-state logic.

## Font

The app uses **Fantasque Sans Mono** (SIL OFL licence).  
Install it so the app looks as intended:

```bash
brew install --cask font-fantasque-sans-mono
```

If the font is not found at launch, the app falls back to the system monospace font automatically.

## Usage

1. Copy text to the clipboard.
2. Launch the app (or trigger it from Alfred).
3. Eight rewriting panels stream results concurrently (max 3 at a time).
4. Click a panel to expand it; press **Escape** to collapse.
5. Click **Copy** on any panel to copy that result and quit.
6. Click **Add >>** to accumulate responses in the **Combine & Refine** panel.
7. Click **Refine** to merge selected responses into one final output.
8. Click **Copy** in the refine panel to copy the refined result and quit.

## Configuration

All configuration is compiled in as defaults:

| Setting | Default | Source file |
|---|---|---|
| API endpoint | `http://localhost:2276/v1/chat/completions` | `ChatCompletionService.swift` |
| Models endpoint | `http://localhost:2276/v1/models` | `ModelService.swift` |
| Default model | `qwen3-4b` | `MainViewModel.swift` |
| Max concurrent requests | `3` | `GenerationScheduler.swift` |
| Chat timeout | `20 s` | `ChatCompletionService.swift` |
| Model-list timeout | `10 s` | `ModelService.swift` |

The selected model is persisted via `UserDefaults` (key: `selected_model`) and restored on next launch.

## Alfred integration

Create an Alfred workflow with a **Run Script** action:

```bash
open -a CopySmithMac
```

Or, if you keep the release binary on `$PATH`:

```bash
/path/to/CopySmithMac &
```

The app activates itself and steals focus (`NSApp.activate(ignoringOtherApps: true)`), so it pops up on top of whatever Alfred launched it from.

## Architecture

```
Sources/CopySmithMac/
  App/
    main.swift              – NSApplication entry point
    AppDelegate.swift       – creates the borderless NSWindow
  UI/
    MainViewController.swift – root layout: top bar + panel scroll + combine panel
    ResultPanelView.swift    – per-mode panel (expand/collapse, streaming text)
    CombinePanelView.swift   – combine & refine panel
    Styles.swift             – centralised colour, font, and spacing constants
  Domain/
    ChatMode.swift           – 8 modes with exact prompt prefixes
    GenerationState.swift    – ModeStatus / ModeResultState value types
  Services/
    ClipboardService.swift        – NSPasteboard read/write
    PreferencesService.swift      – UserDefaults wrapper (selected model)
    ChatCompletionService.swift   – URLSession SSE streaming + retry logic
    ModelService.swift            – /v1/models discovery
  Controllers/
    GenerationScheduler.swift – actor; enforces max-3 concurrency
    MainViewModel.swift       – @MainActor orchestrator; all app state
```

**Concurrency model:** one `Task` per mode, coordinated through `GenerationScheduler` (actor). Each task carries a generation token; stale responses from cancelled tasks are silently discarded. `@MainActor` isolation ensures all UI mutations happen on the main thread.

**Retry policy:** 3 attempts; HTTP 429 / 5xx and network errors are retried with exponential back-off starting at 1.5 s, capped at 10 s. `Retry-After` headers are respected when present.
