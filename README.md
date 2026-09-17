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

VSCode の `dotfiles: Install Command` に指定してください。

## カスタムコマンド

シェルで `zhelp` を実行すると使えるコマンド一覧を確認できます。
