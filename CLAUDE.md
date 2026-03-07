# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Voco — a macOS menu bar app for voice-to-text input. Records audio via hotkey, transcribes with cloud STT, optionally reformats/translates with LLM, and pastes the result into the active app.

## Build & Run

The SPM project lives in `Voco/`. Build requires full Xcode (not just CLT) due to Swift macros (`@Model`, `@Observable`, `@Query`).

```bash
cd Voco && swift build
# Copy binary into .app bundle and launch:
cp .build/debug/Voco .build/Voco.app/Contents/MacOS/
open .build/Voco.app
```

The bare executable exits immediately — it must run inside the `.app` bundle (needs `Info.plist` with `LSUIElement=true`).

XcodeGen project config is in `Voco/project.yml`. The generated Xcode project is `Voco/OpenTypeLess.xcodeproj`.

## Architecture

**Pipeline flow** (triggered by global hotkey F5=reformat, F6=translate):

```
HotkeyService → VoiceInputPipeline.toggle(mode:)
  → AudioRecorderService (AVCaptureSession → WAV)
  → STTProviderFactory → OpenAICompatibleSTT
  → PersonalDictionaryService (vocabulary substitution)
  → Prompts (template with app-context placeholders)
  → LLMProviderFactory → OpenAICompatibleLLM
  → StrictModeGuard (validates output)
  → PasteService (CGEvent-based paste)
  → TranscriptionHistory (SwiftData persistence)
```

**Key patterns:**
- Factory pattern for providers (`STTProviderFactory`, `LLMProviderFactory`)
- Protocol-based providers (`STTProvider`, `LLMProvider`) with single implementation each (`OpenAICompatibleSTT`, `OpenAICompatibleLLM`)
- `AppSettings` is a singleton `@Observable` backed by UserDefaults
- SwiftData models: `TranscriptionHistory`, `DictionaryEntry`, `AppProfile`
- API keys stored file-based via `KeychainHelper` at `~/Library/Application Support/com.voco.app/.secrets` (not macOS Keychain)

**STT routing:** If model name contains "qwen" + "asr" → uses chat completions with base64 audio; otherwise → standard `/audio/transcriptions` (Whisper-compatible).

**Menu bar app quirks:** `LSUIElement=true` hides from Dock. Settings/History windows need temporary `NSApp.setActivationPolicy(.regular)` then switch back to `.accessory` to accept keyboard input.

## Code Conventions

- Swift 6.0 with strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- macOS 15+ deployment target
- `@Sendable` compliance throughout; `RecordingState` is `Sendable`
- Source lives under `Voco/Voco/` organized by: Configuration, Models, Protocols, Services, Utilities, Views
- Entry point: `Voco/Voco/VocoApp.swift`

## Dependencies

Declared in `project.yml` (XcodeGen):
- **KeyboardShortcuts** 2.1.0+ — global hotkey registration
- **LaunchAtLogin-Modern** 1.1.0+ — login item support

## Default Endpoints

- STT: DashScope (`dashscope.aliyuncs.com/compatible-mode/v1`) with `qwen3-asr-flash`
- LLM: configurable OpenAI-compatible endpoint
