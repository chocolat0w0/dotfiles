# dotfiles

## 使い方

スクリプトを実行する

```bash
% ./setup.sh
```

devcontainer では次を実行する

```bash
% ./setup-devcontainer.sh
```

`devcontainer/home` 配下は devcontainer で使うユーザー設定ファイルの実体です。`setup-devcontainer.sh` がこれらを `$HOME` に配置します。

- `devcontainer/home/.claude/settings.json` -> `~/.claude/settings.json`
- `devcontainer/home/.claude/statusline-command.sh` -> `~/.claude/statusline-command.sh`
- `devcontainer/home/.codex/config.toml` -> `~/.codex/config.toml`

`devcontainer/instructions/AGENTS.md` は Claude Code と Codex に共通で読ませるグローバル指示です。`setup-devcontainer.sh` がシンボリックリンクを張るので、コンテナ内で本リポジトリを pull すれば内容が反映されます（実行中のエージェントには次のセッションから反映）。

- `devcontainer/instructions/AGENTS.md` -> `~/.claude/CLAUDE.md`
- `devcontainer/instructions/AGENTS.md` -> `~/.codex/AGENTS.md`

エージェント用のスクリプトもシンボリックリンクで配置します。`settings.json` は既存のファイルを上書きしないので、フックを足したときは `~/.claude/settings.json` へ手で反映してください。

- `devcontainer/bin/git-safe-switch` -> `~/.local/bin/git-safe-switch`
- `devcontainer/home/.claude/hooks/guard-git-worktree-rewrite.py` -> `~/.claude/hooks/guard-git-worktree-rewrite.py`

`git-safe-switch` は Python 3 と、リポジトリ内の補助スクリプト `devcontainer/bin/git-safe-switch-check.py` を使います。作業ツリーやインデックスが新旧どちらかの版に一致する途中状態なら切り戻しを試み、未知の変更や未追跡ファイルとの衝突があれば停止します。新旧いずれかの版へ戻す編集や削除は途中状態と区別できません。改行変換・外部フィルターなどで保存内容がコミットと異なる場合も、安全を確認できないため停止します。

VSCode の `dotfiles: Install Command` に指定してください。

## カスタムコマンド

シェルで `zhelp` を実行すると使えるコマンド一覧を確認できます。
