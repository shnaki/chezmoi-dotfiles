# Claude Code の設定（`~/.claude`）

`~/.claude` には手書きの設定と、Claude Code が生成するランタイム状態
（`projects/`、`history.jsonl`、`.credentials.json` など、合計 100MB 超）が同居しています。
管理対象は次のものだけで、残りはリポジトリルートの `.chezmoiignore` で明示的に除外しています。

| ソース | 配置先 | 内容 |
| --- | --- | --- |
| `settings.json` | `~/.claude/settings.json` | env / model / statusLine / enabledPlugins など |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | 全プロジェクト共通の言語ルール |
| `output-styles/ja-concise.md` | `~/.claude/output-styles/ja-concise.md` | 日本語・簡潔応答スタイル |
| `skills/*/SKILL.md` | `~/.claude/skills/*/SKILL.md` | スキル定義（[skills/README.md](skills/README.md)） |

`~/.claude` のパスは Windows / Linux ともに同じなので、OS ごとの分岐はありません。

## 日本語化の担保

「ユーザ向けの応答は日本語」というルールは 2 層に置いています。

- `output-styles/ja-concise.md` — system prompt に展開される。言語ルールに加えて発話量・トーンを規定する
- `CLAUDE.md` — 全プロジェクトのコンテキストに入る。言語ルールのみを持つ

`output-styles` は `/output-style` で切り替えると丸ごと外れるため、`CLAUDE.md` を
バックストップとして併置しています。スキルやエージェントの**定義ファイル自体**は
英語で書く方針で、これは `CLAUDE.md` にのみ記載しています。

`settings.json` から `extraKnownMarketplaces` は意図的に外しています
（マシン固有の絶対パスを含むため）。必要になったら `/plugin` から手動で登録してください。

## 注意

- `dot_claude/` 配下に `exact_` プレフィックスを付けないこと。
  `~/.claude` の会話ログや認証情報が消えます。
- `~/.claude/settings.json` は Claude Code 自身が書き換えます。
  `chezmoi re-add` の前に `chezmoi diff` で、マシン固有の絶対パスや
  一時的なプラグイン設定が混入していないか確認してください。
