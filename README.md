# chezmoi-dotfiles

[chezmoi](https://www.chezmoi.io/) で管理する個人用 dotfiles です。
Windows と Linux/WSL の両方を対象にしています。

## セットアップ

### 1. chezmoi をインストール

```bash
winget install twpayne.chezmoi
```

Linux/WSL の場合:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
```

### 2. リポジトリを clone

```bash
ghq get https://github.com/shnaki/chezmoi-dotfiles.git
```

### 3. ソースディレクトリを chezmoi に教える

`~/.config/chezmoi/chezmoi.toml` を作成します。このファイルはマシンごとに用意するもので、
chezmoi の管理対象には含めません。

```toml
sourceDir = "C:/Users/<username>/src/github.com/shnaki/chezmoi-dotfiles"
```

Linux/WSL では clone 先に合わせて書き換えてください（例: `~/src/github.com/shnaki/chezmoi-dotfiles`）。

### 4. 反映

```bash
chezmoi diff
```

```bash
chezmoi apply
```

## 日常の使い方

| やりたいこと | コマンド |
| --- | --- |
| 差分を見る | `chezmoi diff` |
| ホームへ反映する | `chezmoi apply` |
| 未反映の対象を一覧する | `chezmoi status` |
| 管理対象を一覧する | `chezmoi managed` |
| ソースを編集する | `chezmoi edit ~/.vimrc` |
| ホーム側の変更を取り込む | `chezmoi re-add` |
| 新しいファイルを管理下に置く | `chezmoi add ~/.foorc` |
| リモートの更新を取得して反映 | `chezmoi update` |

## リポジトリ構成

```
.chezmoiignore          OS ごとに配置対象を切り替える / ~/.claude の除外設定
.chezmoitemplates/      複数パスへ配るファイルの実体
AppData/Roaming/        Windows 用の配置先（中身は .chezmoitemplates を参照するだけ）
dot_config/             Linux/WSL 用の配置先（同上）
dot_claude/             ~/.claude（Claude Code の設定）
dot_zsh/                ~/.zsh
dot_*                   ~/ 直下の dotfiles
```

`dot_` プレフィックスは chezmoi の記法で、配置時に `.` に置き換わります
（`dot_vimrc` → `~/.vimrc`）。

### OS ごとの配置先

| 内容 | Linux/WSL | Windows |
| --- | --- | --- |
| vim / git / zsh / tmux / mintty など | `~/` 直下 | 同左 |
| Claude Code | `~/.claude/` | 同左 |
| Zed | `~/.config/zed/` | `~/AppData/Roaming/Zed/` |
| VS Code | `~/.config/Code/User/` | `~/AppData/Roaming/Code/User/` |
| alacritty | `~/.config/alacritty/` | `~/AppData/Roaming/alacritty/` |
| jj | `~/.config/jj/` | `~/AppData/Roaming/jj/` |

配置先が OS で分かれるファイルは、実体を `.chezmoitemplates/` に置き、
両方の配置先には次の一行だけを書いたテンプレートを置いています。

```
{{- template "zed/settings.json" . -}}
```

**Zed / VS Code / alacritty / jj の設定を変更するときは `.chezmoitemplates/` 側を編集してください。**
`AppData/Roaming/` や `dot_config/` にあるのは参照用のラッパーです。

## Claude Code の設定

`~/.claude` には手書きの設定と、Claude Code が生成するランタイム状態
（`projects/`、`history.jsonl`、`.credentials.json` など、合計 100MB 超）が同居しています。
管理対象は次のものだけで、残りは `.chezmoiignore` で明示的に除外しています。

| ソース | 配置先 | 内容 |
| --- | --- | --- |
| `dot_claude/settings.json` | `~/.claude/settings.json` | env / model / statusLine / enabledPlugins など |
| `dot_claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | 全プロジェクト共通の言語ルール |
| `dot_claude/output-styles/ja-concise.md` | `~/.claude/output-styles/ja-concise.md` | 日本語・簡潔応答スタイル |
| `dot_claude/skills/*/SKILL.md` | `~/.claude/skills/*/SKILL.md` | スキル定義（下表） |

### スキル

いずれも `disable-model-invocation: true` で、スラッシュコマンドからのみ起動します。

| スキル | 内容 |
| --- | --- |
| `cm` | Conventional Commits でコミットする |
| `triage-notes` | メモを調査して GitHub Issue を起票する（実装しない） |
| `issue-pr` | Issue 1件を PR 1件として実装する |
| `ship-notes` | メモ → Issue → 並列ワーカー → PR を通しで回すオーケストレータ |
| `pr-review` | PR を独立した立場でレビューする（変更しない） |

`~/.claude` のパスは Windows / Linux ともに同じなので、OS ごとの分岐はありません。

### 日本語化の担保

「ユーザ向けの応答は日本語」というルールは 2 層に置いています。

- `output-styles/ja-concise.md` — system prompt に展開される。言語ルールに加えて発話量・トーンを規定する
- `CLAUDE.md` — 全プロジェクトのコンテキストに入る。言語ルールのみを持つ

`output-styles` は `/output-style` で切り替えると丸ごと外れるため、`CLAUDE.md` を
バックストップとして併置しています。スキルやエージェントの**定義ファイル自体**は
英語で書く方針で、これは `CLAUDE.md` にのみ記載しています。

`settings.json` から `extraKnownMarketplaces` は意図的に外しています
（マシン固有の絶対パスを含むため）。必要になったら `/plugin` から手動で登録してください。

## 注意

- `AppData/Roaming/` 配下に `exact_` プレフィックスを付けないこと。
  chezmoi が管理していない他アプリの設定まで削除されます。
- `dot_claude/` 配下にも `exact_` プレフィックスを付けないこと。
  `~/.claude` の会話ログや認証情報が消えます。
- `~/.claude/settings.json` は Claude Code 自身が書き換えます。
  `chezmoi re-add` の前に `chezmoi diff` で、マシン固有の絶対パスや
  一時的なプラグイン設定が混入していないか確認してください。
- `.vimrc` / `.gvimrc` / `.zsh/*.zsh` には `{{` `}}` が含まれるため、
  テンプレート（`.tmpl`）にしないこと。
- 秘密情報は `~/.secret` に置きます（`.zshenv` から読み込み、リポジトリでは管理しません）。
