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
dot_claude/             ~/.claude（Claude Code の設定 → dot_claude/README.md）
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

`~/.claude` はランタイム状態と設定が同居しているため、管理対象を絞った上で
残りを `.chezmoiignore` で除外しています。管理対象の内訳、日本語化の方針、
`settings.json` を扱う際の注意は [dot_claude/README.md](dot_claude/README.md) を
参照してください。スキルの一覧と詳細は
[dot_claude/skills/README.md](dot_claude/skills/README.md) にあります。

各ディレクトリの `README.md` は `.chezmoiignore` で除外しているため、ホームには配置されません。

## 注意

- `AppData/Roaming/` 配下に `exact_` プレフィックスを付けないこと。
  chezmoi が管理していない他アプリの設定まで削除されます。
- `dot_claude/` 配下にも `exact_` プレフィックスを付けないこと（[詳細](dot_claude/README.md#注意)）。
- `.vimrc` / `.gvimrc` / `.zsh/*.zsh` には `{{` `}}` が含まれるため、
  テンプレート（`.tmpl`）にしないこと。
- 秘密情報は `~/.secret` に置きます（`.zshenv` から読み込み、リポジトリでは管理しません）。
