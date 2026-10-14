# Grammy v2

[English](README.md) | 日本語

Slack などの入力欄を監視し、英文を打ち終えると LLM が改善案をキャレット付近にポップアップ表示する macOS ネイティブアプリ（Swift / AppKit + SwiftUI）。

## 仕組み

```
[Slack の入力欄] --Accessibility API (0.3秒ポーリング)--> TextMonitor
      ↑                                                     │ 入力停止 (既定 1.2 秒)
      │ ⌘A + ⌘V (Electron) / AXSelectedText (ネイティブ)      ▼
TextReplacer <-- 適用 (⌃⌥↩ / ボタン) -- SuggestionPanel <-- LiteLLMClient / ClaudeClient (JSON Schema 出力)
```

- **入力の取得**: `AXUIElement` でフロントアプリのフォーカス中テキスト欄の値を読む。Slack は Electron 製なので `AXManualAccessibility` を有効化してアクセシビリティツリーを出させている。パスワード欄 (`AXSecureTextField`) は読まない。
- **チェック**: 英語らしいテキストだけを送り、JSON Schema で `{has_issues, corrected_text, issues[]}` を受け取る。解説は日本語。
  - OpenAI 互換（既定）: 設定したエンドポイント（既定 `https://api.openai.com/v1/chat/completions`。LiteLLM プロキシなら `http://localhost:4000/v1/chat/completions` など）に `response_format: json_schema` で送信
    - LM Studio は `http://localhost:1234` を指定してモデル一覧からチャット用モデルを選ぶ。サーバー URL から `/v1/chat/completions` を自動補完する。一部の推論モデルが回答を `reasoning_content` に入れて `content` を空にした場合は、`reasoning_effort: none` で再試行する。
  - Anthropic API 直接: Messages API + `output_config.format`
- **表示**: キャレット位置 (`AXBoundsForRange`) に、アクティブ化しない `NSPanel` で単語単位の差分と指摘一覧を表示するので、フォーカスは Slack に残る。
- **適用**: `⌃⌥↩` またはボタンで適用。Electron アプリでは全選択してペーストし、クリップボードは元に戻す。

## ビルドと起動

```bash
make run          # build/Grammy.app を作って起動
```

初回起動時の設定:

1. **アクセシビリティ権限**: システム設定 → プライバシーとセキュリティ → アクセシビリティ で Grammy を許可
2. **API キー**: メニューバーのアイコン → 設定… で接続先（OpenAI 互換 / Anthropic）を選び、API キーを保存（`~/Library/Application Support/Grammy/credentials.json` に権限 0600 で保存。キーチェーンは使わない）
3. **接続テスト**: 設定画面の「接続テスト」→「テスト実行」で、選択中のモデルが正しい JSON を返すか確認できる（失敗時はどのキーが欠けているか・生の応答を表示）

> アドホック署名は既定だとビルドごとに変わる cdhash が指定要件になり、再ビルドで権限が外れる。
> `scripts/build-app.sh` では指定要件をバンドル ID (`identifier "ninja.oppai.grammy"`) に固定しているので、再ビルドしても権限は維持される。
> それでも「未許可」のままなら、メニューの「アクセシビリティ権限をリセットして再許可…」（`tccutil reset Accessibility ninja.oppai.grammy`）で付け直す。

## 設定

| 項目 | 既定値 |
|---|---|
| 接続先 | OpenAI 互換。エンドポイント URL は自由に変更可（既定 `https://api.openai.com/v1/chat/completions`） |
| モデル | OpenAI 互換: `/v1/models` から取得した一覧から選択（取得できない場合は手入力）/ Anthropic 直接: Opus 5.5（effort: low） |
| 監視対象 | `com.tinyspeck.slackmacgap`（Slack）。カンマ区切りで追加、または全アプリ |
| チェックまでの待ち時間 | 1.2 秒 |

## 既知の制約

- 適用すると入力欄全体が置き換わるため、Slack の太字などのリッチテキスト書式は失われる（プレーンテキストとして貼り付けられる）。
- 待ち時間はモデルの応答速度に依存する。大きいモデルは品質が高いが数秒かかることがある。
- 入力中のテキストは選択したプロバイダ経由でモデルに送信される。
