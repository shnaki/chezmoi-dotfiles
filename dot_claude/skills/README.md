# スキル

`~/.claude/skills/*/SKILL.md` に配置される、全プロジェクト共通のスキルです。

| スキル | 内容 | 引数 | 起動 |
| --- | --- | --- | --- |
| [`cm`](#cm) | Conventional Commits でコミットする | コミットメッセージまたは変更の説明 | `/cm`（モデルからの自動起動も可） |
| [`triage-notes`](#triage-notes) | メモを調査して GitHub Issue を起票する | メモのファイルまたはテキスト | `/triage-notes` のみ |
| [`ship-issues`](#ship-issues) | 既存 Issue 群を並列ワーカーに割って PR 化する | Issue 番号の並び | `/ship-issues` のみ |
| [`issue-pr`](#issue-pr) | Issue 1 件を PR 1 件として実装する | Issue 番号 | `/issue-pr` のみ |
| [`ship-notes`](#ship-notes) | メモ → Issue → PR を通しで回す | メモのファイルまたはテキスト | `/ship-notes` のみ |
| [`pr-review`](#pr-review) | PR を独立した立場でレビューする | PR 番号 | `/pr-review` のみ |

`cm` 以外の 5 つは `disable-model-invocation: true` を持ち、スラッシュコマンドからしか
起動しません。`cm` だけは `user-invocable: true` で、コミット時にモデルからも選ばれます。

## スキル間の関係

責務を段階で分け、上位のスキルは下位のワークフローを呼ぶだけにしています。

```
メモ ──/triage-notes──> Issue 群
Issue 群 ─/ship-issues─> 依存分析 → ウェーブ → ワーカー → PR 群
Issue ───/issue-pr───> PR                 （ship-issues のワーカーが踏襲する単位）

/ship-notes = /triage-notes → /ship-issues を繋ぐだけ
/pr-review  = PR → レビュー結果            （独立・どこからも呼ばれない）
```

- 起票だけしたいときは `/triage-notes`。既に Issue があるなら `/ship-issues` に
  番号を渡します。メモから PR まで一息に回すときだけ `/ship-notes` を使います。
- ワーカーは `ship-issues` が起こします。Issue ごとに Agent tool で
  `isolation: "worktree"` のワーカーを1つ立て、`issue-pr` のワークフローを踏襲させます。
  オーケストレータ本体では実装しません。
- `pr-review` は他スキルから呼ばれません。PR ができた後に手動で回します。

Issue の設計と実装は必ず別フェーズに分け、**1 Issue = 1 PR、1 ワーカー = 1 Issue** を守ります。
いずれのスキルも PR をマージしません。

## Codex への移植性

これらのスキルは Codex の Import で `~/.agents/skills` にコピーされます
（[ルート README](../../README.md#codex-との連携)）。ただし全部が動くわけではありません。

| スキル | Codex での扱い |
| --- | --- |
| `cm` `triage-notes` `issue-pr` `pr-review` | `git` と `gh` にしか依存しないため概ね動く |
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
- 起票後に依存関係を分析し、実行ウェーブに分類する

## ship-issues

既に起票済みの Issue 番号を複数受け取り、並列ワーカーに割り当てて PR 化する
オーケストレータです。本体では実装しません。

- 引数は `101 102 103` / `#101 #102 #103` / `101,102,103` のいずれの形でも受け付け、
  重複を除いた Issue リストに正規化する。指定外の Issue には手を出さない
- 着手前に各 Issue を ready / already implemented / blocked / obsolete / duplicate /
  needs investigation に分類し、既存 PR と競合する実装を起こさない
- ready な Issue について影響範囲（API・共有型・スキーマ・マイグレーション・生成物・
  lock ファイル・ルーティング・ビルド設定など）を見積もり、Issue 間の関係を
  independent / potentially conflicting / semantically dependent /
  ordered but independently valuable に分類する
- ファイルが重ならないことは独立性の根拠にならない。バックエンドとフロントの
  producer/consumer、マイグレーション順序、同一生成物の再生成などを見る
- 実行ウェーブを組む。並列度の最大化より安全な並列度を優先し、理由なく直列化もしない
- ウェーブ内は Agent tool で 1 呼び出し = 1 Issue、`isolation: "worktree"` 指定、
  1 メッセージでまとめて並列起動する
- ウェーブ完了ごとに残りを再評価する。初期計画に盲従しない
- 未マージ PR への依存は明示的に扱う。暗黙の stacked branch を作らない
- 最終出力は Pull Requests / Not implemented / Execution plan / Dependencies and conflicts

## issue-pr

Issue 番号 1 件を受け取り、PR 1 件として実装します。Issue がスコープの境界です。

- 無関係な refactoring・cleanup・formatting・rename・依存更新を PR に混ぜない。
  別の問題を見つけたら報告のみに留める
- 専用ブランチと隔離 worktree で作業する。default branch の checkout は編集しない
- 着手前に既存 PR / 同等ブランチの有無を確認し、二重実装を避ける
- 検証は影響範囲から先に流し、その後リポジトリ規定の広い検証を回す。
  既存の失敗を直すために無関係なコードを触らない
- コミット前に base branch との差分全体を見て、スコープ外の変更・デバッグコード・
  生成物の巻き込みを取り除く
- PR 本文は Summary / Why / Verification / Issue（`Closes #<number>`）の構成
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
