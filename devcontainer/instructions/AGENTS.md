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
- `rebase` や `cherry-pick` の途中で「Your local changes to the following files would be overwritten」と止まっても、
  `git status` に差分が無ければ、stat の食い違いによる誤検知。`git update-index --refresh` の後に `--continue` で進める。
  本当の競合は `git diff --name-only --diff-filter=U` に出るので、それで区別する。

## GBrain の記憶（recall / remember）

この節は、`gbrain` という名前の MCP サーバーのツール（`recall`、`remember`、`forget` など）が使える環境でだけ適用する。ツール一覧に無い環境ではこの節を無視し、GBrain の利用や接続を勧めない。

- 好み、決定事項、プロジェクトの経緯、過去の作業について答える前に、`recall` で保存済みの記憶を確かめる（知識ページも探すときは `query` を付ける）。使った記録は fact の ID やページの slug で示す
- `source_id` は指定しない（指定すると権限エラーになる）。`synthesize` などの有料の合成機能は使わない
- 「覚えておいて」と明示的に頼まれたときだけ `remember` で保存する。`provenance`（例: 「<作業中のリポジトリ名> での会話 YYYY-MM-DD」）を必ず付け、特定のプロジェクトや人についての事実には `entity` を付ける。1 件の保存を頼まれても、以後の会話を自動で保存してよいことにはならない。「この会話だけ」と言われた内容は保存しない
- 保存するのは長く使う好みや決定事項だけ。作業途中の状態、資格情報やトークン、ローカルの設定値は保存しない。保存した記憶は、GBrain につないだすべてのリポジトリのエージェントから読める
- 事実を訂正するときは、保存済みの記録を `recall` で読み、古い ID を `forget` で取り消し、訂正した事実を provenance 付きで `remember` してから、`recall` で読み戻して確かめる。`forget` は有効な記憶から外すだけで、履歴は残る
- 書き込んだら読み戻して確かめる。接続されているのにツール呼び出しが失敗したときは、そう伝える。この会話だけを根拠に「前の会話で覚えた」とは言わない
