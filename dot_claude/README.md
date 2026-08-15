# Claude Code の設定（`~/.claude`）

`~/.claude` には手書きの設定と、Claude Code が生成するランタイム状態
（`projects/`、`history.jsonl`、`.credentials.json` など、合計 100MB 超）が同居しています。
管理対象は次のものだけで、残りはリポジトリルートの `.chezmoiignore` で明示的に除外しています。

| ソース | 配置先 | 内容 |
| --- | --- | --- |
| `settings.json` | `~/.claude/settings.json` | env / model / attribution / statusLine / enabledPlugins など |
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

## 注意

- `dot_claude/` 配下に `exact_` プレフィックスを付けないこと。
  `~/.claude` の会話ログや認証情報が消えます。
- `~/.claude/settings.json` は Claude Code 自身が書き換えます。
  `chezmoi re-add` の前に `chezmoi diff` で、マシン固有の絶対パスや
  一時的なプラグイン設定が混入していないか確認してください。
