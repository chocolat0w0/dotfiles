---
name: team-review-rules-build
description: Extract reviewer feedback from past merged pull requests, classify signal from noise, cluster similar findings, and abstract them into reusable Japanese code-review rules with examples and adoption metadata. Use when building or refreshing the team's shared review-rule set from GitHub PR history. Requires gh auth. Writes rules to the project's docs/team-review-rules/, defining the repository's own categories on the first run. Asks for user approval at classification and rule-proposal stages before saving. Use only when the user explicitly asks to build or refresh the rule set.
---

# Team Review Rules Build

## Overview

過去の merged PR に残されたレビュア指摘を集合知として抽出・抽象化し、汎用レビュー観点ルールに仕立てるスキル。

同じ観点が複数のレビュアから繰り返し出ている事実を根拠に、「どれだけ支持されているか（根拠件数）」を伴う再利用可能なルール集を育てる。生成物は `team-review` スキルが参照する。

分類ゲートとルール案ゲートの 2 段階でユーザー承認を挟み、承認前には保存しない。

**ユーザーが明示的に依頼したときだけ起動する。**

## ルール集

プロジェクトルートの `docs/team-review-rules/` がルール集である。このディレクトリを唯一の永続データとして扱い、スキルのインストール元やエージェントの個人設定へ書き込まない。

書式、カテゴリ、マージ規則は [rule-format.md](references/rule-format.md) に従う。ルール集を更新する前に必ず読む。

カテゴリはリポジトリごとに `INDEX.md` で定義する。スキル側に固定のカテゴリは持たない。`INDEX.md` が無い実行を「初回」と呼ぶ。

初回でも `docs/team-review-rules/` にカテゴリファイルが残っている場合は、カテゴリを新しく決めず、残っているファイルの frontmatter（`category` / `slug`）とルール件数から `INDEX.md` を復元する案を分類ゲートで示す。

## 引数

- `--count N`（既定 100）: 直近 N 件の merged PR を対象。
- `--since YYYY-MM-DD`: 指定日以降に merge された PR を対象。
- 両方省略時は直近 100 件の merged PR。両方指定時は「`--since` 以降、かつ最大 N 件」。

## Workflow

### 1. 収集

[collection-recipes.md](references/collection-recipes.md) に従い、対象 merged PR のインラインレビューコメントとレビュー要約を取得する。

- bot の発言と、PR 作者本人が起点のスレッドを除外する。作者の返信は文脈として残す。
- `in_reply_to_id` と `path`/`line` でスレッドを再構成する。
- 取得できない PR（403 やタイムアウト）はスキップし、スキップ件数を控える。
- 出力は「指摘候補アイテム（root ＋ 返信文脈）」の一覧。

### 2. 分類（分類ゲート）

各アイテムを「指摘 / 非指摘」に分類する。

- 指摘: 恒久的なレビュー観点になりうる指摘・提案・懸念。
- 非指摘: 補足説明、その場で解決した確認質問、雑談、実装メモなど。
- 返信の文脈を使って判断する（例: 「他と挙動を揃えている?」→「揃えました」で終わる確認質問は恒久ルールにしない）。

次に、指摘にカテゴリを付ける。

- `INDEX.md` がある場合は、そのカテゴリを付ける。どれにも収まらない指摘が複数あるときだけ、新カテゴリの案を示す。
- 初回は、指摘と判定したものだけからカテゴリ案を作り、それを付ける。案の作り方は [rule-format.md](references/rule-format.md) の「カテゴリの定義」に従う。

分類結果の表をユーザーに提示し、承認を得る。初回と新カテゴリがあるときは、カテゴリ案の表も同じゲートで示す。誤分類やカテゴリの指摘があれば直す。

承認後、初回は承認したカテゴリで `INDEX.md` を作成する（ルール件数 0 の行を含む）。新カテゴリを承認したときも、ここで `INDEX.md` に行を足す。ルール案ゲートの前に中断しても、次の実行でカテゴリを決め直さずに済むようにするためである。

### 3. クラスタリング

指摘をカテゴリ＋意味的類似度で束ね、同じ観点の複数指摘を 1 クラスタにまとめる。各クラスタは根拠スレッドと出典 PR を保持する。

### 4. 抽象化（ルール案ゲート）

クラスタごとに 1 ルールへ汎用化する（ルール本文＋具体例、[rule-format.md](references/rule-format.md) 準拠）。

既存ルールファイルと照合し、各案を区分する。

- 新規: 既存に一致なし。
- 更新: 既存と意味的に一致 → 最終採用日 bump・出典/根拠件数マージ。
- 重複: 同一実行内の重複 → 統合。

ルール案一覧（新規/更新/重複の区分付き）をユーザーに提示し、承認を得る。既存の `INDEX.md` に `対象` 列が無い場合は、各カテゴリの対象の案も同じゲートで示す。

### 5. 保存

承認されたルールを `docs/team-review-rules/<slug>.md` に反映し、`INDEX.md` を更新する（[rule-format.md](references/rule-format.md) の冪等マージ規則に従う）。

- prune は行わない。
- 変更したファイルと、追加・更新したルール ID を提示する。ルール集は git 管理外のこともあるので、差分は `git diff` に頼らない。
- コミットはしない。

## Output Format

各ゲートでの提示は次を基本にする。

- 分類ゲート:

```text
分類結果（対象 PR: N 件 / 指摘候補: M 件 / 指摘: L 件 / スキップ: K 件）
| # | 出典 | reviewer | 判定 | カテゴリ | 要約 |
```

- 分類ゲートのカテゴリ案（初回、または新カテゴリがあるとき）:

```text
カテゴリ案（新規: A）
| slug | 表示名 | 対象 | 該当する指摘数 |
```

- ルール案ゲート:

```text
ルール案（新規: A / 更新: B / 重複統合: C）
- [新規] R-type-safety-002: ...（根拠 #x, #y / 適用範囲 ...）
- [更新] R-naming-001: 最終採用日 2026-07-09 に更新（+#z）
```

- 保存後: 変更ファイル一覧と、ファイルごとの追加・更新ルール ID。
