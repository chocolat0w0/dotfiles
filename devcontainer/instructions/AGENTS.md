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
