# Claude Code の設定（`~/.claude`）

`~/.claude` には手書きの設定と、Claude Code が生成するランタイム状態
（`projects/`、`history.jsonl`、`.credentials.json` など、合計 100MB 超）が同居しています。
管理対象は次のものだけで、残りはリポジトリルートの `.chezmoiignore` で明示的に除外しています。

| ソース | 配置先 | 内容 |
| --- | --- | --- |
| `modify_settings.json` + `.chezmoitemplates/claude/settings.json` | `~/.claude/settings.json` | env / model / permissions（`gh` 読み取り系と `git commit` の allow、Browser pane の deny）/ hooks / attribution / statusLine / enabledPlugins など。管理キーだけをホーム側にマージし、Claude Code が生成するキー（`autoMode` など）は触らない（[後述](#settingsjson-はキー単位でマージする)） |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | 全プロジェクト共通の言語ルールとコミット / PR ルール |
| `output-styles/ja-concise.md` | `~/.claude/output-styles/ja-concise.md` | 日本語・簡潔応答スタイル |
| `skills/*/` | `~/.claude/skills/*/` | スキル定義（`SKILL.md`）と付随ファイル（[skills/README.md](skills/README.md)） |
| `scripts/*.sh` | `~/.claude/scripts/*.sh` | スキルから呼ぶシェルスクリプト（後述） |

`~/.claude` のパスは Windows / Linux ともに同じなので、OS ごとの分岐はありません。

`~/.claude/ship-issues/` はスキルが書き出す実行状態（中断・再開用）で、管理対象では
ありません（[skills/README.md](skills/README.md#ship-issues)）。`work-status` が
未完の run を探すためにここを読みます（[後述](#進行中の作業を一覧する)）。
`~/.claude/handoff/` も同様で、`handoff` スキルが書く引継ぎ文書と patch の置き場です
（[skills/README.md](skills/README.md#handoff)）。

## settings.json はキー単位でマージする

`~/.claude/settings.json` は Claude Code 自身が丸ごと書き戻すファイルです。
`autoMode.environment` のような自動生成キーの追加や、キー順・配列の整形が入るため、
ファイル全体を管理すると `chezmoi status` が常に差分を出し続けます。
`autoMode.environment` には自宅 LAN の IP や private リポジトリの構成、秘密情報の置き場所が
列挙されるので、このリポジトリ（public）へ `chezmoi re-add` で取り込むわけにもいきません。

そこで chezmoi の `chezmoi:modify-template` を使い、ファイル全体ではなく
**管理したいキーだけをホーム側の現在の内容に上書きマージ**しています。

- `.chezmoitemplates/claude/settings.json` — 管理する内容の実体。**変更するときはここを編集して
  `chezmoi apply`**
- `modify_settings.json` — apply 時にホーム側の現在の内容を `.chezmoi.stdin` で受け取り、
  上の内容を `merge` して書き戻す 4 行のテンプレート。`.tmpl` は付けない（付けると
  chezmoi が先に通常のテンプレートとして評価し、`.chezmoi.stdin` が無い状態で失敗する）

マージの挙動:

- 管理側にあるキーは管理側の値で上書き。`permissions.allow` のような配列も丸ごと置換される
  （ホーム側でだけ追加した allow ルールは apply で消える）
- 管理側に無いキー（`autoMode` など）はホーム側の値がそのまま残る
- 出力はキーがアルファベット順に並ぶ。Claude Code は既存のキー順を保って書き戻すので、
  apply 後に `chezmoi status` が `M` になるのは Claude Code が新しいキーを追加した直後だけで、
  その `apply` はキー順を揃えるだけで何も失わない
- 管理キーを**削除**したいときは、`.chezmoitemplates/claude/settings.json` から消すだけでは
  ホーム側に残る。`modify_settings.json` に一時的に
  `{{ $_ := unset $current "キー名" }}` を足して apply し、その後その行を消す

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

## gh の読み取り系と git commit を許可している

スキルは GitHub 操作を GitHub CLI（`gh`）に統一しています
（[skills/README.md](skills/README.md#前提ツール)）。都度の権限プロンプトを減らすため、
`settings.json` の `permissions.allow` に副作用のない `gh` サブコマンドだけを入れています。

- 許可: `gh auth status` / `gh repo view` / `gh pr list|view|diff|checks|status` /
  `gh issue list|view|status` / `gh label list` / `gh release list|view` /
  `gh run view`（`pr-fix` が失敗した checks のログを読む）/ `gh search issues|prs`
- 許可しない: `gh api`（GET も POST も同じ入口で区別できない）、`create` / `edit` /
  `close` / `merge` / `comment` / `review` / `release create` /
  `label create|edit|delete` などの書き込み系。これらは都度確認のまま

`git commit` も許可に入れています。ローカルに閉じていて取り消せるうえ、`cm` や
`pr-ready` など多くのスキルが必ず通る工程のためです。auto mode の分類器が
`git commit` を弾いて手が止まることがあり、その回避も兼ねています。`git push` と
ブランチ削除は remote に出るため許可していません。

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

削除が「ロックで失敗する」ときの正体は 3 つあり、それぞれ扱いが違います。

| 症状 | 正体 | スクリプトの挙動 |
| --- | --- | --- |
| `cannot remove a locked working tree` | Claude Code がセッション中の worktree に付ける `git worktree lock`。異常終了すると外れずに残る。理由文字列に pid が入っている | pid が死んでいれば stale とみなして自動 `unlock` し、そのまま削除まで進む（`--dry-run` では `unlock` 行を出すだけ）。pid が生きていれば `locked by a running claude session (pid N)` で keep |
| `error: failed to delete ...: Filename too long` | Windows のパス長上限。`node_modules` の深い階層で `git worktree remove` が落ちる。しかも admin エントリ（`.git/worktrees/*`）だけ先に消えてディレクトリが孤児になる | 失敗したらディレクトリを直接 `rm -rf` してから `git worktree prune` するフォールバックへ。恒久策として `~/.gitconfig` に `core.longpaths = true` を入れてある |
| `Device or resource busy` | 別プロセス（終了していないシェルやセッション）がそのディレクトリを cwd として掴んでいる | スクリプト側では解決できない。`in use by another process` として keep する。掴んでいるセッション／シェルを閉じてから再実行する |

`--force` が緩めるのは 60 分ガードだけです。ロックも未コミット変更も `--force` では
押し切れません。

`ship-issues` の最終ステップだけは `--force` 付きで呼びます。ワーカー完了直後は必ず
60 分ガードに当たり、付けないと worktree が 1 つも消えないためです。

呼び出し口は 2 つです。`ship-issues` の最終ステップ（ゴミの発生源）と、
任意のタイミングで叩ける `/worktree-sweep` スキル。

`--recursive` を付けると引数のディレクトリ配下を再帰的に走査します。既定のルートは
持たせていないので、`sh ~/.claude/scripts/worktree-sweep.sh --recursive ~/src` のように
対象を明示して渡します。

## 既定のラベルセットをリポジトリに流し込む

リポジトリごとにラベルの語彙がばらつくと、`triage-notes` / `issue-pr` / `pr-ready` が
Issue や PR に付けるラベルも決まりません。そこで既定セットを `scripts/label-sync.sh` に
1 か所で持ち、`/label-sync` でリポジトリへ冪等に流し込みます。セットの中身は
[skills/README.md](skills/README.md#label-sync) にあります。

```bash
sh ~/.claude/scripts/label-sync.sh --dry-run
```

- 既にある GitHub 既定ラベル（`bug` / `enhancement` / `documentation` / `question` /
  `duplicate` / `wontfix`）は `gh label edit --name` で **rename** して取り込むので、
  付与済みの Issue からラベルが外れない
- セット外のラベルは `unmanaged` として報告するだけで触らない。`--prune` を付けたときだけ、
  open / closed を問わず 1 件も付いていないラベルを消す。使用中なら keep
- rename 元が複数あるとき（`chore` と `ci` の両方があるなど）は表の先頭のものだけ rename し、
  残りは `superseded` として報告する。統合は `/label-apply` で付け替えてから `--prune` で消す
- `-R owner/repo` で対象を指定できる。省略時はカレントディレクトリのリポジトリ

## 進行中の作業を一覧する

`ship-issues` は数時間走り、状態が 4 か所に散ります。GitHub の open PR、
`.claude/worktrees/agent-*` の worktree、ローカルブランチ、`~/.claude/ship-issues/` の
run ファイルです。途中で止めた後や別セッションから「いま何が動いていて、次に何を
叩けばいいか」を横断して読む手段が無かったので、`scripts/work-status.sh` を置いています。
`/work-status` スキルはこれを呼んで表に整形するだけです。

```bash
sh ~/.claude/scripts/work-status.sh
```

読み取り専用です。唯一の副作用は `git fetch --prune` で、`--no-fetch` で止まります。
書き込みモードが無いので `--dry-run` もありません。

出力はタブ区切りで、1 行目の列が種別です。`repo`（リポジトリ・base・呼び出し元・
fetch / gh の状態）、`row`（作業単位ごとに Issue / PR / branch / worktree / agent / state /
next / reason）、`state` と `srow`（`DONE` の無い run ファイルの見出しと表の行をそのまま）、
`note`、`summary`。4 つの情報源はブランチ名で結合し、Issue 番号は PR の
`closingIssuesReferences` → ブランチ名の `<N>-` 接頭辞 → run ファイルの表、の順に引きます。

`next` は上から最初に当たった行で決めます:

| 観測 | next |
| --- | --- |
| git が追跡していない worktree ディレクトリ | `/worktree-sweep` |
| worktree lock の pid が生きている／pid の無い lock | `wait` |
| PR が draft | `wait` |
| `CONFLICTING` / `DIRTY`、checks 失敗、`CHANGES_REQUESTED` | `/pr-fix N` |
| checks 実行中、mergeable 未計算 | `wait` |
| `APPROVED` で checks が緑か無し | `/pr-land N` |
| `REVIEW_REQUIRED`、または未レビューで checks が緑か無し | `/pr-review N` |
| `BLOCKED` | `wait` |
| PR 無し、worktree に未コミット変更、直近 60 分に更新 | `wait` |
| PR 無し、未コミット変更、run ファイルに載っている | `/ship-issues --resume` |
| PR 無し、未コミット変更 | `/pr-ready (in <worktree>)` |
| PR 無し、base より先のコミットあり、run ファイルに載っている | `/ship-issues --resume` |
| PR 無し、base より先のコミットあり | `/pr-ready` |
| PR 無し、空の worktree（直近更新あり／なし） | `wait` ／ `/worktree-sweep` |
| ブランチが base にマージ済み、または upstream が消えた | `/worktree-sweep` |
| run ファイルの Issue にマージ済み PR がある | `-`（完了。ファイルに `DONE` が無いだけ） |
| run ファイルの Issue にローカルにも GitHub にも痕跡が無い | `/ship-issues --resume` |

- 「先のコミット」は `origin/<base>` と ローカル `<base>` の両方に無いコミットで数える。
  未 push の main から切ったブランチが「PR の無い作業」に見えないようにするため。
  main 自体が未 push なら `note` で知らせる
- Agent の生存判定はヒューリスティック。確定するのは worktree lock の pid が生きて
  いること（`alive:<pid>`）だけで、`recent:<5m` のような直近更新、ブランチ、PR、
  run ファイルの記載はヒント。別セッションのバックグラウンド Agent task はここからは
  見えない。この限界はスクリプトが毎回 `note` に出し、スキルも回答に含める
- run ファイルは `DONE` の有無と見出し 5 行だけを読み、表は生の行を `srow` で流す。
  run ごとに列構成が違うので構造解析はしない。「どこまで進んだか」はモデルが読み、
  事実は git / gh の列で見る
- `gh` が無い・未認証・remote 無しでも止まらない。PR 系の列を `?` にしてローカル
  信号だけで判定し、`repo` 行の `gh` に理由を出す
- 他リポジトリの未完 run はファイル名を `note` に並べるだけ

run ファイルの書式は `ship-issues` 側で
[skills/ship-issues/state-file.md](skills/ship-issues/state-file.md) に固定してあります。
このスクリプトが読むのは `- repository:` / `- started:` / `- options:` / `- requested issues:`
の見出し行、`| #N |` で始まる表の行、`DONE` で始まる行だけです。

## スキル定義の整合を検査する

スキルは 17 本あり、frontmatter の形、`skills/README.md` の表、`~/.claude/skills/...` /
`~/.claude/scripts/...` のパス参照、「SKILL.md は英語で書く」という規則で互いに縛られて
います。どれも機械が強制していないので、1 本を直すと別の場所が黙ってずれます。
`scripts/skill-lint.sh` はそのずれを一覧にします。スキルではなくスクリプトだけです。
スキルを書き換えるセッションで直接叩けば足りるためです。

```bash
sh dot_claude/scripts/executable_skill-lint.sh dot_claude/skills
```

引数は skills ディレクトリで、既定は `~/.claude/skills`（配置後）。リポジトリ内では
`dot_claude/skills` を渡します。パス参照は `dot_claude/` 配下に読み替え、スクリプトの
`executable_` 接頭辞も吸収します。

検査項目:

- `SKILL.md` の frontmatter が `---` で始まり、`name` がディレクトリ名と一致し、`description`
  があり、`cm` 以外は `disable-model-invocation: true` を持つ
- `argument-hint` の `--flag` / `-X` が README 表の「引数」列にすべて載っていて、逆も成り立つ
- スキル配下の `*.md` にある `~/.claude/skills/...` / `~/.claude/scripts/...` が実在する
- `SKILL.md` の本文（frontmatter 以降）に日本語が無い（`worker-prompt.md` などの付随ファイルは
  対象外。日本語で書くものがあるため）
- README の表にすべてのスキルの行があり、ディレクトリの無い行が無く、`## <name>` 節がある

違反は `file:line: message` で出し、1 件でもあれば終了コード 1 です。

## 注意

- `dot_claude/` 配下に `exact_` プレフィックスを付けないこと。
  `~/.claude` の会話ログや認証情報が消えます。
- `~/.claude/settings.json` に `chezmoi re-add` / `chezmoi add` を使わないこと。
  Claude Code が生成した `autoMode.environment`（自宅 LAN の IP や private リポジトリの構成、
  秘密情報の置き場所を含む）やマシン固有の絶対パスがそのままリポジトリに入ります。
  設定を変えるときは `.chezmoitemplates/claude/settings.json` を編集して `chezmoi apply`
  （[settings.json はキー単位でマージする](#settingsjson-はキー単位でマージする)）。
