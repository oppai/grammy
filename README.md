# Grammy v2

English | [日本語](README.ja.md)

A native macOS app (Swift / AppKit + SwiftUI) that watches text fields in apps like Slack. When you pause after typing English, an LLM suggests corrections in a popup next to the caret, IME-style.

## How it works

```
[Slack text field] --Accessibility API (polled every 0.3s)--> TextMonitor
      ↑                                                         │ typing pause (default 1.2s)
      │ ⌘A + ⌘V (Electron) / AXSelectedText (native)              ▼
TextReplacer <-- apply (⌃⌥↩ / button) -- SuggestionPanel <-- LiteLLMClient / ClaudeClient (JSON Schema output)
```

- **Reading input**: Reads the value of the focused text field in the frontmost app through `AXUIElement`. Slack is built on Electron, so Grammy sets `AXManualAccessibility` to make it expose its accessibility tree. Password fields (`AXSecureTextField`) are never read.
- **Checking**: Only English-looking text is sent. The model replies with JSON matching a schema: `{has_issues, corrected_text, issues[]}`. Explanations are written in Japanese, since the prompt targets Japanese speakers writing in English.
  - OpenAI-compatible (default): sends to the configured endpoint (default `https://api.openai.com/v1/chat/completions`; for a LiteLLM proxy, something like `http://localhost:4000/v1/chat/completions`) with `response_format: json_schema`
  - Anthropic API (direct): Messages API with `output_config.format`
- **Display**: Shows a word-level diff and the list of issues in a non-activating `NSPanel` at the caret position (`AXBoundsForRange`), so keyboard focus stays in Slack.
- **Applying**: Press `⌃⌥↩` or click the button. In Electron apps Grammy selects all and pastes, then restores your clipboard.

## Requirements

- macOS 14 or later
- An API key for an OpenAI-compatible endpoint, or for the Anthropic API

The app's UI is currently Japanese only. The labels below are given as they appear, with English in parentheses.

## Build and run

```bash
make run          # builds build/Grammy.app and launches it
```

First-launch setup:

1. **Accessibility permission**: Allow Grammy in System Settings → Privacy & Security → Accessibility.
2. **API key**: Open the menu bar icon → 設定… (Settings), choose a provider (OpenAI-compatible / Anthropic), and save your API key. The key is stored in `~/Library/Application Support/Grammy/credentials.json` with mode 0600, not in the Keychain.
3. **Connection test**: In Settings, click 接続テスト (Connection test) → テスト実行 (Run test) to check that the selected model returns valid JSON. On failure, it shows which key is missing and the raw response.

> By default, an ad-hoc signature's designated requirement is its cdhash, which changes on every build and silently revokes the Accessibility permission.
> `scripts/build-app.sh` pins the designated requirement to the bundle ID (`identifier "ninja.oppai.grammy"`), so the permission survives rebuilds.
> If Grammy still shows as not allowed, choose 「アクセシビリティ権限をリセットして再許可…」 (Reset Accessibility permission and re-grant) from the menu (equivalent to `tccutil reset Accessibility ninja.oppai.grammy`) and grant it again.

To sign with a real certificate instead of ad-hoc:

```bash
CODESIGN_IDENTITY="Your Certificate Name" make run
```

To regenerate the app icon:

```bash
swift scripts/make-icon.swift
```

## Settings

| Setting | Default |
|---|---|
| Provider | OpenAI-compatible. The endpoint URL can be changed freely (default `https://api.openai.com/v1/chat/completions`) |
| Model | OpenAI-compatible: pick from the list fetched from `/v1/models` (or type a name if the list is unavailable) / Anthropic direct: Claude Opus 5.5 (effort: low) |
| Monitored apps | `com.tinyspeck.slackmacgap` (Slack). Add more as comma-separated bundle IDs, or enable all apps |
| Delay before checking | 1.2 seconds |

## Troubleshooting

Grammy logs what it sees (field roles, text lengths, why a check was skipped) without logging the text itself:

```bash
/usr/bin/log stream --level debug --predicate 'subsystem == "ninja.oppai.grammy"'
```

## Known limitations

- Applying a suggestion replaces the whole field as plain text, so Slack rich-text formatting such as bold is lost.
- How long a suggestion takes depends on the model. Larger models give better results but can take several seconds.
- Text you type is sent to the model through the provider you selected.
