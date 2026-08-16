# Claude Code の設定（`~/.claude`）

`~/.claude` には手書きの設定と、Claude Code が生成するランタイム状態
（`projects/`、`history.jsonl`、`.credentials.json` など、合計 100MB 超）が同居しています。
管理対象は次のものだけで、残りはリポジトリルートの `.chezmoiignore` で明示的に除外しています。

| ソース | 配置先 | 内容 |
| --- | --- | --- |
| `settings.json` | `~/.claude/settings.json` | env / model / permissions（`gh` 読み取り系の allow、Browser pane の deny）/ hooks / attribution / statusLine / enabledPlugins など |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | 全プロジェクト共通の言語ルールとコミット / PR ルール |
| `output-styles/ja-concise.md` | `~/.claude/output-styles/ja-concise.md` | 日本語・簡潔応答スタイル |
| `skills/*/` | `~/.claude/skills/*/` | スキル定義（`SKILL.md`）と付随ファイル（[skills/README.md](skills/README.md)） |
| `scripts/*.sh` | `~/.claude/scripts/*.sh` | スキルから呼ぶシェルスクリプト（後述） |

`~/.claude` のパスは Windows / Linux ともに同じなので、OS ごとの分岐はありません。

`~/.claude/ship-issues/` はスキルが書き出す実行状態（中断・再開用）で、管理対象では
ありません（[skills/README.md](skills/README.md#ship-issues)）。

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

## 作業中に投げた質問の回答が消える

実装中に追加の質問を送っても回答が返ってこないことがあります。トランスクリプト
（`~/.claude/projects/**/*.jsonl`）を全件調べたところ、**UI の表示問題ではなく、
モデルが答えていない**のが原因でした。

- 質問自体は届いている。作業中のメッセージは `queue-operation: enqueue` の後、
  次のツール結果と同時に `attachment: queued_command`（`origin.kind: human`）と
  してターンの内部へ差し込まれる。捨てられてはいない
- 実例（`sf6-playbook`、2026-08-16 01:12）: ゴールデンテストの実装を問う質問に対し、
  モデルは Grep / Read の後に **Edit で該当箇所を直しただけ**でテキストを返さず、
  5 分後の「さきほどの質問の答えは？」にも答えなかった。最終回答に修正内容が
  1 行載っただけ
- 長いターン（ツール 35〜200 回）ほど落ちやすい。即答されたのは作業方針に直結する
  質問だけで、それ以外は最終回答に圧縮されるか消える

原因は 3 つの合成です。

- **ハーネスの文言**。差し込み時に付く指示は「`Address the message above as you
  continue this turn.`」で、**続行しながら対処せよとしか言わず、返答せよとは
  言っていない**
- **`output-styles/ja-concise.md`**。「ツール呼び出しの間にテキストを挟まない」
  「最終回答は 10 行以内」「経緯は書かない」が重なり、途中で答える経路と最後に
  答える余地の両方を塞いでいた
- **自動モードの system prompt**。「ユーザーはリアルタイムに見ていない」が即答の
  動機をさらに下げる

**hook では塞げません。** キュー経由のメッセージで `UserPromptSubmit` が発火するかは
バイナリから確認できず、`Stop` hook は「未回答の質問が残っているか」を判定できません。
そのため言語ルールと同じく指示で 2 層に置いています。

- `output-styles/ja-concise.md` の `# 作業中に届いたメッセージ` — 「次のツールを
  呼ぶ前にテキストで答える」を「ツール呼び出しの間にテキストを挟まない」より
  優先させる。回答をコード変更で代用することも明示的に禁じる
- `CLAUDE.md` の `# Messages that arrive mid-turn` — `/output-style` で ja-concise が
  外れた場合のバックストップ。Import 経由で Codex 側にも効く

効いているかは、セッションの `.jsonl` で `attachment.type == "queued_command"` の
直後を見て、**次の `tool_use` より前に回答の `text` があるか**で確認できます。

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

## gh の読み取り系を許可している

スキルは GitHub 操作を GitHub CLI（`gh`）に統一しています
（[skills/README.md](skills/README.md#前提ツール)）。都度の権限プロンプトを減らすため、
`settings.json` の `permissions.allow` に副作用のない `gh` サブコマンドだけを入れています。

- 許可: `gh auth status` / `gh repo view` / `gh pr list|view|diff|checks|status` /
  `gh issue list|view|status` / `gh search issues|prs`
- 許可しない: `gh api`（GET も POST も同じ入口で区別できない）、`create` / `edit` /
  `close` / `merge` / `comment` などの書き込み系。これらは都度確認のまま

`enabledPlugins` の `github@claude-plugins-official`（GitHub MCP）は対話用に残していますが、
スキルからは使いません。MCP 側のツールは `permissions.allow` に入れていないので、
使えば都度確認になります。

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

## worktree のゴミを掃除する

`ship-issues` は Issue ごとに Agent tool の `isolation: "worktree"` でワーカーを立てます。
このとき作られる worktree は**ワーカーが 1 度でもコミットすると自動削除の対象から外れる**
ため、実行のたびにゴミが残り続けます。実測（`sf6-playbook`、掃除前）:

| 種類 | 実測 | 状況 |
| --- | --- | --- |
| `worktree-agent-*` ブランチ | 15 本 | 全て main にマージ済み。ワーカーは別途 `NN-*` ブランチを切るので、このブランチは一度も使われない純粋なゴミ |
| `NN-*` 作業ブランチ | 14 本 | PR マージ済み。ローカルに残ったまま |
| `.claude/worktrees/agent-*/` | 6〜8 個 | `node_modules` 込みのフルチェックアウト。しかも `git worktree list` から登録が消えているため `git worktree prune` では落ちず、`git worktree remove` も効かない（ただのディレクトリになっている） |

**Claude Code 側に自動削除の設定はありません。** `settings.json` の `worktree` オブジェクトが
持つのは `baseRef`（`fresh` / `head`）と `bgIsolation`（`worktree` / `none`）だけで、掃除に
関わるキーは存在せず、クリーンアップ用のコマンドもありません。設定で消せないか再調査しないこと。

そこで `scripts/worktree-sweep.sh` を置いています。

```bash
sh ~/.claude/scripts/worktree-sweep.sh --dry-run
```

- 削除するのは「孤児 worktree ディレクトリ」「クリーンかつ HEAD が remote に届いている
  登録済み worktree」「base branch にマージ済みのブランチ」「upstream が `[gone]` で、
  かつ `gh` がマージ済み PR を確認できたブランチ」だけ
- **オープンな PR のブランチは消えません**（upstream が生きていて未マージのため、
  どの削除条件にも当たらない）
- 未コミット変更のある worktree、HEAD が remote に無い worktree、`gh` で裏を取れない
  ブランチは削除せず理由付きで報告する
- 直近 60 分に更新された worktree は実行中のエージェントとみなしてスキップする（`--force` で解除）
- カレントディレクトリが属する worktree とブランチには触らない

呼び出し口は 2 つです。`ship-issues` の最終ステップ（ゴミの発生源）と、
任意のタイミングで叩ける `/worktree-sweep` スキル。

`--recursive` を付けると引数のディレクトリ配下を再帰的に走査します。既定のルートは
持たせていないので、`sh ~/.claude/scripts/worktree-sweep.sh --recursive ~/src` のように
対象を明示して渡します。

## 注意

- `dot_claude/` 配下に `exact_` プレフィックスを付けないこと。
  `~/.claude` の会話ログや認証情報が消えます。
- `~/.claude/settings.json` は Claude Code 自身が書き換えます。
  `chezmoi re-add` の前に `chezmoi diff` で、マシン固有の絶対パスや
  一時的なプラグイン設定が混入していないか確認してください。
