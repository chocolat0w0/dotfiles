# 収集レシピ

過去 PR のレビュー指摘を取得し、スレッド単位に整理してフィルタする手順。すべて `gh` CLI を使う。

## 0. 前提

- `gh auth status` が認証済みであること。未認証ならユーザーに `gh auth login` を依頼する。
- リポジトリはハードコードしない。次で解決する。

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

## 1. 対象 merged PR を決める

引数に応じて対象 PR 一覧（番号・作者・merge 日時）を取得する。

- 件数指定（既定 100）:

```bash
gh pr list --repo "$REPO" --state merged --limit <N> \
  --json number,author,mergedAt
```

N は `--count` の値（既定 100）。

- 期間指定（`--since`）:

```bash
gh pr list --repo "$REPO" --state merged \
  --search "merged:>=2025-01-01" --limit 300 \
  --json number,author,mergedAt
```

- `--since` だけのときは、取得件数が `--limit` と同じなら打ち切られている可能性がある。`--limit` を増やして取り直すか、打ち切った旨をユーザーに伝える。
- 両方指定時は「`--since` 以降、かつ最大 N 件（`--count` の値）」で解釈する（`--search "merged:>=..."` に `--limit <N>` を併用し、結果は先頭 N 件に打ち切る）。

この結果から次を作る:
- 対象 PR 番号の集合
- PR 番号 → 作者ログイン（`author.login`）のマップ（作者除外に使う）

## 2. インラインレビューコメントを一括取得（主経路）

PR ごとに呼び出す回数を減らすため、リポジトリ単位の一括エンドポイントを使う。

```bash
gh api --paginate \
  "repos/$REPO/pulls/comments?per_page=100&sort=created&direction=desc" \
  --jq '.[] | {
    id, in_reply_to: .in_reply_to_id,
    pr: (.pull_request_url | split("/") | last),
    path, line: (.line // .original_line),
    user: .user.login, type: .user.type,
    body, created_at
  }'
```

- `pr` が §1 の対象集合に含まれるものだけ残す。
- 後続の push で outdated になったコメントは `line` が null になるので、`original_line` で補う。
- 遡りすぎないよう、対象 PR の最古 merge 日時より古い `created_at` に達したらページングを打ち切る目安にできるが、これはあくまで参考の目安である。取得は created 降順だが対象 PR は mergedAt で選ぶため、対象 PR 集合に含まれるコメントを落とさない範囲で判断すること。

## 3. レビュー要約本文を補完取得

対象 PR ごとに、レビュー要約（`state` が COMMENTED/APPROVED/CHANGES_REQUESTED の本文）を取得する。

この個別呼び出しは応答が遅くタイムアウトしやすい。`timeout` で上限を設け、失敗したら数回リトライする。

```bash
for i in 1 2 3; do
  out=$(timeout 20 gh api "repos/$REPO/pulls/<PR>/reviews" \
    --jq '.[] | select((.body // "") != "") | {user: .user.login, type: .user.type, state, body}' 2>&1)
  rc=$?
  [ $rc -eq 0 ] && break            # 成功
  [ $rc -eq 124 ] && continue       # タイムアウト → リトライ
  echo "$out" | grep -q "Resource not accessible" && break  # 403 → スキップ確定
done
```

- `403` が返る PR はスキップし、スキップした PR 番号と件数をログに残す。
- リトライしても取得できない（タイムアウト継続）PR も、403 と同様にスキップし PR 番号と件数をログに残す。
- `body` が空のレビュー（インラインコメントのみのレビュー）は §2 のインライン取得でカバーされるため、ここでは `body` 非空のものだけ扱う。

## 4. スレッド再構成

インラインコメントをスレッドに束ねる。

- root コメント: `in_reply_to == null`。
- 返信: `in_reply_to` が root の `id` を指す。補助的に同一 `pr` + `path` + `line` でも束ねる。
- 1 スレッド = root ＋ 返信群（時系列）。

例:
- root（reviewer）: 「未変更でも保存できるのは違和感…他の画面もこの挙動で揃えている?」
- reply（作者）: 「揃えました」
→ 返信単体では意味不明だが、root と束ねると指摘内容と解決経緯が揃う。

## 5. フィルタ

- 除外: `type == "Bot"`（例 `chatgpt-codex-connector[bot]`）。
- 除外: root の `user` が当該 PR の作者（§1 のマップ）と一致するもの。
- 残す:
  - 人間レビュア（作者以外）の root コメント → 指摘候補。
  - スレッド内の返信（作者返信を含む）→ 文脈・解決経緯・具体例として保持。
  - レビュー要約本文（§3、作者以外・bot 以外）→ それ自体を 1 アイテムとして扱う。

## 6. 出力

以下を持つ「指摘候補アイテム」の一覧を作る。
- PR 番号 / ファイルパス / 行
- root コメント本文（reviewer）
- 返信群（文脈）
- reviewer ログイン
