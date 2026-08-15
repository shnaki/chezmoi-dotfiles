# スキル

`~/.claude/skills/*/SKILL.md` に配置される、全プロジェクト共通のスキルです。

| スキル | 内容 | 引数 | 起動 |
| --- | --- | --- | --- |
| [`cm`](#cm) | Conventional Commits でコミットする | コミットメッセージまたは変更の説明 | `/cm`（モデルからの自動起動も可） |
| [`triage-notes`](#triage-notes) | メモを調査して GitHub Issue を起票する | メモのファイルまたはテキスト | `/triage-notes` のみ |
| [`issue-pr`](#issue-pr) | Issue 1 件を PR 1 件として実装する | Issue 番号 | `/issue-pr` のみ |
| [`ship-notes`](#ship-notes) | メモ → Issue → 並列ワーカー → PR を通しで回す | メモのファイルまたはテキスト | `/ship-notes` のみ |
| [`pr-review`](#pr-review) | PR を独立した立場でレビューする | PR 番号 | `/pr-review` のみ |

`cm` 以外の 4 つは `disable-model-invocation: true` を持ち、スラッシュコマンドからしか
起動しません。`cm` だけは `user-invocable: true` で、コミット時にモデルからも選ばれます。

## スキル間の関係

```
メモ ──/triage-notes──> Issue                          （起票まで）
     └─/ship-notes───> Issue ──ワーカー──> PR          （通しで実行）
                                  └ 各ワーカーが issue-pr のワークフローを踏襲

Issue ──/issue-pr───> PR                               （1 件ずつ実装）
PR ────/pr-review──> レビュー結果                      （独立・どこからも呼ばれない）
```

- `ship-notes` は triage 工程を内包します（「Perform the same process as the
  `triage-notes` skill」）。`triage-notes` を別途呼ぶ必要はありません。
- `ship-notes` は Issue ごとに Agent tool で `isolation: "worktree"` のワーカーを起こし、
  各ワーカーに `issue-pr` のワークフローを踏襲させます。オーケストレータ本体では実装しません。
- `pr-review` は他スキルから呼ばれません。PR ができた後に手動で回します。

Issue の設計と実装は必ず別フェーズに分け、**1 Issue = 1 PR、1 ワーカー = 1 Issue** を守ります。
いずれのスキルも PR をマージしません。

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

メモから PR までを通しで回すオーケストレータです。

1. **Phase 1** メモを triage して Issue を起票（`triage-notes` と同じ処理）
2. **Phase 2** 起票した Issue をスコープ契約として凍結する。実装を楽にするための書き換えはしない
3. **Phase 3** 影響範囲（モジュール／API／共有型／スキーマ／生成物／lock ファイル等）から
   依存グラフを組み、実行ウェーブに分類する。ファイルが重ならないことは独立性の根拠にならない
4. **Phase 4** ウェーブ内の Issue ごとに Agent tool でワーカーを起動。1 呼び出し = 1 Issue、
   `isolation: "worktree"` 指定、同一ウェーブは 1 メッセージでまとめて並列起動
5. **Phase 5-7** 結果を集約し、依存が判明したら後続ウェーブを組み直す。最後に
   「1 Issue = 1 PR」が崩れていないかを検査する

失敗は隠さず報告します。PR はマージしません。

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
