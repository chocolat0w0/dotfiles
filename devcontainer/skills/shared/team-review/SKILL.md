---
name: team-review
description: Apply the team's accumulated code-review rules (built by team-review-rules-build) to review a diff or pull request. Placeholder skill - the rule set lives in the project's docs/team-review-rules/ and the review workflow is implemented later. Use only when the user explicitly asks for a team-rule review.
---

# Team Review（スタブ）

## Overview

チームの過去レビュー指摘から抽出した観点ルールを使って、差分や PR をレビューするためのスキル。

現時点ではルールの置き場所を定めるスタブであり、レビュー実行ロジックは後続で実装する。

ルールは `team-review-rules-build` スキルが生成・更新する。

## ルールの場所

プロジェクトルートの `docs/team-review-rules/` がルール集である。スキルのインストール元には置かない。

- `INDEX.md`: カテゴリの定義（表示名と対象）とルール件数の索引。カテゴリはリポジトリごとに異なる。
- `<slug>.md`: カテゴリ別のレビュー観点ルール。

ルール集が存在しない場合は、`team-review-rules-build` で作成するようユーザーに伝える。

## 未実装

- 差分/PR に対するルール適用とレビューコメント生成は後続タスク。
