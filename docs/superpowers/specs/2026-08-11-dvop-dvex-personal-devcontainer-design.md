# dvop / dvex の個人用 devcontainer 設定対応

## 背景・目的

`dvop`（1Password の GH_TOKEN を注入して `devcontainer up`）と `dvex`（同トークンで `devcontainer exec`）は、現状常にリポジトリ標準の `.devcontainer/devcontainer.json` を使う。

プロジェクトによっては、個人用にカスタマイズした devcontainer 設定（`.devcontainer-personal/<host>/<org>/<repo>/.devcontainer/devcontainer.json`）を使いたい場合がある。このパスは VS Code Dev Containers 拡張が認識できる形式（リポジトリのパス）だが、リポジトリごとに異なるため、都度手動で `--config` を指定するのは煩雑。

`dvop`/`dvex` が、個人用設定が存在すればそれを自動的に `--config` として使い、存在しなければ従来通り標準の `.devcontainer/devcontainer.json` にフォールバックするようにする。

## 対象ファイル

`zsh/.zsh.d/secrets.zsh`

## 設計

### 1. ヘルパー関数 `_dv_personal_config()`

`dvop`/`dvex` の両方から呼び出す非公開ヘルパーとして追加する。`zhelp`（`zsh/.zsh.d/help.zsh`）は関数直前に説明コメントが無い場合は一覧に表示しないため、このヘルパーには説明コメントを付けない。

**処理内容:**

1. `git config --get remote.origin.url` で origin の URL を取得する。取得できない（git リポジトリでない／origin が無い）場合は何も出力せず失敗（非 0）を返す。
2. URL を正規化して `host/org/repo` 形式に変換する。
   - プロトコル部分（`https://`、`ssh://` など）を除去
   - `user@`（`git@` など）を除去
   - 残った最初の `:` を `/` に置換（SSH 形式 `host:org/repo` 対応）
   - 末尾の `.git` を除去
   - 変換例:
     - `https://github.com/example-org/example-repo.git` → `github.com/example-org/example-repo`
     - `git@github.com:example-org/example-repo.git` → `github.com/example-org/example-repo`
     - `ssh://git@github.com/example-org/example-repo.git` → `github.com/example-org/example-repo`
3. `$PWD` を基準に `.devcontainer-personal/<host/org/repo>/.devcontainer/devcontainer.json` の存在を確認する。
4. 存在すればそのパス（`$PWD` からの相対パス）を標準出力して成功を返す。存在しなければ何も出力せず失敗を返す。

### 2. `dvop` への統合

- `_dv_personal_config` の結果を `config_path` に格納し、空でなければ `--config "$config_path"` を `devcontainer up` の引数に追加する。
- あわせて `--workspace-folder "$PWD"` を明示的に追加する（`--config` の相対パス解決を `dvex` と同じ基準に揃えるため。現状は暗黙的に cwd が使われている想定だが、明示化してリスクを無くす）。
- `--remove-existing-container` / `--build-no-cache` は追加しない（必要な時にユーザーが `dvop -- --remove-existing-container` 等で都度付与する運用のため、範囲外）。

### 3. `dvex` への統合

- 既存の `--workspace-folder "${PWD}"` はそのまま維持する。
- `_dv_personal_config` の結果が空でなければ `--config "$config_path"` を `devcontainer exec` の引数に追加する。

### 4. エラーハンドリング・フォールバック

- git リポジトリでない、origin が未設定、`.devcontainer-personal` 配下に該当する `devcontainer.json` が無い、のいずれの場合も静かにフォールバックし、`--config` を付けずに標準の `.devcontainer/devcontainer.json` 解決に委ねる（devcontainer CLI 自体のデフォルト解決に任せる）。
- 上記フォールバックはエラーとして扱わず、コマンドの実行を妨げない。

## 動作確認方法

このリポジトリに zsh 関数の自動テストの仕組みが無いため、`_dv_personal_config()` のロジック部分を手元のシェルに切り出し、以下を手動確認する。

- テスト用ディレクトリに `.devcontainer-personal/github.com/example/repo/.devcontainer/devcontainer.json` を作成
- origin URL を HTTPS 形式・SSH 形式（`git@`）・`ssh://` 形式それぞれに設定し、期待通りのパスが標準出力されることを確認
- `.devcontainer-personal` 配下に該当ファイルが無い場合に何も出力されず失敗を返すことを確認
- git リポジトリでないディレクトリで実行した場合に何も出力されず失敗を返すことを確認

## スコープ外

- `--remove-existing-container` / `--build-no-cache` の自動付与
- `.devcontainer-personal` 以外のパス規約のサポート
- GitLab のネストしたサブグループなど、`org/repo` が複数階層になるケースの明示的な検証（正規化ロジック上は自然に対応できるが、個別テストは行わない）
