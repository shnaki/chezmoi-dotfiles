# スキル

`~/.claude/skills/*/SKILL.md` に配置される、全プロジェクト共通のスキルです。

| スキル | 内容 | 引数 | 起動 |
| --- | --- | --- | --- |
| [`cm`](#cm) | Conventional Commits でコミットする | コミットメッセージまたは変更の説明 | `/cm`（モデルからの自動起動も可） |
| [`triage-notes`](#triage-notes) | メモを調査して GitHub Issue を起票する | `--dry-run`（任意）+ メモのファイルまたはテキスト | `/triage-notes` のみ |
| [`issue-refine`](#issue-refine) | 既存 Issue を調査して実装可能な本文に書き換える | `--dry-run` / `--split`（任意）+ Issue 番号の並び | `/issue-refine` のみ |
| [`ship-issues`](#ship-issues) | 既存 Issue 群を並列ワーカーに割って PR 化する | Issue 番号の並び + `--merge` / `--ignore-checks` / `--dry-run` / `--resume` / `--no-merge` / `--worker-model <alias>`（任意） | `/ship-issues` のみ |
| [`issue-pr`](#issue-pr) | Issue 1 件を PR 1 件として実装する | Issue 番号 + `--merge` / `--ignore-checks`（任意） | `/issue-pr` のみ |
| [`pr-ready`](#pr-ready) | 現在ブランチの作業を diff 確認 → 検証 → コミット → PR にする | Issue 番号 + `--merge` / `--ignore-checks`（任意） | `/pr-ready` のみ |
| [`ship-notes`](#ship-notes) | メモ → Issue → PR を通しで回す | `--merge` / `--ignore-checks` / `--worker-model <alias>`（任意）+ メモのファイルまたはテキスト | `/ship-notes` のみ |
| [`pr-review`](#pr-review) | PR を独立した立場でレビューする | PR 番号 + `--post`（任意） | `/pr-review` のみ |
| [`ci-review`](#ci-review) | 落ちた CI のログを読み、pr-caused / pre-existing / flaky / infrastructure（billing 含む）/ ci-definition / needs investigation に分類する（読むだけ） | PR 番号 / `--run <id>` / `--branch <name>` + `--workflow` / `-R owner/repo`（任意） | `/ci-review` のみ |
| [`pr-fix`](#pr-fix) | レビュー指摘・conflict・checks 失敗を PR ブランチに反映して push する | PR 番号 + `--checks-only` / 指摘（任意） | `/pr-fix` のみ |
| [`pr-land`](#pr-land) | 準備の整った PR をマージして後始末する | PR 番号 + `--keep-branch` / `--ignore-checks`（任意） | `/pr-land` のみ |
| [`pr-describe`](#pr-describe) | 既存 PR の本文を diff とコミットから書き直す（人手の記述は残す） | PR 番号 + `--dry-run`（任意） | `/pr-describe` のみ |
| [`pr-respond`](#pr-respond) | pr-fix の fix / decline をレビュアーへ 1 本のコメントで返す | PR 番号 + `--dry-run`（任意） | `/pr-respond` のみ |
| [`worktree-sweep`](#worktree-sweep) | 残った worktree と不要ブランチを掃除する | スクリプトへ渡すオプション: `--dry-run` / `--recursive` / `--no-fetch` / `--force` / PATH（任意） | `/worktree-sweep` のみ |
| [`label-sync`](#label-sync) | 既定のラベルセットをリポジトリに流し込む | `--dry-run` / `--prune` / `--forge <github か gitlab>` / `-R owner/repo`（任意） | `/label-sync` のみ |
| [`label-apply`](#label-apply) | 既存の Issue / PR にラベルを付け直す | `--dry-run` / `--issues` / `--prs` / `--all` / `--limit N` / 番号（任意） | `/label-apply` のみ |
| [`work-status`](#work-status) | 進行中の PR / worktree / ship-issues run を一覧し、次に叩くコマンドを出す（読むだけ） | `--no-fetch` / PATH（任意） | `/work-status` のみ |
| [`backlog-review`](#backlog-review) | open Issue 群を調査して ready / in progress / blocked / duplicate 等に分類する（読むだけ） | `--limit` / `--label` / `--milestone` / `--since` / `-R` / 番号（任意） | `/backlog-review` のみ |
| [`backlog-apply`](#backlog-apply) | backlog-review の分類を GitHub に反映する（close / 質問コメント / status ラベル） | `--dry-run`（任意）+ Issue 番号（任意） | `/backlog-apply` のみ |
| [`handoff`](#handoff) | 作業の引継ぎ文書を書く / 読んで再開する | `--resume [file]`（任意）+ メモ | `/handoff` のみ |
| [`release-cut`](#release-cut) | 前回リリース以降のマージ済み PR から版と release notes を起こし、GitHub release を作る | `--dry-run` / `--tag <version>` / `--draft` / `-R owner/repo`（任意） | `/release-cut` のみ |
| [`repo-init`](#repo-init) | git init と空の初期コミットでローカルリポジトリを作る | パス（任意） | `/repo-init` のみ |
| [`repo-bootstrap`](#repo-bootstrap) | ラベルセット・PR / Issue テンプレート・CLAUDE.md 雛形を無いものだけ足す | `--dry-run` / `-R owner/repo`（任意） | `/repo-bootstrap` のみ |
| [`repo-cli`](#repo-cli) | 自然言語の指示を gh / glab コマンドに変換して実行する（既定は読み取り専用） | `--write`（任意）+ 自然言語の指示 | `/repo-cli` のみ |

`cm` 以外の 23 は `disable-model-invocation: true` を持ち、スラッシュコマンドからしか
起動しません。`cm` だけは `user-invocable: true` で、コミット時にモデルからも選ばれます。

定義同士の整合（frontmatter、argument-hint とこの表、`~/.claude/...` のパス参照、SKILL.md が
英語であること）は `scripts/skill-lint.sh` で機械チェックします
（[../README.md](../README.md#スキル定義の整合を検査する)）。この README は `.chezmoiignore` で
配置されないので、lint は **リポジトリのソースに対してだけ**動きます。スキルを足したり引数を
変えたりしたら `sh dot_claude/scripts/executable_skill-lint.sh dot_claude/skills` を通してから
コミットします。

## スキル間の関係

責務を段階で分け、上位のスキルは下位のワークフローを呼ぶだけにしています。

```
メモ ──/triage-notes──> Issue 群
粗い Issue ─/issue-refine─> 実装可能な Issue   （--split で子 Issue に分割起票）
Issue 群 ─/ship-issues─> 依存分析 → ウェーブ → ワーカー → PR 群
Issue ───/issue-pr───> PR                 （ship-issues のワーカーが踏襲する単位）
ブランチ上の作業 ─/pr-ready─> PR          （Issue なしでも可。cm のコミット規約を内包）

PR ─/pr-review─> 指摘 ─/pr-fix─> 修正を push ─/pr-respond─> fix / decline を 1 コメントで返信 ─/pr-land─> マージ + 掃除
     （--post で PR コメントに残す）（conflict / checks 失敗も pr-fix が直す）
                              └─本文が古くなったら─/pr-describe─> PR 本文を diff から書き直す

落ちた CI ─/ci-review─> check ごとに pr-caused / pre-existing / flaky / infrastructure / ci-definition / needs investigation（読むだけ）
                        ──pr-caused──> /pr-fix N --checks-only
                        ──pre-existing / ci-definition──> /triage-notes で Issue 化
                        ──flaky──> gh run rerun <id> --failed の案（実行はしない）
                        ──infrastructure (billing)──> /pr-land N --ignore-checks の案（Actions が使えないとき）

/ship-notes = /triage-notes → /ship-issues を繋ぐだけ
/ship-issues --merge / /issue-pr --merge / /pr-ready --merge ──> PR 作成後に /pr-land を続けて回す
                                                                （--ignore-checks はそのまま pr-land へ）
/triage-notes --dry-run / /ship-issues --dry-run ──> 起票 / ウェーブ計画だけ見て止まる

マージ済み PR 群 ─/release-cut─> 版の提案 + release notes ─> gh release create（--dry-run で提案だけ）

/ship-issues ──最終ステップ──> /worktree-sweep 相当の掃除
/pr-land     ──最終ステップ──> 同上
/worktree-sweep                            （単体でも任意のタイミングで叩ける）

/label-sync ──> リポジトリのラベルを既定セットに揃える ──> /label-apply で既存 Issue / PR に付け直す
/triage-notes /issue-pr /pr-ready ──起票・PR 作成時──> label-apply/labeling-rules.md の規則で
                                                        既存ラベルから選んで付ける（作らない）

/work-status ──> いま何が動いていて次に何を叩くかを一覧（読むだけ）
                 ──> /pr-fix /ci-review /pr-review /pr-land /pr-ready /ship-issues --resume /worktree-sweep へ案内

open Issue 群 ─/backlog-review─> ready / in progress / blocked / duplicate … に分類（読むだけ）
                                 ──ready の番号──> /ship-issues、ラベルの食い違い──> /label-apply
                                 ──needs investigation の番号──> /issue-refine
                                 ──in progress の PR 番号──> /pr-review / /pr-land
                                 ──duplicate / obsolete / already implemented / needs-info / blocked──> /backlog-apply
                                                                                    （close・質問コメント・status ラベル）

新規ディレクトリ ─/repo-init─> ローカルリポジトリ（空の Initial commit のみ）
新規リポジトリ ─/repo-bootstrap─> label-sync + PR / Issue テンプレート + CLAUDE.md 雛形（無いものだけ）─> /pr-ready

任意の作業 ─/handoff─> ~/.claude/handoff/<repo>-<日時>.md（+ .patch）
                       ─/handoff --resume─> 別セッション / 別エージェントで実状を照合して続き
```

- 起票だけしたいときは `/triage-notes`。既に Issue があるなら `/ship-issues` に
  番号を渡します。メモから PR まで一息に回すときだけ `/ship-notes` を使います。
- 既にある Issue が粗くて実装に入れないときは `/issue-refine`。コードと突き合わせて
  本文を実装可能な構成に書き換えます（実装はしない）。`ship-issues` / `backlog-review` が
  needs investigation とした Issue の受け皿で、`--split` を付けたときだけ子 Issue を起票します。
- ワーカーは `ship-issues` が起こします。Issue ごとに Agent tool で
  `isolation: "worktree"` のワーカーを1つ立て、`issue-pr` のワークフローを踏襲させます。
  オーケストレータ本体では実装しません。
- Issue から始めるなら `/issue-pr`、手元で書き終えた作業を PR にするなら `/pr-ready`。
  `pr-ready` は実装をせず、既にブランチにある変更を確認・検証・コミットして PR にするだけです。
- `pr-review` → `pr-fix` → `pr-land` が PR 作成後の一直線です。`pr-review` は読むだけ
  （`--post` で結果を PR コメントに残せる。自分の PR には approve できないので COMMENT 固定）、
  `pr-fix` は直して push するだけ、マージするのは `pr-land` だけ、と工程を分けています。
  `work-status` が conflict / `CHANGES_REQUESTED` を `/pr-fix N` に案内するので、`pr-fix` は
  レビュー指摘だけでなく base との conflict 解消（`git merge origin/<base>`、rebase はしない）と
  CI 失敗の修正も引き受けます。
- CI が落ちた原因を先に切り分けたいときは `/ci-review`。PR 番号のほか `--run <id>` /
  `--branch <name>` で main の失敗や scheduled workflow も対象にでき、落ちた check ごとに
  pr-caused / pre-existing / flaky / infrastructure / ci-definition / needs investigation のどれかを
  付けて次のコマンドを出します。読むだけで、rerun もしません。同じ会話で続けて
  `/pr-fix N --checks-only` を叩くと、`pr-fix` はその分類を引き継いで pr-caused だけ直します
  （レビュー指摘は集めない）。`work-status` は checks 失敗をまず `/ci-review N` に案内します。
- `pr-land` は checks を待ってから `mergeStateStatus` を判定します。required checks が走っている
  間は GitHub が `BLOCKED` を返すため、先に判定すると PR 作成直後に必ず止まるからです。checks が
  緑でも `BLOCKED` なら branch protection（required review）で、承認は GitHub 側の作業です。
- `worktree-sweep` は `ship-issues` が残す worktree とブランチの後始末です。
  `ship-issues` と `pr-land` が最終ステップで同じスクリプトを呼ぶため、通常は手で叩く
  必要はありません。
- ラベルは `label-sync` がリポジトリに語彙を用意し、`label-apply` が既存の Issue / PR に
  付け直します。新規に起票・作成する側（`triage-notes` / `issue-pr` / `pr-ready`）は
  同じ規則ファイルを読んで、**そのリポジトリに既にあるラベルから**選びます。既定セットを
  入れていないリポジトリでは `bug` / `enhancement` など既存の語彙に合わせ、ラベルは
  作りません。
- `work-status` は上のどれにも介入しない読み取り専用の一覧です。`ship-issues` が数時間
  走っている最中や中断後に、open PR・agent worktree・未完の run を横断して「次に叩く
  スキル」を行ごとに出します。自分では何も実行しません。
- `backlog-review` は `ship-issues` に渡す番号を選ぶ前段です。open Issue を読んで
  ready / already implemented / in progress / blocked / duplicate / obsolete / needs-info /
  needs investigation に分類し、`/ship-issues <ready の番号>` / `/issue-refine <needs investigation の番号>` /
  `/label-apply <食い違いの番号>` / `/pr-review <in progress の PR>` の案を出します。
  GitHub 側は一切変更しません（ラベルも close もコメントもしない）。
- `release-cut` は `pr-land` の先にある工程です。前回リリース以降にマージされた PR と
  Conventional Commits から次の版（major / minor / patch）と release notes を起こし、
  `gh release create` でタグごと作ります。コードにも `CHANGELOG.md` にも触りません。
- `backlog-apply` は `backlog-review` の書き込み側です。同じ会話の分類だけを入力に、duplicate /
  obsolete / already implemented を理由コメント付きで close し、needs-info には質問コメントと
  ラベル、blocked にはラベルを付けます。自分では分類せず、ready / in progress / needs
  investigation には触りません。
- `pr-describe` は PR 本文を diff・コミット・Issue から書き直します。`pr-fix` で本文が古くなった
  ときや手で作った PR 向けで、人手のチェックリストや注記は残し、タイトルは提案だけ。
  `pr-respond` は同じ会話の `pr-fix` の fix / decline をレビュアーへ 1 本のコメントで返します。
  インライン返信と thread の resolve は `gh api` の write なのでしません。
- `repo-bootstrap` は新しいリポジトリを他のスキルの前提に合わせます。`label-sync.sh`、PR / Issue
  テンプレート（`pr-ready` / `triage-notes` が書く節構成）、`CLAUDE.md` 雛形を**無いものだけ**
  足して 1 コミットにし、branch protection や Actions の設定は人向けの一覧にします。
- `handoff` はどのワークフローにも属さない横断ツールです。長い作業を別セッション
  （クラッシュ後・コンテキスト圧縮後・翌日）や別エージェント（Agent tool のワーカー、Codex）に
  渡すとき、会話の外に「文書 1 枚 + 未コミット差分の patch」を残します。リポジトリの状態は
  変えません。受け取り側は `--resume` で読み、鵜呑みにせず `git` / `gh` で照合してから続けます。

Issue の設計と実装は必ず別フェーズに分け、**1 Issue = 1 PR、1 ワーカー = 1 Issue** を守ります。

**PR をマージするのは `pr-land` だけです。** `ship-issues` と `issue-pr` は `--merge` を
付けたときに `pr-land` のワークフローを続けて回すだけで、自前ではマージしません。
ワーカーは `--merge` の有無にかかわらずマージしません。

## Actions が使えないリポジトリ

private リポジトリで GitHub Actions の無料枠が尽きると、以降の run は job が起動せず全て失敗に
なります（annotation は `The job was not started because recent account payments have failed
or your spending limit needs to be increased`、`gh run view --log-failed` は `log not found`、
`gh pr checks` は普通の `FAILURE`）。リポジトリ側で Actions を無効にすると checks は 1 件も
付かず、`gh pr checks` は `No checks reported on the '<branch>' branch` を exit 1 で返します。
どちらもコードの良し悪しとは無関係なので、checks に依存する工程は次のように扱います。

| 状態 | `ci-review` | `pr-fix` | `pr-land` | `work-status` |
| --- | --- | --- | --- | --- |
| Actions 無効 / workflow 無し（checks 0 件） | `no checks: Actions disabled or no workflows` と報告して終了 | source 5 が空 | `checks: none` と記録して続行 | `checks` 列 `none`。`wait` にも `/ci-review` にもならない |
| 無料枠切れ（全 job が起動前に失敗） | `infrastructure` に `billing: job not started (spending limit)` の evidence を付け、`/pr-land N --ignore-checks` を案内 | billing 行を decline し `/pr-land N --ignore-checks` を報告に載せる | 既定は止まり `checks failed: billing` と報告。`--ignore-checks` を付けたときだけ checks を無視してマージ | `checks` 列 `fail` → `/ci-review N` |

`--ignore-checks` は `pr-land` の他、`--merge` と一緒に `issue-pr` / `pr-ready` / `ship-issues` /
`ship-notes` に付けられ、そのまま `pr-land` に渡ります。required checks が失敗しているときは
GitHub 側がマージを拒む（`BLOCKED`）ので、このオプションで branch protection は越えられません。
自動判定で通すことはせず、billing 起因かどうかは `pr-land` の報告（または `/ci-review`）で
確かめてから人が付けます。`gh pr checks` の exit code（失敗 1 / pending 8 / checks 無し 1）は
結果を表すだけで、どのスキルもエラー扱いしません。

## スキル同士の呼び出し方

`cm` 以外は `disable-model-invocation: true` なので、**別のスキルやサブエージェントから
Skill tool で呼ぶことはできません**（モデルが選択できない設定のため）。スキルが他のスキルの
手順に従う箇所では、`~/.claude/skills/<name>/SKILL.md` をパスで読ませています。

- `ship-notes` → `triage-notes/SKILL.md` と `ship-issues/SKILL.md`
- `ship-issues` のワーカー → `issue-pr/SKILL.md`（`ship-issues/worker-prompt.md` の雛形経由）
- `ship-issues` の state file → `ship-issues/state-file.md`（`work-status.sh` が読める書式）
- `ship-issues --merge` / `issue-pr --merge` / `pr-ready --merge` → `pr-land/SKILL.md`
- `label-apply` / `triage-notes` / `issue-refine` / `issue-pr` / `pr-ready` / `backlog-review` / `backlog-apply` / `pr-describe` → `label-apply/labeling-rules.md`
- `repo-bootstrap` → `scripts/label-sync.sh`（`label-sync` と同じスクリプト）
- `backlog-apply` / `pr-respond` は同じ会話の `backlog-review` / `pr-fix` の**出力**を入力にする（ファイル参照ではなく、会話に結果が無ければ止まる）

このため Codex 側（Import 先は `~/.agents/skills`）では、これらのパス参照が解決しません。

## 前提ツール

全スキルは `git` と、リポジトリのホスティング先に応じた CLI —— GitHub なら GitHub CLI
（`gh`）、GitLab なら GitLab CLI（`glab`）—— がインストール・認証済みであることを前提に
しています。Issue / PR の読み取り・検索・作成は **すべてその CLI に統一**し、各 SKILL.md
にもその旨を明記しています。CLI が無い、または未認証なら、スキルは別の手段に逃げず止まって
報告します。どちらを使うかは `scripts/forge-detect.sh` が `origin` のホストから決めます
（[GitLab で使う](#gitlab-で使う)）。

`settings.json` で有効にしている GitHub プラグイン（`github@claude-plugins-official`、
GitHub MCP）はスキルからは使いません。対話中に Issue を検索したいといった用途のために
残してあるだけです。CLI に寄せる理由:

- Codex 側の前提（`git` + `gh`、後述）と揃う。MCP は Codex に届く保証がない
- 経路が 1 本なら、環境によってモデルが選ぶツールが変わって挙動がブレることがない
- `worktree-sweep.sh` が既に `gh pr list` / `glab mr list` に依存している

読み取り系の `gh` / `glab` サブコマンドと `git commit`（ローカルに閉じるため）は
`settings.json` の `permissions.allow` で許可し、書き込み系（`create` / `edit` / `close` /
`merge`）は都度確認のままにしています。`gh api` は GET も allow に入れておらず、`pr-fix` /
`pr-respond` がインラインのレビューコメントを読む 1 箇所だけが例外で、そこは毎回確認が入る
前提です。`glab api` は `glab api -X GET` と書いた形だけを allow に入れています（glab は
gh より JSON 出力の範囲が狭く、MR が閉じる Issue・approvals・discussion の取得は REST を
読むしかないため）。書き込みの `api` はどちらも禁止です
（[../README.md](../README.md#gh-の読み取り系と-git-commit-を許可している)）。

## GitLab で使う

スキル本文は `gh` のコマンドで書いてあり、GitLab では **同じ手順を `glab` に読み替えて**
実行します。GitHub 版と GitLab 版を別スキルにはしていません（22 スキルのロジックが二重に
なり、直すたびに両方を触ることになるため）。仕組みは 3 つだけです。

1. `scripts/forge-detect.sh` —— 各スキルが最初に 1 回だけ実行します。`origin` のホストが
   `github.com` なら `github`、それ以外で `glab auth status --hostname <host>` が通れば
   `gitlab`、`gh auth status -h <host>` が通れば `github`（GHES）。出力は
   `<forge>\t<host>\t<path>` の 1 行で、`<path>` は `owner/repo`（GitLab ではサブグループ込みの
   `group/sub/project`）。どれも通らなければ理由を出して exit 1 し、スキルは止まります。
   従来各スキルがやっていた `gh auth status` + `gh repo view --json nameWithOwner` の
   代わりなので、GitHub 経路の呼び出し回数は増えません。
2. `~/.claude/forge/gitlab.md` —— スキルで使う全 `gh` コマンド（`gh pr view`、
   `gh pr checks`、`gh run view` …）ごとに、対応する `glab` コマンドと JSON フィールドの
   対応（`mergeStateStatus` → `detailed_merge_status`、`reviewDecision` → approvals、
   checks → pipeline / job、`gh run view --log-failed` → `glab ci trace` など）、GitLab に
   無いものの扱い（`gh issue close --reason` はコメント + close、draft release は無い）を
   書いた対応表です。`ci-review` は GitHub Actions 前提の作りなので、pipeline / job で
   読み替える専用の節があります。**`gitlab` と判定されたときだけ Read** するので、GitHub
   で使うときのコンテキストは増えません。
3. 各 SKILL.md の前提段落 —— 「`forge-detect.sh` を実行し、`github` なら以下の `gh` を
   そのまま、`gitlab` なら `gitlab.md` で読み替える」の 1 段落だけを差し替えてあります。
   コマンド本文は `gh` のままです。

`scripts/work-status.sh` / `worktree-sweep.sh` / `label-sync.sh` は内部で同じ判定関数を
`source` し、`glab` に分岐します（`work-status.sh` は MR の状態を GitHub と同じ列・同じ値に
正規化するので、`next` の判定表は共通）。`label-sync.sh` は GitLab では `glab label
create` / `glab label edit --label-id` / `glab label delete` を使い、グループから継承した
ラベルは編集も削除もせずその旨を報告します。

セルフホストの GitLab は `glab auth login --hostname <host>` を一度通しておきます
（API のポートが違うときは `--api-host <host>:<port>`）。`GITLAB_HOST` は使いません。

対応表の網羅性は `skill-lint.sh` が機械チェックします: スキル配下の `*.md` に現れる
`gh <cmd> <sub>` すべてに `gitlab.md` の `### gh <cmd> <sub>` 見出しがあること、逆に
使われていない見出しが無いことです。`gh` コマンドを新しく使い始めたら、`gitlab.md` に節を
足さないと lint が落ちます。

## Codex への移植性

これらのスキルは Codex の Import で `~/.agents/skills` にコピーされます
（[ルート README](../../README.md#codex-との連携)）。ただし全部が動くわけではありません。

| スキル | Codex での扱い |
| --- | --- |
| `cm` `triage-notes` `issue-refine` `issue-pr` `pr-ready` `pr-review` `ci-review` `pr-fix` `pr-respond` `pr-describe` `pr-land` `label-apply` `backlog-review` `backlog-apply` `handoff` `release-cut` `repo-cli` | `git` と `gh` にしか依存しないため概ね動く（[前提ツール](#前提ツール)）。ただし `issue-pr --merge` / `pr-ready --merge` の `pr-land` 参照と、`label-apply` 系の `labeling-rules.md` 参照は `~/.claude` のパスなので解決しない。`issue-pr` / `pr-fix` / `pr-ready` の隔離 worktree は Claude Code の EnterWorktree 前提なので、Codex では `git worktree add` を手で行う。`handoff` の `~/.claude/handoff/` は単なるディレクトリなので Codex からも読み書きできる |
| `worktree-sweep` `label-sync` `work-status` `repo-bootstrap` | `sh` / `git` / `gh`（GitLab では `glab`）にしか依存しない。`~/.claude/scripts/*.sh` と `~/.claude/forge/gitlab.md` は Import の対象外なので、Codex 側では実体が要る |
| `ship-issues` `ship-notes` | Claude Code の Agent tool と `isolation: "worktree"` が前提。Codex には対応機能が無いため動かない |

Codex が読む frontmatter は `name` と `description` だけです。
`user-invocable` / `disable-model-invocation` / `argument-hint` は無視され、
起動は `$<スキル名>` のメンションになります。`$ARGUMENTS` の展開もありません。

**スキルは Claude Code の仕様に合わせて書き、Codex 向けの分岐は入れません。**

## cm

現在の変更を Conventional Commits 形式でコミットします。

- 変更を論理的なテーマでグループ分けし、単一テーマなら確認なしでそのままコミット、
  分割が必要／意図が不明な場合のみ確認を取る
- `git add -A` / `git add .` は使わず、対象ファイルを明示。1 ファイルに複数テーマが
  混ざる場合は hunk を選んだ patch を `git apply --cached` で stage する（`git add -p` は
  ツールのシェルでは対話できない）。本文付きのメッセージは一時ファイルから `git commit -F`
- subject / body の言語はそのリポジトリの既存コミット（`git log`）に合わせ、慣例が無ければ
  日本語。subject は句点なし、body は句点あり。「何を」ではなく「なぜ」を書く。
  リポジトリに別のコミット規約があればそちらに従う
- `co-authored-by` 相当の記述と、使用ツールへの言及は禁止

## triage-notes

雑なメモ・バグ報告・TODO を調査し、GitHub Issue として起票します。**実装はしません**
（ブランチも PR も作りません）。

- 1 メモ = 1 Issue とは限らない。複数 Issue に分割、既存 Issue に統合、重複につき起票せず、
  調査の結果アクション不要、のいずれもあり得る
- Issue 境界を決める前に必ずコードを読み、既存の Issue / PR を検索して重複を避ける
- 判断基準は「独立してマージできるか」「独立した価値／観測可能な不具合か」
  「独自の受け入れ条件を書けるか」「独立して検証できるか」
- 技術レイヤーが違うだけで分割しない。1 つの振る舞いに DB・API・フロント・テストが
  すべて必要なら、それで 1 Issue
- Issue 本文は Problem / Expected behavior / Acceptance criteria / Scope / Out of scope /
  Investigation notes の構成。Investigation notes は参考情報であって実装指示ではない
- ラベルは [`label-apply/labeling-rules.md`](label-apply/labeling-rules.md) の規則で、
  リポジトリに既にあるものから type（と根拠のある status）を `--label` で付ける。作らない
- 起票前に依存関係を分析して実行ウェーブに分類し、計画表（行 / タイトル / ラベル / 元メモ /
  依存）と本文案を出す。`--dry-run` はそこで止まる。本文はリポジトリ外の一時ファイルに書いて
  `gh issue create --body-file`。言語はリポジトリの既存 Issue に合わせる
- 起票後にウェーブを実番号で言い直す

## issue-refine

既存の Issue をリポジトリと突き合わせて調査し、実装ワーカーが本文だけで着手できる品質に
**本文を書き換えます**。**実装はしません**（ブランチも PR も作りません）。
スキルを叩いたこと自体が書き換えの承認で、適用前に再確認は取りません（`--dry-run` を除く）。

- 引数は Issue 番号の並び（`31` / `#31` / URL、空白・カンマ区切り）。無引数では動かない
  （既定で全 open を触らない）。1 件ずつ独立に処理し、1 件の失敗で残りを止めない
- 着手前に既存 PR（`closingIssuesReferences` → `Closes #N` → `<N>-` ブランチ名の順で照合）/
  重複 Issue を検索し、refinable / already implemented / in progress / duplicate / obsolete /
  blocked に判定する。refinable・in progress・blocked だけ本文を書き換え、他は報告のみ
  （close も新規起票もしない）。`ship-issues` / `backlog-review` の needs investigation はここで
  verdict を付け直す
- コードを読んで現状挙動・原因候補・影響モジュール・テスト・依存を確認する。再現や
  根本原因は根拠なしに断言しない。言い換えるだけで情報が増えないなら書き換えず報告
- 本文は `triage-notes` と同じ Problem / Expected behavior / Acceptance criteria / Scope /
  Out of scope / Investigation notes に、必要なときだけ Dependencies / Open questions /
  Split proposal を足す。元本文の事実・例・ログ・リンクはすべて取り込み、コードと矛盾する
  記述も消さず Investigation notes で指摘する。実装方法は縛らない
- タイトルは観測可能な問題を誤って表しているときだけ変え、報告する
- 大きすぎる Issue は既定では分割案（子のタイトル・Problem・受け入れ条件）を本文と報告に
  書くだけ。`--split` を付けたときだけ子 Issue を `gh issue create` で起票し、親本文の
  Split proposal を `Split into` に置き換える。親は close しない
- 適用前に計画表（番号 / verdict / タイトル / ラベル / split）と本文案を出す。`--dry-run` は
  そこで止まる。適用は本文をリポジトリ外の一時ファイルに書いて `gh issue edit --body-file`
- ラベルは [`label-apply/labeling-rules.md`](label-apply/labeling-rules.md) の規則で、
  type が無ければ付け、open な依存があれば blocked。needs-info は規則の根拠があるときだけで、
  自分が書いた Open questions を根拠にしない
- 報告は Issue ごとの verdict / 変えた節 / ラベル / 分割 / Open questions と、Issue 間の
  依存（ウェーブ形式）、触らなかった Issue と理由

`gh issue edit` / `gh issue create` は書き込み系なので `permissions.allow` に入れておらず、
実行時に都度確認が入ります。

## ship-issues

既に起票済みの Issue 番号を複数受け取り、並列ワーカーに割り当てて PR 化する
オーケストレータです。本体では実装しません。

- 引数は `101 102 103` / `#101 #102 #103` / `101,102,103` / Issue URL のいずれの形でも受け付け、
  重複を除いた Issue リストに正規化する。指定外の Issue には手を出さない。着手前に base branch
  （`defaultBranchRef`）、state file 用のリポジトリ名（`nameWithOwner`）、検証コマンドを確定し、
  ワーカーの雛形（`worker-prompt.md`）の穴を埋める
- 着手前に各 Issue を ready / already implemented / in progress / blocked / obsolete /
  duplicate / needs investigation に分類し、既存 PR と競合する実装を起こさない。
  in progress（open PR あり）はその PR を案内し、needs investigation はワーカーを起こさず
  `/issue-refine <N>` を案内する
- ready な Issue について影響範囲（API・共有型・スキーマ・マイグレーション・生成物・
  lock ファイル・ルーティング・ビルド設定など）を見積もり、Issue 間の関係を
  independent / potentially conflicting / semantically dependent /
  ordered but independently valuable に分類する
- ファイルが重ならないことは独立性の根拠にならない。バックエンドとフロントの
  producer/consumer、マイグレーション順序、同一生成物の再生成などを見る
- 実行ウェーブを組む。並列度の最大化より安全な並列度を優先し、理由なく直列化もしない
- ウェーブ内は Agent tool で 1 呼び出し = 1 Issue、`isolation: "worktree"` 指定、
  1 メッセージでまとめて並列起動する
- ワーカーへ渡すプロンプトは [`ship-issues/worker-prompt.md`](ship-issues/worker-prompt.md)
  の雛形を埋めて作る。毎回即興で書かない
- ウェーブ完了ごとに残りを再評価する。初期計画に盲従しない
- 未マージ PR への依存は明示的に扱う。暗黙の stacked branch を作らない
- 最終出力は Pull Requests / Not implemented / Execution plan / Dependencies and conflicts /
  State file

`--merge` を付けると、ウェーブ完了ごとにそのウェーブの PR を `pr-land` の手順で
1 件ずつマージしてから次のウェーブへ進みます。`pr-land` が止めた PR は
`PR created, not merged (理由)` として記録し、残りは続行します。ワーカーはマージしません。
required review のあるリポジトリでは checks が緑でも `BLOCKED` で全件止まるので、
`--merge` は自分でマージできるリポジトリ向けです。`--ignore-checks` は `pr-land` にそのまま
渡します（Actions が使えないリポジトリ向け。`--merge` 無しでは無意味）。`--resume --no-merge`
で記録済みの `--merge` を外せます。

`--dry-run` を付けると、分類とウェーブ計画（step 6）まで進めて state file を書き、
ワーカーを起こさずに終わります。数時間走る前に計画だけ確認する用途です。

`--worker-model <alias>` を付けると、ワーカーの Agent 呼び出しに `model: "<alias>"` を
渡し、実装だけを別モデルで走らせます（`opus` / `sonnet` / `haiku` / `fable` のいずれか。
それ以外は止まって報告）。省略時は `model` を渡さず、ワーカーはセッションのモデルを
継承します。分類・依存分析・ウェーブ設計・`pr-land`・掃除はセッションのモデルのままで、
変わるのはワーカーだけです。トークンの大半は並列で長く走るワーカーが使うので、
issue-refine 済みの小さな Issue 群ならここを安いモデルに落とす効果が大きく、逆に大きい・
曖昧な Issue では `pr-fix` の手戻りで高くつくことがあります。state file の options 行に
値ごと記録され、`--resume` でコマンドラインに付け直せば上書きできます。

実行計画と Issue ごとの状態は `~/.claude/ship-issues/<repo>-<日時>.md` に書き出します。
書式は [`ship-issues/state-file.md`](ship-issues/state-file.md) のテンプレートに固定して
います。`work-status.sh` が見出し行（`- repository:` など）と `| #N |` で始まる表と `DONE`
行を parse するので、別の形で書くと `/work-status` から run が見えなくなります。
Claude Desktop のクラッシュや中断を跨いで `/ship-issues --resume` で再開するためのもので、
再開時はファイルを鵜呑みにせず `gh` と `git worktree list` で実状を取り直します。
`--resume` に付けたオプションは state file の options に追加されます。
このディレクトリはランタイム状態なので chezmoi では管理しません。

## issue-pr

Issue 番号 1 件を受け取り、PR 1 件として実装します。Issue がスコープの境界です。

- 無関係な refactoring・cleanup・formatting・rename・依存更新を PR に混ぜない。
  別の問題を見つけたら報告のみに留める
- 専用ブランチと隔離 worktree で作業する。default branch の checkout にいるなら
  EnterWorktree で `<N>-<slug>` の worktree を作り、その中で `<N>-<slug>` ブランチを切る。
  worktree 生成時のブランチにはコミットしない。ExitWorktree は呼ばない（掃除は後工程）
- 着手前に既存 PR / 同等ブランチの有無を確認し、二重実装を避ける
- 検証は影響範囲から先に流し、その後リポジトリ規定の広い検証を回す。
  既存の失敗を直すために無関係なコードを触らない
- コミット前に base branch との差分全体を見て、スコープ外の変更・デバッグコード・
  生成物の巻き込みを取り除く
- PR 本文は Summary / Why / Verification / Issue（`Closes #<number>`）の構成
- PR にはコミット type（`fix` → bug、`feat` → feature …）か Issue 側のラベルに合う type ラベルを、
  リポジトリに既にあるものから `--label` で付ける（[`labeling-rules.md`](label-apply/labeling-rules.md)）
- 引数の `#31` / Issue URL は番号に正規化する（`##31` になるのを防ぐ）
- force-push しない。マージしない。`--merge` を付けたときだけ、PR 作成後に `pr-land` の
  手順でマージする（`--ignore-checks` はそのまま `pr-land` へ渡す）

## pr-ready

現在ブランチで書き終えた作業を、diff 確認 → 検証 → コミット → push → PR 作成まで一息に
持っていきます。**実装はしません**。既にブランチにある変更が対象です。

- Issue 番号は任意引数。省略時はブランチ名（`123-foo` など）やコミットメッセージ（`#123`、
  `Github-Issue:` トレーラ）から候補を出し、Issue を読んで一致を確認できたときだけ `Closes #N`
  を付ける。確信が持てなければ閉じず、候補として報告する
- default branch 上なら、未コミット変更だけのときは新ブランチ（Issue があれば `<N>-<slug>`、
  無ければ `<slug>`）を切って続行。default branch にコミット済みのものがあれば止まって報告する
- `git status` / `git diff` / base branch との差分全体を読み、無関係な変更・デバッグコード・
  一時ファイル・生成物・lock ファイル・秘密情報・マシン固有パスを取り除く
- `pr-review` と同じ観点（correctness / scope / 規約 / テスト）で自己レビューし、明らかな欠陥は直す
- リポジトリ規定の検証を影響範囲から先に流す。無ければでっち上げない。既存の失敗は直さず記録
- 未コミット変更は `cm` の規約でコミットする
- 同ブランチの PR が既にあれば作らず報告。PR テンプレートがあればそれに従い、無ければ
  Summary / Why / Verification / Issue の構成。`gh pr create` で作る
- type ラベルは `issue-pr` と同じ規則で、リポジトリに既にあるものから付ける
- force-push しない。マージしない。`--merge` を付けたときだけ、PR 作成後に `pr-land` の
  手順でマージする（`--ignore-checks` はそのまま `pr-land` へ渡す）

## ship-notes

メモから PR までを通しで回します。実体は `triage-notes` と `ship-issues` を繋ぐだけの
薄い合成で、固有のロジックは持ちません。両者の SKILL.md をパスで読んで従います。

1. メモを `triage-notes` のワークフローで triage する
2. Issue を起票する
3. **新しく起票された actionable な Issue 番号だけ**を集める
4. それらを `ship-issues` のワークフローで処理する（`--merge` / `--ignore-checks` /
   `--worker-model <alias>` を透過。起票フェーズはセッションのモデルのまま）
5. 両者の結果と `ship-issues` の state file パスを合わせて返す

重複・obsolete・アクション不要と判断したメモは実装フェーズに渡しません。
triage フェーズでは実装せず、実装開始後に Issue 境界を都合よく書き換えることもしません。
`--merge` 無しでは PR をマージしません。`--dry-run` は受けません（`/triage-notes --dry-run` /
`/ship-issues --dry-run` を使う）。中断した run の再開は `/ship-issues --resume` です。

## pr-review

PR 番号 1 件を、実装者ではなくレビュアーの立場でレビューします。**ファイルを変更せず**、
push もマージもしません。

- 引数は `82` / `#82` / URL を番号に正規化し、無引数なら現在ブランチの PR
- PR 本文とリンク先 Issue を読み、受け入れ条件とスコープ境界を把握してから差分を見る。
  Issue の無い PR（`pr-ready` 由来）は PR 本文がスコープ境界
- 差分は base branch との全体を見る。断片だけを見ない
- 観点は correctness（誤動作・エッジケース・競合状態・データ損失・互換性）、scope
  （Issue と無関係な変更）、リポジトリ規約、テストと検証の十分さ、混入物
  （デバッグログ・一時ファイル・秘密情報・マシン固有パス）
- 報告前に周辺コードを読んで裏を取る。推測と事実を分け、スタイル上の好みを欠陥として挙げない。
  弱い指摘を並べるより、確度の高い少数を出す
- 出力は APPROVE / REQUEST CHANGES / COMMENT の判定から始め、Critical / High / Medium / Low
  の順に列挙。最後に Issue coverage / Scope / Verification assessment を述べる
- `--post` を付けたときだけ、同じ本文を `gh pr review --comment --body-file` で PR に残す。
  自分の PR には APPROVE / REQUEST_CHANGES を出せないので COMMENT 固定。別セッションの
  `pr-fix` が拾える。`reviewDecision` は変わらないので `work-status` は `/pr-review N` を出し続ける

## ci-review

落ちた GitHub Actions の check を 1 つずつ読んで、ちょうど 1 つの分類を付けます。**読むだけ**で、
rerun も cancel もコメントも commit もしません。「なぜ落ちたか」を切り分ける工程で、
直すのは `pr-fix`、Issue にするのは `triage-notes` の仕事です。

- 対象は PR 番号（既定。無指定ならカレントブランチの PR、それも無ければカレントブランチ）、
  `--run <run-id>` で run 1 件、`--branch <name>` でそのブランチの直近失敗 run（main の失敗や
  scheduled workflow）。`--workflow <name>` で絞り、`-R owner/repo` は全 `gh` 呼び出しに渡す
- 取得は `gh pr view --json` / `gh pr checks --json` / `gh run list` / `gh run view --json` /
  `gh run view --log-failed`（無ければ `gh run view` の ANNOTATIONS）/ `gh workflow list`。
  `gh api` は使わない。ログは丸ごと読まず、失敗 step の末尾と `error` / `##[error]` /
  `exit code` の行から「失敗した step・コマンド・最初のエラー・名指しされたファイルやテスト」を抜く。
  checks が 1 件も無ければ「Actions 無効か workflow 無し」と報告して終了
- base 側（PR なら `baseRefName`、それ以外は default branch）の同 workflow の直近 run を
  `gh run list --branch <base> --workflow <w>` で取り、base でも同じ step・同じエラーで落ちて
  いるかを見る。head 側の同 workflow の run も取り、同じ SHA で success した run が flaky の根拠。
  対象が default branch 自身なら直近の緑 run との間のコミットを候補にする。PR のときは失敗 step の
  対象が PR の変更ファイル（100 件超は `gh pr diff --name-only`）に含まれるかも見る
- 分類は優先順に判定し、先に当たったものを採用する:
  infrastructure（runner 起動失敗 / secrets 未設定 / rate limit / ネットワーク / **billing**
  （無料枠切れ。annotation + `log not found` + steps 空）。リポジトリ自身のコマンドに入る前に
  落ちている）→ ci-definition（`Invalid workflow file`、action が解決しない等。PR がその YAML を
  変えていれば pr-caused）→ flaky（同一 SHA の別 run が通った、または base が緑で timeout /
  外部サービス起因。「無関係に見える」だけでは flaky にしない）→ pre-existing（base の直近 run が
  同じ step・同じエラー）→ pr-caused（base は緑で、エラーが PR の変更を名指し）→
  needs investigation（決められない。何を見れば決まるかを書く）
- 出力は対象と件数 → 表（check / run / class / evidence / note）→ 行ごとの要点ログ数行 →
  次に叩くコマンド案（pr-caused の `/pr-fix <N> --checks-only`、pre-existing / ci-definition の
  `/triage-notes "<要約>"`、flaky の `gh run rerun <id> --failed`、infrastructure は人が見る箇所
  （billing なら Billing & plans と `/pr-land <N> --ignore-checks`）、needs investigation は次に見る
  1 点）。案は出すだけで実行しない。末尾に「Nothing was changed on GitHub.」を必ず書く
- `--run` / `--branch` で default branch の失敗が pr-caused でも、default branch は直さない。
  `/triage-notes` → `/issue-pr` へ案内する

## pr-fix

`pr-review` の指摘、base との conflict、checks の失敗を PR ブランチに反映して push します。
**マージしません**。GitHub へのコメント投稿もしません。

- 先に `gh pr view --json state` を読み、open でない PR には手を出さない
- 指摘の入力元は、(1) 引数の自由記述 → (2a) 同じ会話の `pr-review` 出力 / (2b) 同じ会話の
  `ci-review` 出力 → (3) GitHub 上のレビュー（`gh pr view --comments`。`pr-review --post` の
  コメントも含む。インラインは `gh api ... --paginate` の GET で、allow 外なので毎回確認）→
  (4) `mergeable=CONFLICTING` / `DIRTY`（`BEHIND` は up-to-date 必須のときだけ）→ (5) `gh pr checks`
  の失敗（`gh run view --log-failed` でログを読む。`log not found` なら ANNOTATIONS）の順。
  全部空なら止まる
- `--checks-only` を付けると 2b・4・5 だけを findings にし、レビュー指摘（1 / 2a / 3）は集めない。
  同じ会話に `ci-review` の結果があれば、pr-caused の行だけ直し、pre-existing / flaky /
  infrastructure（billing 含む）/ ci-definition の行はその根拠ごと decline として報告する
  （ログを読み直さない）。needs investigation の行は自分でログを読んで判断する。billing の
  decline には `/pr-land <N> --ignore-checks` を添える。flaky の rerun は `gh run rerun` が
  GitHub への write なので自分では叩かず、報告に載せる
- head ブランチが既に別 worktree（`ship-issues` のワーカーが残したもの）に checkout されて
  いればそこで直す。無ければ隔離 worktree（`pr-<N>`）で `gh pr checkout` する。
  default branch の checkout では直さない
- conflict は `git merge origin/<base>` で解消する。rebase は force-push になるのでしない。
  checks の失敗は base でも起きるものなら pre-existing として decline する
- 指摘は 1 件ずつ fix / decline に振り分ける。丸呑みも黙殺もしない。事実誤認、意図的な挙動、
  PR のスコープ外、リポジトリが求めないスタイル上の好みは理由付きで decline する
- 検証はリポジトリ規定に従う。既存の失敗は直さず記録する
- コミットは `cm` の規約。force-push しない

## pr-land

準備の整った PR をマージし、後始末します。**スキルを叩いたこと自体がマージの承認**で、
マージ前に再確認は取りません。ただし赤信号では必ず止まり、押し切りません。

- 止める条件: open でない / draft / `CHANGES_REQUESTED` / `gh pr checks` の失敗
  （`--ignore-checks` 無し）/ checks が緑になった後も `BLOCKED`（required review か required
  check）/ `DIRTY` / `CONFLICTING` / up-to-date 必須のリポジトリで `BEHIND` / `mergeable` が
  1 分読み直しても `UNKNOWN` / 議論に未対応の反対意見。**直さずに止めて報告する**（直すのは
  `pr-fix` の仕事。checks の失敗は 1 件 `gh run view` して billing 起因なら
  `/pr-land <N> --ignore-checks`、それ以外は `/ci-review <N>` → `/pr-fix <N> --checks-only` を案内）
- 判定順は「即止まる条件（state / draft / `CHANGES_REQUESTED`）→ `gh pr checks --watch` →
  状態を読み直して `mergeable` / `mergeStateStatus` を判定」。required checks が走っている間は
  GitHub が `BLOCKED` を返し、push 直後は `mergeable` が `UNKNOWN` になるため、checks の前に
  判定すると PR 作成直後に必ず止まる。`UNKNOWN` は最大 1 分ほど読み直す。`gh pr checks` の
  exit code はエラーではなく結果（失敗 1 / pending 8）。`No checks reported` は Actions 無効か
  workflow 無しで、`checks: none` として続行。`--watch` がツールの timeout で切れたら
  `--watch` 無しで読み直し、30 分で諦める
- マージ方式はリポジトリの慣例に従い、不明なら `--squash`。squash では `--subject` / `--body`
  を `cm` の規約（`<type>(<scope>): <subject> (#N)`）で明示し、`gh` 既定の PR タイトル +
  コミット見出し一覧にしない。既定で `--delete-branch` を付けて remote ブランチを消す。
  残したいときだけ `--keep-branch` を付ける（ローカルの後始末には影響しない）
- `gh` はローカルブランチ → remote ブランチの順に消すので、worktree で checkout 中のブランチだと
  ローカル削除で失敗して **remote が残る**。マージ済みなら停止条件にせず、`git ls-remote` で
  確かめて `git push origin --delete <branch>` で消す（詳細は SKILL.md step 5）。fork からの
  PR（`isCrossRepository`）では remote 削除に触らない
- マージ後に紐づく Issue が閉じたか確認する。閉じていなければ報告のみ（手で閉じない）
- 後始末は base branch へ切替 → `git fetch --prune` → `git pull --ff-only` →
  `worktree-sweep.sh`。カレントが agent worktree の中（`issue-pr --merge` / `pr-ready --merge`
  を EnterWorktree したセッションで回した場合）なら、`git -C <main-root>` で main checkout 側を
  更新し、いる worktree は sweeper が keep する（次の `/worktree-sweep` で消える）。
  `git` の削除コマンドは自分で叩かない
- コードは変更しない。push もしない

## worktree-sweep

`ship-issues` のワーカーが残した worktree と、不要になったローカルブランチを掃除します。
判定ロジックは全て `~/.claude/scripts/worktree-sweep.sh` にあり、スキルはそれを呼んで
結果を要約するだけです。スキル側で `git` の削除コマンドを直接叩きません。

- 引数はスクリプトへそのまま渡す。無引数ならカレントリポジトリが対象
- 削除せず残した対象は理由込みで必ず報告する。そこが人間の判断が要る箇所
- 残ったものを `--force` で押し切らない。`--force` は「直近 60 分に更新された worktree を
  スキップする」ガードを外すだけで、未コミット変更や未マージの判定には効かない
- 死んだセッションの `git worktree lock` はスクリプトが自動で外して削除まで進める。
  生きているセッションのロックと、別プロセスが掴んでいるディレクトリは keep する。
  手で `git worktree unlock` / `rm -rf` して回らず、掴んでいる側を閉じて再実行する

`ship-issues` の最終ステップからだけは `--force` 付きで呼びます（ワーカー完了直後は
必ず 60 分ガードに当たるため）。`pr-land` の後始末は既定のまま呼びます。単発の
マージ時には他のエージェントが動いている可能性があるためです。

対象の判定基準とスクリプトのオプションは [../README.md](../README.md#worktree-のゴミを掃除する)
に書いてあります。

## label-sync

既定のラベルセットをリポジトリに冪等に流し込みます。判定ロジックとラベルの定義は全て
`~/.claude/scripts/label-sync.sh` にあり、スキルはそれを呼んで結果を要約するだけです。
スキル側で `gh label` / `glab label` の書き込みを直接叩きません。

- 引数はスクリプトへそのまま渡す（`--dry-run` / `--prune` / `--forge github|gitlab` /
  `-R owner/repo`）。`--forge` は `-R` で別フォージのリポジトリを指すときだけ要る
- GitHub 既定の `bug` / `enhancement` / `documentation` / `question` / `duplicate` / `wontfix`
  は rename で取り込み、付与済みの Issue からラベルが外れないようにする（GitLab の新規
  プロジェクトには既定ラベルが無いので、そのときは単に create になる）
- GitLab でグループから継承したラベルは編集も削除もできないので、差があっても `keep` /
  `retain` としてその旨を報告する
- セット外のラベルは `unmanaged` として報告するだけ。`--prune` 時のみ、1 件も付いていない
  ものを消す
- rename 元が複数あるときは表の先頭のものだけ rename し、残りは `superseded` として
  報告する。統合は `label-apply` で付け替えてから `--prune`

ラベルセット（19 個）。`type/*` は `cm` の Conventional Commits type から一意に決まる
多対一の対応で（`fix` → bug、`feat` → feature、`docs` / `refactor` / `perf` / `test` は同名、
`chore` / `ci` / `build` / `style` は chore、`revert` は元の変更の type）、ちょうど 1 つ付ける。
逆向きは一意ではない（`type/chore` から commit type は決まらない）。
`priority/*` と `status/*` は最大 1 つ。

| ラベル | 意味 | rename 元 |
| --- | --- | --- |
| `type/bug` | 想定どおり動かない | `bug` |
| `type/feature` | 新機能・既存挙動の拡張（`feat`） | `enhancement` `feature` |
| `type/refactor` | 挙動を変えない内部整理 | `refactor` `refactoring` |
| `type/perf` | 性能改善 | `perf` `performance` |
| `type/docs` | ドキュメントのみ | `documentation` `docs` |
| `type/test` | テストの追加・修正のみ | `test` `tests` |
| `type/chore` | 保守・ツール・ビルド・CI・依存の整理（commit type の `chore` / `ci` / `build` / `style` をまとめる） | `chore` `ci` `build` |
| `priority/high` `priority/medium` `priority/low` | 優先度。本文に明示があるときだけ付ける | — |
| `status/blocked` | 他の Issue / PR / 外部要因待ち | `blocked` |
| `status/needs-info` | 報告者からの情報待ち | `question` `needs-info` |
| `status/duplicate` | 別の Issue / PR で追跡済み | `duplicate` |
| `status/wontfix` | 対応しないと決めた | `wontfix` |
| `dependencies` | Dependabot / Renovate の依存更新 | — |
| `security` | 脆弱性修正・堅牢化 | — |
| `breaking-change` | 互換性を壊す変更（`feat!:` / `BREAKING CHANGE:`） | `breaking` `breaking change` |
| `good first issue` `help wanted` | GitHub 既定のまま。自動では付け外ししない | — |

`invalid` はセットに含めていません（`unmanaged` として残り、`--prune` で未使用なら消える）。

## label-apply

既存の Issue / PR を読み直し、**リポジトリに既にあるラベルの中から**適切なものを付け直します。
ラベルは作りません。判断規則は [`label-apply/labeling-rules.md`](label-apply/labeling-rules.md)
にあり、`triage-notes` / `issue-pr` / `pr-ready` も同じファイルを読みます。

- 既定は open な Issue と PR を各 200 件まで（`--limit N`）。`--issues` / `--prs` で絞り、
  `--all` で closed も含める。番号や URL を渡せばその項目だけ
- 語彙は `gh label list` から解決する。既定セット（`type/*` …）が無いリポジトリでは
  `bug` / `enhancement` / `documentation` などの既存の語彙に対応付ける。type 系のラベルが
  1 つも無ければ止めて `/label-sync` を案内する
- type は PR タイトル／コミットの Conventional Commits prefix → 紐づく Issue のラベル →
  本文の順で決め、ちょうど 1 つにする。priority と status は本文に明示的な根拠があるときだけ
- 管理外のラベル（`area/*` など）には触らない。管理カテゴリでも根拠なく外さない。
  迷ったら付けず、undecided として理由付きで報告する
- 適用前に計画表（番号 / 現状 / 追加 / 削除 / 根拠）を出す。`--dry-run` はそこで止まる。
  Issue は同じ変更ごとに `gh issue edit N1 N2 ... --add-label --remove-label` でまとめて
  適用し、PR は `gh pr edit` を 1 件ずつ
- type ラベルを 10 件超から外す、または 100 件超を触るときだけ、適用前に一度確認する

## work-status

カレントリポジトリで「いま何が動いていて、次に何を叩くか」を一覧します。読むだけで、
何も変更しません。判定は全て `~/.claude/scripts/work-status.sh` にあり、スキルは出力を
表に整形して限界を添えるだけです。

- 対象は repo 全体。open PR（`gh pr list`、GitLab では `glab mr list` + MR ごとの
  `glab ci get`）、agent worktree とローカルブランチ
  （`git worktree list` / `for-each-ref`）、`~/.claude/ship-issues/` の `DONE` が無い run を
  ブランチ名で結合し、1 単位 1 行にする
- 各行の `next` は `/pr-fix` / `/ci-review` / `/pr-review` / `/pr-land` / `/pr-ready` /
  `/ship-issues --resume` / `/worktree-sweep` / `wait` / `-`（完了）のどれか。判定表は
  [../README.md](../README.md#進行中の作業を一覧する) とスクリプト冒頭のコメントにある。
  checks 失敗は `/ci-review` に送る（billing / flaky を `pr-fix` に持ち込まないため）。表には
  判断根拠の `checks` / `review` 列も出す
- state file は「その Issue が ship-issues 由来か」「run の進み具合の主張」としてだけ読む。
  事実は git とフォージ CLI の列で、食い違えば表が勝つ
- Agent の生存はヒューリスティック。確定信号は worktree lock の pid が生きていることだけで、
  直近の更新・ブランチ・PR・state file はヒント。別セッションのバックグラウンド Agent は
  見えない。この限界は毎回出力に含める
- 提案したコマンドは実行しない。「やって」と言われたら呼ぶスキル名を答える
- `--no-fetch` で `git fetch --prune` を省く（唯一の副作用）

## backlog-review

open Issue 群を読んで、1 件ずつちょうど 1 つの分類に振り分けます。**読むだけ**で、
ラベル付け・close・コメント・状態変更のどれもしません。`ship-issues` に渡す番号を選ぶ前段で、
`ship-issues` step 3 の分類（ready / already implemented / in progress / blocked / obsolete /
duplicate / needs investigation）に needs-info を足した 8 分類を使います。

- 既定は open Issue を 200 件まで（`--limit`）。`--label`（複数は AND）/ `--milestone` /
  `--since <日付>`（その日以降に更新されたもの）/ `-R owner/repo` で絞る。番号や URL を
  渡せばその Issue だけ（closed でも読む）
- 取得は `gh issue list` 1 回と `gh pr list --state all` 1 回。Issue と PR の対応は
  `closingIssuesReferences` → 本文の `Closes #N` → `issue-pr` の `<N>-<slug>` ブランチ名 →
  本文の `#N` 言及の順で強い根拠から取る。`gh api` は使わない（`permissions.allow` に無く、
  タイムラインを見なくても PR 側から辿れる）
- コメントがある Issue だけ `gh issue view --comments` で読む。重複探しの `gh search issues`
  は Issue ごとに最大 1 回。コードは「既に実装済みか」「対象がまだあるか」を確かめる範囲だけ読む
- 分類は優先順に判定し、先に当たったものを採用する:
  already implemented（マージ済み PR が紐づく、またはコードが既に満たす）→ in progress
  （open な PR が紐づく。close 案は出さず `/pr-review` / `/pr-land` を案内）→ duplicate
  （残す側を名指し）→ obsolete → blocked → needs-info → needs investigation → ready。
  blocked と needs-info の定義は [`labeling-rules.md`](label-apply/labeling-rules.md) step 4
  のもの。迷ったら needs investigation にして何が足りないかを書き、推測で ready にしない
- 出力は件数サマリ → 分類ごとの表（番号 / タイトル / 根拠 / 注記）→ 既存 status ラベルとの
  食い違い一覧 → 次に叩くコマンド案（`/ship-issues <ready 番号>`、`/issue-refine <needs investigation 番号>`、
  `/label-apply <食い違い番号>`、in progress の `/pr-review <PR>`、
  duplicate / obsolete / already implemented の `gh issue close` 案）。
  案は出すだけで実行しない。
  末尾に「Nothing was changed on GitHub.」を必ず書く
- 影響範囲の見積もりやウェーブ設計はしない（`ship-issues` の仕事）。ready 同士に明白な順序
  依存があれば `after #A` と注記するに留める

## handoff

いまの作業を、会話を持たない別セッション・別エージェントが続けられる文書に落とします。
`--resume` で受け取り側にもなります。**リポジトリの状態は変えません**（commit / stash /
checkout / push をしない。記録するだけ）。

- 引数は先頭が `--resume` なら受け取りモード（残りはファイル指定、省略時はカレント
  リポジトリ名で始まる最新）。それ以外は自由記述のメモ（渡し先や追加指示）として文書に載せる
- 書き出し先は `~/.claude/handoff/<repo>-<YYYYMMDD-HHMM>.md`。未コミットの tracked 変更が
  あれば同名 `.patch`（`git diff HEAD --binary`）を隣に置く。worktree 隔離のサブエージェントや別マシン
  には未コミット差分が見えないため。untracked ファイルは patch に入らないので一覧だけ書く
- 文書は英語固定の見出し（How to resume / Goal / Constraints / Repository state / Done /
  In progress / Next steps / Decisions / Verification / Known issues / Key files）、本文は
  会話の言語。Next steps は「run X, expect Y, then edit Z」の粒度で、会話を読まずに
  最初の 1 歩を踏み出せる具体さにする
- 検証済みの事実と推測を分けて書く。秘密情報・トークン・環境変数の値、使ったツール名や
  モデル名は書かない。パスはリポジトリルート相対で、絶対パスはルートの 1 か所だけ
- `--resume` は文書を鵜呑みにせず、`git` / `gh` で実状を取り直して差異（新しいコミット、
  消えたブランチ、マージ済み PR）を先に列挙する。`.patch` は working tree がクリーンで
  HEAD が一致するときだけ `git apply --check` して**適用を提案する**。自動では当てない
- 再開後にまた渡すときは新しいファイルを書く。元のファイルは編集しない
- 最終応答はファイルパス、Next steps の先頭 3 件、受け取り側にそのまま渡す 1 行
  （`/handoff --resume <path>`、他ツール向けには `Read <path> and continue from "Next steps".`）

このディレクトリはランタイム状態なので chezmoi では管理しません（`.chezmoiignore` で除外）。

## release-cut

前回リリース以降に base branch へマージされたものから次の版と release notes を起こし、
`gh release create` で release とタグを作ります。**コードも `CHANGELOG.md` も変更しません**
（commit / push / `git tag` をしない。タグは `gh release create` に作らせる）。
スキルを叩いたこと自体が release 作成の承認で、適用前に再確認は取りません（`--dry-run` を除く）。

- 前回リリースは `gh release list` の最新の非 draft・非 prerelease、無ければ最新タグ、それも
  無ければ初回 release（root からの全履歴）。タグの接頭辞（`v` の有無）や notes の言語・見出しは
  既存の release に合わせる
- `gh pr list --state merged` を一次ソースにし、`git log <prev>..origin/<base>`（merge commit 含む）
  と突き合わせて PR に紐づかないコミットだけ個別行にする（merge commit 運用でも 1 PR 1 行）。
  取得件数が `--limit` に達したら止める。type は PR タイトルの Conventional Commits prefix →
  `type/*` ラベル → 中のコミットの prefix の順に決める
- 版は `feat!` / `BREAKING CHANGE` → major、`feat` → minor、それ以外 → patch を**提案**。
  `--tag` で上書きできる（提案も併記する）
- notes は Breaking changes / Features / Fixes / Other の節に 1 PR 1 行 `(#N)` 付きで、
  空の節は省く。末尾に compare URL。ツール痕跡は残さない
- `CHANGELOG.md` があれば追記案を報告に載せるだけで編集しない（それは PR にすべき変更）
- 適用前に前回タグ・範囲・提案タグ・節ごとの件数・notes 全文を出す。`--dry-run` はそこで止まる。
  200 件超、または既にリリース済みのタグを跨ぐ範囲のときだけ一度確認する
- タグが既にあれば止まる（`--tag` 指定分は step 1 で、提案タグは作成直前に確認）。
  `gh release create` の失敗は別タグで再試行しない
- `--draft` で下書き、`-R owner/repo` で別リポジトリ（ローカル checkout が無ければ `gh` だけで動く）

`gh release list` / `gh release view` は読み取りなので `permissions.allow` に入れてあり、
`gh release create` は都度確認です。

## backlog-apply

同じ会話の `backlog-review` の分類を GitHub に反映します。**自分では分類しません**（結果が
会話に無ければ止まって `/backlog-review` を案内）。スキルを叩いたこと自体が close とコメントの
承認で、10 件超を close するときだけ一度確認します（`--dry-run` を除く）。

- 対象は duplicate / obsolete / already implemented / needs-info / blocked だけ。ready /
  in progress（PR がマージされれば閉じる）/ needs investigation（`/issue-refine` の仕事）には触らない。
  番号を渡せばその部分集合だけ
- 適用前に 1 件ずつ読み直し、閉じていた・review 後に更新された・根拠が崩れた（重複先が閉じた、
  マージ済み PR が revert された、依存が閉じた）Issue は触らずに報告する
- 操作は already implemented → `gh issue close --reason completed` + `Implemented by #M`、
  duplicate / obsolete → `--reason "not planned"` + 理由コメント（+ status ラベル）、needs-info →
  質問コメント + needs-info ラベル、blocked → blocked ラベル。ラベルは
  [`label-apply/labeling-rules.md`](label-apply/labeling-rules.md) の語彙で status 系だけ、
  リポジトリに既にあるものから
- 適用前に計画表（番号 / class / 操作 / コメント / ラベル）を出す。`--dry-run` はそこで止まる。
  末尾に「Nothing else was changed on GitHub.」

`gh issue close` / `comment` / `edit` は書き込み系なので都度確認が入ります。

## pr-describe

既存 PR の本文を diff・コミット・リンク先 Issue から書き直します。`pr-fix` が push を重ねて本文が
古くなったとき、手で作った PR の本文が空のときに使います。**コードにも push にも触らず**、
`gh pr edit --body-file` だけです。

- 構成は PR テンプレートがあればそれ、無ければ Summary / Why / Verification / Issue。人手の
  チェックリスト・注記・`Closes #N` は残し、変更を説明する散文だけ書き直す。既に diff と一致して
  いれば何もしない
- Verification は commit / 本文にある事実と、`gh pr checks` の結果（無ければ `no checks`）だけ。
  でっち上げない。ログは読まない（`ci-review` の仕事）
- タイトルは変えない。規約に合わなければ提案だけ
- type ラベルは規則で付け直す（`gh pr edit --add-label`）。既存ラベルからだけ
- `--dry-run` は本文案で止まる。マージ済み / closed の PR は触らない

## pr-respond

同じ会話の `pr-fix` の結果（fix / decline）を、レビュアーへ **PR コメント 1 本**で返します
（`gh pr comment --body-file`）。`pr-fix` は GitHub に何も書かないので、その穴を埋めます。

- 入力は `pr-fix` の結果だけ。無ければ止まる。指摘を再判定しない
- GitHub 上の指摘（`gh pr view --comments` と、インラインは `gh api ... --paginate` の GET。
  `pr-fix` と同じ唯一の例外で毎回確認）と `pr-fix` の verdict を著者・ファイル・文言で突き合わせ、
  1 指摘 1 行で `fixed in <sha>` / `declined: <理由>` / `not ours: <ci-review の根拠>` を並べる。
  verdict の無い指摘は「not addressed」として残す
- インライン返信と thread の resolve は `gh api` の write なのでしない。レビュアーが読んで自分で
  resolve する
- `--dry-run` はコメント案で止まる。マージ済み / closed の PR には投稿しない

## repo-init

`git init` と空の初期コミット（`git commit --allow-empty -m "Initial commit"`）だけで
ローカルリポジトリを作ります。空の root commit を置くのは、最初の実コミットも含めて
後からリベース・squash できるようにするためです。

- 引数はパス（任意）。無ければカレントディレクトリ、あれば無いディレクトリも作る
- 既に git リポジトリの中なら `git init` を重ね掛けせず止まって報告する
- ブランチ名は指定せず `init.defaultBranch` の設定に従う
- 既存ファイルがあっても stage しない（コミットは `/cm` の仕事）。メッセージは
  `Initial commit` 固定で、Conventional Commits の対象外
- リモート作成・push・`gh` / `glab` は使わない。forge 側の整備は `/repo-bootstrap`

## repo-bootstrap

新しいリポジトリを他のスキルの前提に合わせます。**無いものだけ足し**、既にあるファイルは
読んで残します。GitHub の設定は変えません（`gh api` の write が要るため人向けの一覧にする）。

- 調査は `gh repo view`（default branch / visibility / merge 方式 / `deleteBranchOnMerge`）、
  `gh workflow list`（Actions の有無）、`gh label list`、ローカルの `CLAUDE.md` / `.github/` /
  `.gitignore` / 言語・ビルドツール。working tree が汚れていれば止まる
- 実施は (1) `~/.claude/scripts/label-sync.sh`、(2) `.github/PULL_REQUEST_TEMPLATE.md`
  （Summary / Why / Verification / Issue）、`.github/ISSUE_TEMPLATE/bug.md` / `feature.md`
  （Problem / Expected behavior / Acceptance criteria / Scope / Out of scope / Investigation notes、
  `labels:` に既存の type ラベル）、`CLAUDE.md` 雛形（Language / Verification / Branches）、
  (3) それらを `cm` の規約で 1 コミット。push はせず `/pr-ready` に渡す
- `.gitignore` は無ければ言語名を添えて「手で足す」と報告（GitHub のテンプレート取得は `gh api`）
- 人が設定するもの: head branch の自動削除、squash 許可、branch protection、private なら
  Actions の無料枠（billing 失敗は `infrastructure` 扱いで `/pr-land --ignore-checks`）
- `--dry-run` は計画で止まる（`label-sync.sh --dry-run` も含む）。`-R owner/repo` は `gh` と
  `label-sync.sh` に渡す。ローカルファイルはカレントがその checkout のときだけ書く

## repo-cli

自然言語の指示を `gh` / `glab` のコマンドに変換して実行します。専用スキルの無い単発の
問い合わせ（「open な PR を一覧して」「issue 82 を見せて」）の汎用の入口です。

- **既定は読み取り専用**。書き込み（create / edit / close / merge / comment、rerun 等の
  実行系、ローカルを変える checkout も含む）の指示は実行せず、叩くべきコマンドを提示して
  `--write` 付きの再実行を案内する。迷うものは書き込み側に倒す
- `--write` を付けると書き込みも実行するが、各コマンドを実行前に本文で提示して合意を
  取ってから 1 件ずつ実行する（複数の書き込みを 1 回の合意でまとめない）。読み取り系は
  どちらのモードでも確認なしで即実行
- `gh api` は読み取りでも使わない。GitLab では `gitlab.md` が許す `glab api -X GET` のみ。
  API の書き込みは `--write` があっても常に拒否
- 解釈が実質的に分かれる指示は当て推量で実行せず、候補コマンドを提示して質問する。
  実行したコマンドは必ず報告に載せる
