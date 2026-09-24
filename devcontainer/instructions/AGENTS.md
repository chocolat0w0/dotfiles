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
