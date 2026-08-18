# スキル

`~/.claude/skills/*/SKILL.md` に配置される、全プロジェクト共通のスキルです。

| スキル | 内容 | 引数 | 起動 |
| --- | --- | --- | --- |
| [`cm`](#cm) | Conventional Commits でコミットする | コミットメッセージまたは変更の説明 | `/cm`（モデルからの自動起動も可） |
| [`triage-notes`](#triage-notes) | メモを調査して GitHub Issue を起票する | メモのファイルまたはテキスト | `/triage-notes` のみ |
| [`issue-refine`](#issue-refine) | 既存 Issue を調査して実装可能な本文に書き換える | Issue 番号の並び + `--dry-run` / `--split`（任意） | `/issue-refine` のみ |
| [`ship-issues`](#ship-issues) | 既存 Issue 群を並列ワーカーに割って PR 化する | Issue 番号の並び + `--merge` / `--resume`（任意） | `/ship-issues` のみ |
| [`issue-pr`](#issue-pr) | Issue 1 件を PR 1 件として実装する | Issue 番号 + `--merge`（任意） | `/issue-pr` のみ |
| [`pr-ready`](#pr-ready) | 現在ブランチの作業を diff 確認 → 検証 → コミット → PR にする | Issue 番号（任意） | `/pr-ready` のみ |
| [`ship-notes`](#ship-notes) | メモ → Issue → PR を通しで回す | `--merge`（任意）+ メモのファイルまたはテキスト | `/ship-notes` のみ |
| [`pr-review`](#pr-review) | PR を独立した立場でレビューする | PR 番号 | `/pr-review` のみ |
| [`pr-fix`](#pr-fix) | レビュー指摘を PR ブランチに反映して push する | PR 番号 + 指摘（任意） | `/pr-fix` のみ |
| [`pr-land`](#pr-land) | 準備の整った PR をマージして後始末する | PR 番号 + `--keep-branch`（任意） | `/pr-land` のみ |
| [`worktree-sweep`](#worktree-sweep) | 残った worktree と不要ブランチを掃除する | スクリプトへ渡すオプション | `/worktree-sweep` のみ |
| [`label-sync`](#label-sync) | 既定のラベルセットをリポジトリに流し込む | `--dry-run` / `--prune` / `-R owner/repo`（任意） | `/label-sync` のみ |
| [`label-apply`](#label-apply) | 既存の Issue / PR にラベルを付け直す | `--dry-run` / `--issues` / `--prs` / `--all` / 番号（任意） | `/label-apply` のみ |
| [`work-status`](#work-status) | 進行中の PR / worktree / ship-issues run を一覧し、次に叩くコマンドを出す（読むだけ） | `--no-fetch`（任意） | `/work-status` のみ |
| [`backlog-review`](#backlog-review) | open Issue 群を調査して ready / blocked / duplicate 等に分類する（読むだけ） | `--limit` / `--label` / `--milestone` / `--since` / `-R` / 番号（任意） | `/backlog-review` のみ |
| [`handoff`](#handoff) | 作業の引継ぎ文書を書く / 読んで再開する | `--resume [file]`（任意）+ メモ | `/handoff` のみ |

`cm` 以外の 15 は `disable-model-invocation: true` を持ち、スラッシュコマンドからしか
起動しません。`cm` だけは `user-invocable: true` で、コミット時にモデルからも選ばれます。

## スキル間の関係

責務を段階で分け、上位のスキルは下位のワークフローを呼ぶだけにしています。

```
メモ ──/triage-notes──> Issue 群
粗い Issue ─/issue-refine─> 実装可能な Issue   （--split で子 Issue に分割起票）
Issue 群 ─/ship-issues─> 依存分析 → ウェーブ → ワーカー → PR 群
Issue ───/issue-pr───> PR                 （ship-issues のワーカーが踏襲する単位）
ブランチ上の作業 ─/pr-ready─> PR          （Issue なしでも可。cm のコミット規約を内包）

PR ─/pr-review─> 指摘 ─/pr-fix─> 修正を push ─/pr-land─> マージ + 掃除

/ship-notes = /triage-notes → /ship-issues を繋ぐだけ
/ship-issues --merge / /issue-pr --merge ──> PR 作成後に /pr-land を続けて回す

/ship-issues ──最終ステップ──> /worktree-sweep 相当の掃除
/pr-land     ──最終ステップ──> 同上
/worktree-sweep                            （単体でも任意のタイミングで叩ける）

/label-sync ──> リポジトリのラベルを既定セットに揃える ──> /label-apply で既存 Issue / PR に付け直す
/triage-notes /issue-pr /pr-ready ──起票・PR 作成時──> label-apply/labeling-rules.md の規則で
                                                        既存ラベルから選んで付ける（作らない）

/work-status ──> いま何が動いていて次に何を叩くかを一覧（読むだけ）
                 ──> /pr-fix /pr-review /pr-land /pr-ready /ship-issues --resume /worktree-sweep へ案内

open Issue 群 ─/backlog-review─> ready / blocked / duplicate … に分類（読むだけ）
                                 ──ready の番号──> /ship-issues、ラベルの食い違い──> /label-apply
                                 ──needs investigation の番号──> /issue-refine

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
- `pr-review` → `pr-fix` → `pr-land` が PR 作成後の一直線です。`pr-review` は読むだけ、
  `pr-fix` は直して push するだけ、マージするのは `pr-land` だけ、と工程を分けています。
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
  ready / already implemented / blocked / duplicate / obsolete / needs-info / needs investigation
  に分類し、`/ship-issues <ready の番号>` / `/issue-refine <needs investigation の番号>` /
  `/label-apply <食い違いの番号>` の案を出します。
  GitHub 側は一切変更しません（ラベルも close もコメントもしない）。
- `handoff` はどのワークフローにも属さない横断ツールです。長い作業を別セッション
  （クラッシュ後・コンテキスト圧縮後・翌日）や別エージェント（Agent tool のワーカー、Codex）に
  渡すとき、会話の外に「文書 1 枚 + 未コミット差分の patch」を残します。リポジトリの状態は
  変えません。受け取り側は `--resume` で読み、鵜呑みにせず `git` / `gh` で照合してから続けます。

Issue の設計と実装は必ず別フェーズに分け、**1 Issue = 1 PR、1 ワーカー = 1 Issue** を守ります。

**PR をマージするのは `pr-land` だけです。** `ship-issues` と `issue-pr` は `--merge` を
付けたときに `pr-land` のワークフローを続けて回すだけで、自前ではマージしません。
ワーカーは `--merge` の有無にかかわらずマージしません。

## スキル同士の呼び出し方

`cm` 以外は `disable-model-invocation: true` なので、**別のスキルやサブエージェントから
Skill tool で呼ぶことはできません**（モデルが選択できない設定のため）。スキルが他のスキルの
手順に従う箇所では、`~/.claude/skills/<name>/SKILL.md` をパスで読ませています。

- `ship-issues` のワーカー → `issue-pr/SKILL.md`
- `ship-issues --merge` / `issue-pr --merge` → `pr-land/SKILL.md`
- `label-apply` / `triage-notes` / `issue-refine` / `issue-pr` / `pr-ready` / `backlog-review` → `label-apply/labeling-rules.md`

このため Codex 側（Import 先は `~/.agents/skills`）では、これらのパス参照が解決しません。

## 前提ツール

全スキルは `git` と、インストール・認証済みの GitHub CLI（`gh`）を前提にしています。
Issue / PR の読み取り・検索・作成は **すべて `gh` に統一**し、各 SKILL.md にもその旨を
明記しています。`gh` が無い、または未認証なら、スキルは別の手段に逃げず止まって報告します。

`settings.json` で有効にしている GitHub プラグイン（`github@claude-plugins-official`、
GitHub MCP）はスキルからは使いません。対話中に Issue を検索したいといった用途のために
残してあるだけです。`gh` に寄せる理由:

- Codex 側の前提（`git` + `gh`、後述）と揃う。MCP は Codex に届く保証がない
- 経路が 1 本なら、環境によってモデルが選ぶツールが変わって挙動がブレることがない
- `worktree-sweep.sh` が既に `gh pr list` に依存している

読み取り系の `gh` サブコマンドは `settings.json` の `permissions.allow` で許可し、
書き込み系（`create` / `edit` / `close` / `merge`）は都度確認のままにしています
（[../README.md](../README.md#gh-の読み取り系を許可している)）。

## Codex への移植性

これらのスキルは Codex の Import で `~/.agents/skills` にコピーされます
（[ルート README](../../README.md#codex-との連携)）。ただし全部が動くわけではありません。

| スキル | Codex での扱い |
| --- | --- |
| `cm` `triage-notes` `issue-refine` `issue-pr` `pr-ready` `pr-review` `pr-fix` `pr-land` `label-apply` `backlog-review` `handoff` | `git` と `gh` にしか依存しないため概ね動く（[前提ツール](#前提ツール)）。ただし `issue-pr --merge` の `pr-land` 参照と、`label-apply` 系の `labeling-rules.md` 参照は `~/.claude` のパスなので解決しない。`handoff` の `~/.claude/handoff/` は単なるディレクトリなので Codex からも読み書きできる |
| `worktree-sweep` `label-sync` `work-status` | `sh` / `git` / `gh` にしか依存しない。`~/.claude/scripts/*.sh` は Import の対象外なので、Codex 側では実体が要る |
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
  混ざる場合は `git add -p` で hunk 単位に stage する
- subject は日本語・句点なし、body は日本語・句点あり。「何を」ではなく「なぜ」を書く
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
- 起票後に依存関係を分析し、実行ウェーブに分類する

## issue-refine

既存の Issue をリポジトリと突き合わせて調査し、実装ワーカーが本文だけで着手できる品質に
**本文を書き換えます**。**実装はしません**（ブランチも PR も作りません）。
スキルを叩いたこと自体が書き換えの承認で、適用前に再確認は取りません（`--dry-run` を除く）。

- 引数は Issue 番号の並び（`31` / `#31` / URL、空白・カンマ区切り）。無引数では動かない
  （既定で全 open を触らない）。1 件ずつ独立に処理し、1 件の失敗で残りを止めない
- 着手前に既存 PR / 重複 Issue を検索し、refinable / already implemented / duplicate /
  obsolete / blocked に判定する。refinable と blocked だけ本文を書き換え、他は報告のみ
  （close も新規起票もしない）
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

- 引数は `101 102 103` / `#101 #102 #103` / `101,102,103` のいずれの形でも受け付け、
  重複を除いた Issue リストに正規化する。指定外の Issue には手を出さない
- 着手前に各 Issue を ready / already implemented / blocked / obsolete / duplicate /
  needs investigation に分類し、既存 PR と競合する実装を起こさない。needs investigation は
  ワーカーを起こさず `/issue-refine <N>` を案内する
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

実行計画と Issue ごとの状態は `~/.claude/ship-issues/<repo>-<日時>.md` に書き出します。
Claude Desktop のクラッシュや中断を跨いで `/ship-issues --resume` で再開するためのもので、
再開時はファイルを鵜呑みにせず `gh` と `git worktree list` で実状を取り直します。
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
  手順でマージする

## pr-ready

現在ブランチで書き終えた作業を、diff 確認 → 検証 → コミット → push → PR 作成まで一息に
持っていきます。**実装はしません**。既にブランチにある変更が対象です。

- Issue 番号は任意引数。省略時はブランチ名（`123-foo` など）やコミットメッセージ（`#123`、
  `Github-Issue:` トレーラ）から候補を出し、Issue を読んで一致を確認できたときだけ `Closes #N`
  を付ける。確信が持てなければ閉じず、候補として報告する
- default branch 上なら、未コミット変更だけのときは新ブランチを切って続行。default branch に
  コミット済みのものがあれば止まって報告する
- `git status` / `git diff` / base branch との差分全体を読み、無関係な変更・デバッグコード・
  一時ファイル・生成物・lock ファイル・秘密情報・マシン固有パスを取り除く
- `pr-review` と同じ観点（correctness / scope / 規約 / テスト）で自己レビューし、明らかな欠陥は直す
- リポジトリ規定の検証を影響範囲から先に流す。無ければでっち上げない。既存の失敗は直さず記録
- 未コミット変更は `cm` の規約でコミットする
- 同ブランチの PR が既にあれば作らず報告。PR テンプレートがあればそれに従い、無ければ
  Summary / Why / Verification / Issue の構成。`gh pr create` で作る
- type ラベルは `issue-pr` と同じ規則で、リポジトリに既にあるものから付ける
- force-push しない。マージしない

## ship-notes

メモから PR までを通しで回します。実体は `triage-notes` と `ship-issues` を繋ぐだけの
薄い合成で、固有のロジックは持ちません。

1. メモを `triage-notes` のワークフローで triage する
2. Issue を起票する
3. **新しく起票された actionable な Issue 番号だけ**を集める
4. それらを `ship-issues` のワークフローで処理する
5. 両者の結果を合わせて返す

重複・obsolete・アクション不要と判断したメモは実装フェーズに渡しません。
triage フェーズでは実装せず、実装開始後に Issue 境界を都合よく書き換えることもしません。
PR はマージしません。

## pr-review

PR 番号 1 件を、実装者ではなくレビュアーの立場でレビューします。**ファイルを変更せず**、
push もマージもしません。

- PR 本文とリンク先 Issue を読み、受け入れ条件とスコープ境界を把握してから差分を見る
- 差分は base branch との全体を見る。断片だけを見ない
- 観点は correctness（誤動作・エッジケース・競合状態・データ損失・互換性）、scope
  （Issue と無関係な変更）、リポジトリ規約、テストと検証の十分さ、混入物
  （デバッグログ・一時ファイル・秘密情報・マシン固有パス）
- 報告前に周辺コードを読んで裏を取る。推測と事実を分け、スタイル上の好みを欠陥として挙げない。
  弱い指摘を並べるより、確度の高い少数を出す
- 出力は APPROVE / REQUEST CHANGES / COMMENT の判定から始め、Critical / High / Medium / Low
  の順に列挙。最後に Issue coverage / Scope / Verification assessment を述べる

## pr-fix

`pr-review` の指摘を PR ブランチに反映して push します。**マージしません**。
GitHub へのコメント投稿もしません。

- 指摘の入力元は、引数の自由記述 → 同じ会話の `pr-review` 出力 → GitHub 上のレビュー
  （`gh pr view --comments`、インラインは `gh api` の GET）の順
- PR の head ブランチにいなければ隔離 worktree（`pr-<N>`）で `gh pr checkout` する。
  default branch の checkout では直さない
- 指摘は 1 件ずつ fix / decline に振り分ける。丸呑みも黙殺もしない。事実誤認、意図的な挙動、
  PR のスコープ外、リポジトリが求めないスタイル上の好みは理由付きで decline する
- 検証はリポジトリ規定に従う。既存の失敗は直さず記録する
- コミットは `cm` の規約。force-push しない

## pr-land

準備の整った PR をマージし、後始末します。**スキルを叩いたこと自体がマージの承認**で、
マージ前に再確認は取りません。ただし赤信号では必ず止まり、押し切りません。

- 止める条件: open でない / draft / `CONFLICTING` / `CHANGES_REQUESTED` /
  `gh pr checks` の失敗 / 議論に未対応の反対意見。**直さずに止めて報告する**
  （直すのは `pr-fix` の仕事）
- マージ方式はリポジトリの慣例に従い、不明なら `--squash`。既定で `--delete-branch` を
  付けて remote ブランチを消す。残したいときだけ `--keep-branch` を付ける（ローカルの
  後始末には影響しない）
- `gh` はローカルブランチ → remote ブランチの順に消すので、ローカルブランチが worktree で
  checkout 中（`ship-issues --merge` の通常ケース）だとローカル削除で失敗して **remote が
  残る**。マージ済みなら停止条件にせず、`gh api` で remote ブランチの有無を確かめ、残って
  いれば `git push origin --delete <branch>` で消してから後始末へ進む
  （`gh api -X DELETE .../git/refs/heads/<branch>` は権限分類器にブロックされる）
- マージ後に紐づく Issue が閉じたか確認する。閉じていなければ報告のみ（手で閉じない）
- 後始末は base branch へ切替 → `git fetch --prune` → `git pull --ff-only` →
  `worktree-sweep.sh`。`git` の削除コマンドは自分で叩かない
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
スキル側で `gh label` の書き込みを直接叩きません。

- 引数はスクリプトへそのまま渡す（`--dry-run` / `--prune` / `-R owner/repo`）
- GitHub 既定の `bug` / `enhancement` / `documentation` / `question` / `duplicate` / `wontfix`
  は rename で取り込み、付与済みの Issue からラベルが外れないようにする
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
| `type/refactor` | 挙動を変えない内部整理 | `refactor` |
| `type/perf` | 性能改善 | `perf` `performance` |
| `type/docs` | ドキュメントのみ | `documentation` `docs` |
| `type/test` | テストの追加・修正のみ | `test` `tests` |
| `type/chore` | 保守・ツール・ビルド・CI・依存の整理（commit type の `chore` / `ci` / `build` / `style` をまとめる） | `chore` `ci` `build` |
| `priority/high` `priority/medium` `priority/low` | 優先度。本文に明示があるときだけ付ける | — |
| `status/blocked` | 他の Issue / PR / 外部要因待ち | `blocked` |
| `status/needs-info` | 報告者からの情報待ち | `question` |
| `status/duplicate` | 別の Issue / PR で追跡済み | `duplicate` |
| `status/wontfix` | 対応しないと決めた | `wontfix` |
| `dependencies` | Dependabot / Renovate の依存更新 | — |
| `security` | 脆弱性修正・堅牢化 | — |
| `breaking-change` | 互換性を壊す変更（`feat!:` / `BREAKING CHANGE:`） | `breaking` |
| `good first issue` `help wanted` | GitHub 既定のまま。自動では付け外ししない | — |

`invalid` はセットに含めていません（`unmanaged` として残り、`--prune` で未使用なら消える）。

## label-apply

既存の Issue / PR を読み直し、**リポジトリに既にあるラベルの中から**適切なものを付け直します。
ラベルは作りません。判断規則は [`label-apply/labeling-rules.md`](label-apply/labeling-rules.md)
にあり、`triage-notes` / `issue-pr` / `pr-ready` も同じファイルを読みます。

- 既定は open な Issue と PR を各 200 件まで。`--issues` / `--prs` で絞り、`--all` で closed も
  含める。番号や URL を渡せばその項目だけ
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

- 対象は repo 全体。open PR（`gh pr list`）、agent worktree とローカルブランチ
  （`git worktree list` / `for-each-ref`）、`~/.claude/ship-issues/` の `DONE` が無い run を
  ブランチ名で結合し、1 単位 1 行にする
- 各行の `next` は `/pr-fix` / `/pr-review` / `/pr-land` / `/pr-ready` /
  `/ship-issues --resume` / `/worktree-sweep` / `wait` のどれか。判定表は
  [../README.md](../README.md#進行中の作業を一覧する) とスクリプト冒頭のコメントにある
- state file は「その Issue が ship-issues 由来か」「run の進み具合の主張」としてだけ読む。
  事実は git と gh の列で、食い違えば表が勝つ
- Agent の生存はヒューリスティック。確定信号は worktree lock の pid が生きていることだけで、
  直近の更新・ブランチ・PR・state file はヒント。別セッションのバックグラウンド Agent は
  見えない。この限界は毎回出力に含める
- 提案したコマンドは実行しない。「やって」と言われたら呼ぶスキル名を答える
- `--no-fetch` で `git fetch --prune` を省く（唯一の副作用）

## backlog-review

open Issue 群を読んで、1 件ずつちょうど 1 つの分類に振り分けます。**読むだけ**で、
ラベル付け・close・コメント・状態変更のどれもしません。`ship-issues` に渡す番号を選ぶ前段で、
`ship-issues` step 3 の分類（ready / already implemented / blocked / obsolete / duplicate /
needs investigation）に needs-info を足した 7 分類を使います。

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
  already implemented（マージ済み / open な PR が紐づく、またはコードが既に満たす）→ duplicate
  （残す側を名指し）→ obsolete → blocked → needs-info → needs investigation → ready。
  blocked と needs-info の定義は [`labeling-rules.md`](label-apply/labeling-rules.md) step 4
  のもの。迷ったら needs investigation にして何が足りないかを書き、推測で ready にしない
- 出力は件数サマリ → 分類ごとの表（番号 / タイトル / 根拠 / 注記）→ 既存 status ラベルとの
  食い違い一覧 → 次に叩くコマンド案（`/ship-issues <ready 番号>`、`/issue-refine <needs investigation 番号>`、
  `/label-apply <食い違い番号>`、duplicate / obsolete / already implemented の `gh issue close` 案）。
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
  あれば同名 `.patch`（`git diff HEAD`）を隣に置く。worktree 隔離のサブエージェントや別マシン
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
