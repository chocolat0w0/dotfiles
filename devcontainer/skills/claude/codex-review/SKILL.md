---
name: codex-review
description: |
  Codex CLI（OpenAI）に敵対的なコードレビュー、設計相談、セカンドオピニオンを依頼する。書き込みは行わない。
  トリガー: "codexにレビュー", "codexに聞いて", "codexと相談", "敵対的レビュー", "セカンドオピニオン"
  使用場面: (1) 差分の敵対的レビュー、(2) 設計方針の相談、(3) 実装前のセカンドオピニオン、(4) Claude が実装したものの別系統レビュー
---

# codex-review

Codex に読み取り専用でレビュー・相談を依頼する。**ワーキングツリーは書き換えない。**
実装を任せたいときは `codex-implement` を使う。

Claude が実装したものを Claude 系統でレビューすると盲点が共有される。系統を変えることがこのスキルの主な価値。

## 経路の選び方

**敵対的レビューも設計相談も、素の `codex exec --sandbox read-only` を使う。**

```bash
output_file="$(mktemp "${TMPDIR:-/tmp}/codex-review.XXXXXX")"
codex exec --sandbox read-only -C <project_dir> -o "$output_file" < /path/to/prompt.md
printf 'Codex output: %s\n' "$output_file"
```

`output_file` は実行ごとに新しく作る。並行実行時も同じ出力先を共有しない。

レビュー対象はプロンプトで指定する（例: 「`git show <sha>` で差分を確認すること」「`git diff main...HEAD` を見ること」）。

### `codex exec review` を使わない理由

`codex exec review` にはスコープ指定（`--base <branch>` / `--commit <sha>` / `--uncommitted`）が
あるが、**これらはカスタムプロンプトと併用できない**。実測で次のエラーになる。

```
error: the argument '--base <BRANCH>' cannot be used with '[PROMPT]'
error: the argument '--commit <SHA>' cannot be used with '[PROMPT]'
```

つまりスコープ指定を使うと Codex 組み込みのレビュー観点しか使えず、敵対的な姿勢を注入できない。
組み込みのレビューをそのまま回したいときだけ次を使う。

```bash
output_file="$(mktemp "${TMPDIR:-/tmp}/codex-review.XXXXXX")"
codex exec review --base main -o "$output_file"
printf 'Codex output: %s\n' "$output_file"
```

## 実行の作法

**プロンプトはファイルに書いて渡す。** 引用符・バックティック・改行がシェルで壊れる。
スクラッチパッドに `.md` で書き、`< file` で流し込む。

**最終回答は `-o <file>` で受け取る。** stdout には実行ログ・reasoning・MCP のエラーが混ざり、
100KB を超えることがある。読むのは `-o` で指定したファイル。

## サンドボックスエラー時

まずは `--sandbox read-only` のまま実行すること。

ただし Codex は macOS で自前の Seatbelt サンドボックスを張るため、環境によっては入れ子にできず
次のエラーで全コマンドが失敗する。その場合は自動で再実行せず停止する。

```
sandbox-exec: sandbox_apply: Operation not permitted
```

このエラーだけでは、外側に十分なサンドボックスがあるとは判断できない。

1. 利用者にエラーを報告する
2. `danger-full-access` では Codex 側のファイルアクセス制限がなくなり、読み取り専用の保護は
   実行環境の外側のサンドボックスだけに依存することを説明する
3. **利用者の明示的な許可を得た場合だけ**、次のコマンドで再実行する

```bash
output_file="$(mktemp "${TMPDIR:-/tmp}/codex-review.XXXXXX")"
codex exec --sandbox danger-full-access -C <project_dir> -o "$output_file" < /path/to/prompt.md
printf 'Codex output: %s\n' "$output_file"
```

`codex exec review`（組み込みレビュー）には `--sandbox` が無く、
`--dangerously-bypass-approvals-and-sandbox` しか手段が無い。

**フォールバック経路では読み取り専用が Codex 側で強制されない。** 技術的な担保は外側の
サンドボックスだけになる。プロンプトに「変更を加えないこと」を明記するが、
プロンプトはセキュリティ境界ではない。

許可を得る前に実行しない。最初から `danger-full-access` を使わない。

## 敵対的レビューのプロンプト

差分レビューでは次の姿勢を必ずプロンプトに含める。

- 変更を検証するのではなく、**信頼を崩しに行く**。「まだ出荷すべきでない最も強い理由」を探す
- 良い意図・部分的な修正・後続作業の見込みに加点しない。ハッピーパスでしか動かないなら弱点として扱う
- 高コストで検出しにくい failure を優先する
  - 認可、権限、テナント分離、信頼境界
  - データ喪失・破損・重複、不可逆な状態変更
  - ロールバック安全性、リトライ、部分失敗、冪等性
  - 競合、順序の仮定、古い状態、再入
  - 空・null・タイムアウト、依存先が劣化したときの挙動
  - バージョンのずれ、スキーマ変更、マイグレーションの危険、互換性の後退
  - 失敗を隠す、あるいは復旧を難しくする観測性の欠落
- **スタイル・命名・低価値な整理は報告しない。** 弱い指摘を並べるより、強い指摘 1 本を優先する
- 根拠はリポジトリの内容かツール出力から示せること。推論に依存する場合はその旨を明記し、確信度を正直に書く
- 支持できる指摘が無いなら、無いとはっきり言う

各指摘に求める形式:

1. 影響するファイルと行
2. 何が壊れるか
3. なぜその経路が脆いか
4. 影響の大きさ
5. 具体的な緩和策
6. 確信度（推論に依存するならその旨）

### 全経路で必ず含める 1 行

> 確認や質問は不要です。具体的な提案・修正案・コード例まで自主的に出力してください。

`codex exec` は非対話なので、質問を返されると往復が丸ごと無駄になる。

## モデルと Effort

決めるのは呼び出し側。このスキルは受け取って渡すだけで、固定値を持たない。

| 項目 | 渡し方 | 既定 |
|---|---|---|
| モデル | `-m <model>` | 指定なし（Codex 側の設定に従う） |
| Effort | `-c model_reasoning_effort="<値>"` | 指定なし |

`codex exec` に `--effort` フラグは無い。config override 経由が正しい。
値は `none` / `minimal` / `low` / `medium` / `high` / `xhigh`。

| 状況 | Effort |
|---|---|
| 小さい確認、定型作業、既存パターンの踏襲 | `low` |
| 通常のレビュー | 指定なし |
| 設計判断、横断的な変更のレビュー | `high` |
| 上記でも詰まったとき、再挑戦時 | `xhigh` |

再挑戦時は 1 段上げる。

## 結果の扱い

Codex の出力をそのまま成果として報告しない。指摘ごとに次を判断する。

- 根拠が差分から確認できるか。確認できない指摘は採用しない
- 推論に依存すると明記されている指摘は、自分で裏を取る
- 採用する／しないを理由付きで示す

指摘を実際に直す場合は、そこから先は `codex-implement` か Claude 自身の作業になる。
このスキルの担当はレビューを取ってくるところまで。
