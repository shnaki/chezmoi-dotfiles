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
| ホーム側の変更を取り込む | `chezmoi re-add`（`~/.claude/settings.json` は対象外 → [dot_claude/README.md](dot_claude/README.md#settingsjson-はキー単位でマージする)） |
| 新しいファイルを管理下に置く | `chezmoi add ~/.foorc` |
| リモートの更新を取得して反映 | `chezmoi update` |

## リポジトリ構成

```
.chezmoiignore          OS ごとに配置対象を切り替える / ~/.claude の除外設定
.chezmoitemplates/      複数パスへ配るファイル / テンプレートから参照するファイルの実体
AppData/Roaming/        Windows 用の配置先（中身は .chezmoitemplates を参照するだけ）
dot_config/             Linux/WSL 用の配置先（同上）
dot_claude/             ~/.claude（Claude Code の設定 → dot_claude/README.md）
dot_zsh/                ~/.zsh
dot_*                   ~/ 直下の dotfiles
```

Codex（`~/.codex` / `~/.agents`）に対応するディレクトリはありません。意図的に
管理対象外にしています（[Codex との連携](#codex-との連携)）。

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

**Zed / VS Code / alacritty / jj / Claude Code の設定を変更するときは `.chezmoitemplates/` 側を編集してください。**
`AppData/Roaming/` や `dot_config/` にあるのは参照用のラッパーです。Claude Code の
`settings.json` はラッパーではなくキー単位でマージする `modify_` テンプレートで、理由は
[dot_claude/README.md](dot_claude/README.md#settingsjson-はキー単位でマージする) にあります。

## Claude Code の設定

`~/.claude` はランタイム状態と設定が同居しているため、管理対象を絞った上で
残りを `.chezmoiignore` で除外しています。管理対象の内訳、日本語化の方針、
`settings.json` を扱う際の注意は [dot_claude/README.md](dot_claude/README.md) を
参照してください。スキルの一覧と詳細は
[dot_claude/skills/README.md](dot_claude/skills/README.md) にあります。

各ディレクトリの `README.md` は `.chezmoiignore` で除外しているため、ホームには配置されません。

## Codex との連携

Codex には Claude Code の設定・スキルを取り込む Import 機能があります。
このリポジトリでは **`~/.claude` を source of truth とし、Codex 側は Import の
生成物として扱います**。同じスキルを 2 箇所で管理することはしません。

```
chezmoi apply
     ↓
~/.claude/                      ← このリポジトリが管理する唯一の実体
     ↓  Codex Desktop: Settings > Import（Automatic updates を ON）
     ↓  Desktop が無い環境は Codex CLI の /import をその都度実行
~/.agents/skills/               スキルの変換結果
~/.codex/AGENTS.md              CLAUDE.md の変換結果
~/.codex/config.toml            settings.json / MCP / plugins の変換結果
```

### 新しいマシンでの手順

1. `chezmoi apply` で `~/.claude` を配置する（Import 元が先に要る）
2. Codex にログインする
3. Codex Desktop の **Settings > Import** で Claude Code を選び、
   **Automatic updates を ON** にする。以降は `~/.claude` の変更が自動で取り込まれる
4. Desktop を使わない環境では Codex CLI で `/import` を実行する。
   こちらはワンショットで、自動同期はされない

### `.agents` と `.codex` の役割

| ディレクトリ | 役割 | chezmoi |
| --- | --- | --- |
| `~/.agents/skills/` | エージェント横断のスキル置き場。Codex がユーザースキルを探す標準の場所であり、Import の出力先 | 管理しない（生成物） |
| `~/.codex/config.toml` | Codex 固有設定。Import の書き込み先でもある | 管理しない（後述） |
| `~/.codex/agents/` | Codex の subagent 定義（`*.toml`） | 未使用。必要になったら `dot_codex/agents/` で管理する |
| `~/.codex/hooks/` | Codex の hooks | 未使用。同上 |
| `~/.codex/rules/` `auth.json` `*.sqlite` | 承認ルール・認証情報・ランタイム状態 | 管理しない |
| `~/.codex/skills/` | 後方互換の旧配置。Codex 同梱スキルのみが入る | 使わない（新規スキルを置かない） |

`.agents` は `.codex` の新版ではなく、役割が違います。`.agents` は
エージェント横断のスキル、`.codex` は Codex 固有の設定です。
**新しいスキルを `~/.codex/skills/` に置かないこと。**

### 管理しないものとその理由

- **Automatic updates の設定** — Codex Desktop の UI からしか設定できません。
  実機の `config.toml` には `[desktop] external-agent-import-sync-enabled` が
  書かれていますが、これは Desktop アプリが書き込む UI 状態で、
  同期対象の選択は `~/.codex/.codex-global-state.json` 側にあります。
  公式の設定キーではないため、dotfiles では管理しません。
- **`~/.codex/config.toml`** — マシン固有の絶対パス、プロジェクトごとの
  `trust_level`、Codex 自身が随時書き換える UI 状態、Import が書き込む
  `[mcp_servers.*]` / `[plugins.*]` が混在します。`settings.json` から
  `extraKnownMarketplaces` を外したのと同じ判断で、ファイルは管理せず
  意図して選んだ値だけを下に記録します。

新しいマシンでは次の値を手で設定し直してください。

| キー | 値 |
| --- | --- |
| `model` | `gpt-5.6-sol` |
| `model_reasoning_effort` | `high` |
| `plan_mode_reasoning_effort` | `high` |
| `approvals_reviewer` | `auto_review` |
| `[windows] sandbox` | `elevated` |
| `[shell_environment_policy] inherit` | `core` |
| `[shell_environment_policy.set]` | `DISABLE_TELEMETRY` `DO_NOT_TRACK` `DISABLE_FEEDBACK_COMMAND` `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` `DISABLE_ERROR_REPORTING` = `"1"` |
| `[features] js_repl` | `false` |
| `[notice] hide_full_access_warning` | `true` |

## 注意

- `AppData/Roaming/` 配下に `exact_` プレフィックスを付けないこと。
  chezmoi が管理していない他アプリの設定まで削除されます。
- `dot_claude/` 配下にも `exact_` プレフィックスを付けないこと（[詳細](dot_claude/README.md#注意)）。
- `.vimrc` / `.gvimrc` / `.zsh/*.zsh` には `{{` `}}` が含まれるため、
  テンプレート（`.tmpl`）にしないこと。
- `~/.codex` を `chezmoi add` しないこと。会話ログの sqlite（200MB 超）と
  `auth.json` がリポジトリに入ります。
- `~/.agents` を `chezmoi add` しないこと。Import の生成物なので、
  管理すると `~/.claude/skills` との二重管理になります。
- 秘密情報は `~/.secret` に置きます（`.zshenv` から読み込み、リポジトリでは管理しません）。
