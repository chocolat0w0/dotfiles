# エージェント共通の指示

devcontainer で動く Claude Code と Codex の両方に適用されるグローバル指示です。

## CLI へ複数行の JSON を渡す

複数行の本文を含む JSON を CLI へ渡すときは、ヒアドキュメントの python で生成して
直接パイプする。

```bash
python3 - <<'PY' | crit comment --json --author "Claude Code"
import json
print(json.dumps([
  {"reply_to": "c_xxxxxx", "body": "1 行目\n\n2 行目"},
], ensure_ascii=False))
PY
```

次の 2 つは使わない。どちらも文字列リテラルへ生の改行が混入して失敗する。

- シェルのクォート文字列へ JSON を直書きする（`echo '[...]' | cmd`）。`\n` が展開されず
  リテラルの `\` + `n` のまま渡り、`invalid character '\n' in string literal` になる
- Write で作った JSON ファイルを Edit で書き換える。`new_string` の末尾に残った改行が
  文字列を途中で閉じ、`Expecting ',' delimiter` になる

ファイル経由にせざるを得ない場合は、渡す前に
`python3 -c "import json;json.load(open('...'))"` でパースを検証する。

## 挙動を断定する前に確かめる

- 挙動を断定する前やユーザーに確認を求める前に、確認できる手段を探す。設定ファイル、既存実装、ブランチや PR、`--dry` などの実測がそれに当たる。
- 実測では、入力をユーザーの操作から実際に届く形に揃える。例えば、URL のクエリは `searchParams.get` で 1 回デコードされた値になる。
- 代替実装を提案するときは、その実装が持ち込む依存も確かめる。例えば、import の経路が循環しないかを見る。
- 確認できなかったことは「未確認」と書く。

## 完了報告の前に差分をレビューさせる

- コードを変更した作業では、完了報告の前に、自分のサブエージェントへ差分のレビューを依頼する。変更の経緯を渡さずに、バグ、変更した部品を使う他の画面や機能への影響、周辺の既存コードとの書き方の違いを見させる。
- 指摘には対応するか、対応しない理由を完了報告に書く。

## /workspace でのブランチ切り替え

- devcontainer の `/workspace` では、作業ツリーを書き換える git 操作が途中で失敗し、
  新旧の版が混ざった状態で残ることがある。読み取り専用マウント（`.devcontainer/proxy/` など）に
  差分があると必ず失敗し、virtiofs 越しの書き込みも `Permission denied` で止まることがある。
- ブランチの切り替え・作成・早送りは `git-safe-switch` を使う。読み取り専用マウント配下に差分が
  あれば実行せずに止まり、失敗したら元のブランチへ戻す。
  - `git-safe-switch <ref>`、`git-safe-switch -c <branch> [<start>]`
  - `pull` の代わりは `git fetch` の後に `git-safe-switch --ff [<ref>]`
  - 実行してよいかの判定だけなら `git-safe-switch --check <ref>`
- `git-safe-switch` が終了コード 2〜4 で止まったら、表示された内容を伝えてホストでの実行を
  ユーザーに依頼する。終了コード 4（元に戻せなかった）のときは、作業ツリーを触らずに報告する。
  終了コード 1 は git がそのまま拒否した（何も変わっていない）ので、git のメッセージに従う。
- 早送りでない `merge`、`reset --hard`、`gh pr checkout` はホストでの実行を依頼する。
  Claude Code では PreToolUse フックがこれらと直接の `git switch` / `git checkout <ref>` / `git pull` を止める。
- `rebase` と `cherry-pick` は対象外。実行する前に
  `git diff --name-only HEAD <対象> -- .devcontainer/proxy` が空であることを確かめる。
