# Copy Smith

A native macOS writing-assistant popup built in Swift + AppKit.  
Reads the clipboard, runs your text through eight rewriting modes concurrently using Apple Intelligence, lets you pick the best result, and copies it back to the clipboard.

## Requirements

| Requirement | Version |
|---|---|
| macOS | 26.0 or later |
| Swift | 5.9+ (ships with Xcode 15+) |
| Apple Intelligence | Enabled in System Settings > Apple Intelligence & Siri |

## Build

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run directly (debug)
swift run

# Run the release binary
.build/release/CopySmith
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
3. Eight rewriting panels run sequentially (one at a time); each panel streams tokens as they arrive.
4. Click a panel to expand it; press **Escape** to collapse.
5. Click **Copy** on any panel to copy that result and quit.
6. Click **Refresh** on a panel to re-run just that mode.
7. Click **Add >>** to accumulate responses in the **Combine & Refine** panel.
8. Click **Refine** to merge selected responses into one final output.
9. Click **Copy** in the refine panel to copy the refined result and quit.
10. Click **Refresh All** in the toolbar to re-run all modes.

## Configuration

| Setting | Default | Source file |
|---|---|---|
| API endpoint (fallback) | `http://localhost:2276/v1/chat/completions` | `ChatCompletionService.swift` |
| Max concurrent requests | `1` | `GenerationScheduler.swift` |
| Chat timeout (fallback) | `20 s` | `ChatCompletionService.swift` |

The default LLM backend is Apple Intelligence (`FoundationModelService`). To switch to a local OpenAI-compatible server instead, pass a `ChatCompletionService` instance when constructing `MainViewModel`.

## Alfred integration

Create an Alfred workflow with a **Run Script** action:

```bash
open -a CopySmith
```

Or, if you keep the release binary on `$PATH`:

```bash
/path/to/CopySmith &
```

The app activates itself and steals focus (`NSApp.activate(ignoringOtherApps: true)`), so it pops up on top of whatever Alfred launched it from.

## Architecture

```
Sources/CopySmith/
  App/
    main.swift              – NSApplication entry point
    AppDelegate.swift       – creates the borderless NSWindow
  UI/
    MainViewController.swift – root layout: top bar + panel scroll + combine panel
    ResultPanelView.swift    – per-mode panel (expand/collapse, streaming text, per-panel refresh)
    CombinePanelView.swift   – combine & refine panel
    Styles.swift             – centralised colour, font, and spacing constants
  Domain/
    ChatMode.swift           – 8 modes with exact prompt prefixes
    GenerationState.swift    – ModeStatus / ModeResultState value types
  Services/
    ClipboardService.swift        – NSPasteboard read/write
    LLMService.swift              – LLMService protocol + ChatError types
    ChatCompletionService.swift   – URLSession SSE streaming + retry logic (OpenAI-compatible)
    FoundationModelService.swift  – Apple Intelligence via FoundationModels framework
  Controllers/
    GenerationScheduler.swift – actor; enforces max-3 concurrency
    MainViewModel.swift       – @MainActor orchestrator; all app state
```

**LLM backend:** The app uses `FoundationModelService` by default, which routes requests through Apple Intelligence on-device. `ChatCompletionService` is also available for OpenAI-compatible local servers. Both conform to the `LLMService` protocol, making the backend swappable.

**Concurrency model:** one `Task` per mode, coordinated through `GenerationScheduler` (actor). Each task carries a generation token; stale responses from cancelled tasks are silently discarded. `@MainActor` isolation ensures all UI mutations happen on the main thread.

**Retry policy (ChatCompletionService):** 3 attempts; HTTP 429 / 5xx and network errors are retried with exponential back-off starting at 1.5 s, capped at 10 s. `Retry-After` headers are respected when present.
