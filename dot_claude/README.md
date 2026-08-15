# Claude Code の設定（`~/.claude`）

`~/.claude` には手書きの設定と、Claude Code が生成するランタイム状態
（`projects/`、`history.jsonl`、`.credentials.json` など、合計 100MB 超）が同居しています。
管理対象は次のものだけで、残りはリポジトリルートの `.chezmoiignore` で明示的に除外しています。

| ソース | 配置先 | 内容 |
| --- | --- | --- |
| `settings.json` | `~/.claude/settings.json` | env / model / permissions / hooks / attribution / statusLine / enabledPlugins など |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | 全プロジェクト共通の言語ルールとコミット / PR ルール |
| `output-styles/ja-concise.md` | `~/.claude/output-styles/ja-concise.md` | 日本語・簡潔応答スタイル |
| `skills/*/SKILL.md` | `~/.claude/skills/*/SKILL.md` | スキル定義（[skills/README.md](skills/README.md)） |

`~/.claude` のパスは Windows / Linux ともに同じなので、OS ごとの分岐はありません。

## Codex の Import 元でもある

`~/.claude` は Codex の Import 元も兼ねています。`settings.json` / `CLAUDE.md` /
`skills/` を変更すると、Codex 側の `~/.agents/skills` と `~/.codex/AGENTS.md`、
`~/.codex/config.toml` にも波及します。Codex 側は生成物として扱い、
このリポジトリでは管理しません。詳細はルートの
[README.md](../README.md#codex-との連携) を参照してください。

**Codex 用に別のスキルを `~/.agents/skills` や `~/.codex/skills` へ手で置かないこと。**
Import が上書きするため維持できません。

## 日本語化の担保

「ユーザ向けの応答は日本語」というルールは 2 層に置いています。

- `output-styles/ja-concise.md` — system prompt に展開される。言語ルールに加えて発話量・トーンを規定する
- `CLAUDE.md` — 全プロジェクトのコンテキストに入る。言語ルールと、後述のコミット / PR ルールを持つ

`output-styles` は `/output-style` で切り替えると丸ごと外れるため、`CLAUDE.md` を
バックストップとして併置しています。スキルやエージェントの**定義ファイル自体**は
英語で書く方針で、これは `CLAUDE.md` にのみ記載しています。

`settings.json` から `extraKnownMarketplaces` は意図的に外しています
（マシン固有の絶対パスを含むため）。必要になったら `/plugin` から手動で登録してください。

## ツール痕跡を残さない

コミットメッセージ・PR 本文・Issue 本文・コードコメントに、作業に使ったツールの痕跡
（署名、co-author トレーラ、生成元の定型句、絵文字）を残さないルールも 2 層に置いています。

- `settings.json` の `attribution` — `commit` / `pr` を空文字にすると Claude Code が
  `Co-Authored-By:` と `🤖 Generated with ...` を付けなくなる。`sessionUrl: false` は
  これらとは別系統の `Claude-Session` トレーラを止める
- `CLAUDE.md` の `# Commits and Pull Requests` — モデルが自主的に付ける分を禁じる

`attribution` を入れないと、Claude Code は「コミットメッセージの末尾に `Co-Authored-By:`
を付けろ」という指示を **system prompt に自分で注入します**。付与はモデルの癖ではなく
ハーネスの既定動作なので、`CLAUDE.md` だけでは打ち消しが後追いになります。

一方で `attribution` は Claude Code にしか効かず、Codex や GitHub MCP 経由の PR 作成には
届きません。`CLAUDE.md` は Import で `~/.codex/AGENTS.md` に波及するため両方に効きますが、
強制力はありません。**どちらか片方では塞がらないため、冗長に見えても両方残してください。**

## Browser pane を封じている

Claude Desktop の Browser pane（dev サーバープレビュー）が Chromium の GPU プロセスを
落とし、アプリ全体が無言終了します（[anthropics/claude-code#82967](https://github.com/anthropics/claude-code/issues/82967)）。

- `main.log` に `GPU process gone: { reason: 'crashed', exitCode: 101457950 }` が 3 件。
  うち 1 件は `[Preview] Created browser preview` の 1 秒後
- 同時刻に `claude.ai-web.log` へ `CONTEXT_LOST_WEBGL`
- TDR / Crashpad ダンプ / WER はなし。OS・ドライバレベルの問題ではない
- ハードウェアアクセラレーションを無効にした状態でも再現する

Browser pane 自体を切る設定は Claude Code 側に存在しません
（`browserExternalPageTools` と `disableBrowserExternalNavigation` は外部サイトにしか
効かず、localhost のプレビューは対象外）。そこで Claude に触らせない方向で 3 層置いています。

- `settings.json` の `permissions.deny` — `mcp__Claude_Browser` を bare で deny する。
  bare な deny はツールをコンテキストから除去し、`auto` / `bypassPermissions` を含む
  全パーミッションモードで効く。これが主層
- `settings.json` の `hooks.PreToolUse` — Desktop 内蔵サーバーに deny が届かなかった
  場合の保険。`mcp__Claude_Browser__.*` に一致したら exit 2 でブロックし、代替手段を
  stderr で Claude に返す。Windows ではフックが `cmd` で実行されるため、コマンドは
  `cmd` / `sh` 双方で通る構文だけを使い、括弧・引用符・`;` を含めていない
- `CLAUDE.md` の `# Browser pane` — 理由と代替手段（`run_in_background` + `curl`）を
  与え、ブロックされたときに設定を書き換えて回避しようとするのを止める

**ユーザー自身の操作は塞げません。** `Ctrl+Shift+B` で Browser pane を開く、チャット内の
HTML / PDF / 画像 / 動画のパスをクリックする、といった操作は設定では止まらないので手で避けてください。

プロジェクト側では `.claude/launch.json` に `"autoVerify": false` を入れると、編集のたびの
自動検証（プレビュー起動）が止まります。これはプロジェクト単位の設定しかないため、
このリポジトリでは管理せず各リポジトリで設定します。

Issue が解決したら、`settings.json` の `permissions.deny` と `hooks.PreToolUse`、
`CLAUDE.md` の `# Browser pane`、この節をまとめて削除してください。

## 注意

- `dot_claude/` 配下に `exact_` プレフィックスを付けないこと。
  `~/.claude` の会話ログや認証情報が消えます。
- `~/.claude/settings.json` は Claude Code 自身が書き換えます。
  `chezmoi re-add` の前に `chezmoi diff` で、マシン固有の絶対パスや
  一時的なプラグイン設定が混入していないか確認してください。
