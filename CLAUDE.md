# dotfiles

このリポジトリは zsh の設定ファイル群です。GNU stow でホームディレクトリにシンボリックリンクを張って使います。

## ファイル構成

- `zsh/.zsh.d/alias.zsh` — エイリアスと単純な関数
- `zsh/.zsh.d/fzf.zsh` — fzf を使うインタラクティブな関数
- `zsh/.zsh.d/help.zsh` — `zhelp` 関数（コマンド一覧表示）

## カスタムコマンドの命名規則

### プレフィックス
- `g` — git 操作

### 動詞（操作対象）
| 略語 | 意味 |
|------|------|
| `b`  | branch |
| `a`  | add |
| `c`  | commit |
| `ll` | log |
| `ps` | push |
| `pl` | pull |
| `f`  | fetch |
| `rb` | rebase |
| `w`  | worktree |
| `cp` | cherry-pick |

### サフィックス
| 略語 | 意味 |
|------|------|
| `f`  | fzf でインタラクティブ選択 |
| `d`  | delete / remove |
| `n`  | new（新規作成） |
| `b`  | back（戻る） |
| `i`  | interactive（例: rebase -i）|

### 命名例
```
gbf   = git branch + fzf          → fzf でブランチ選択して checkout
gbdf  = git branch + delete + fzf → fzf でブランチ選択して削除
gwaf  = git worktree + add + fzf   → fzf でブランチ選択して worktree 作成
gwdf  = git worktree + delete + fzf→ fzf で worktree 選択して削除
grbf  = git rebase + fzf           → fzf でブランチ選択して rebase
grbif = git rebase -i + fzf        → fzf でコミット選択して rebase -i
```

## コマンド追加のルール

### alias.zsh に追加する場合
- 単純なエイリアスや1行で完結する関数を置く
- 各エイリアス/関数の末尾に `# 説明` を必ず書く（`zhelp` でパースされる）
- セクションは `#> セクション名` で区切る

```zsh
#> git / branch
alias gb='git checkout'   # checkout
```

### fzf.zsh に追加する場合
- fzf を使う複数行の関数を置く
- 関数の直前の行に `# 説明` を書く（`zhelp` でパースされる）
- セクションは `#> セクション名` で区切る

```zsh
#> git / fzf

# ブランチをfzfで選択して checkout
function gbf() {
  ...
}
```

### zhelp への自動反映
`zhelp` コマンドは以下をパースして表示する:
- `#> セクション名` → セクションヘッダー
- `alias name='...'  # 説明` → エイリアスの説明
- `function name() {` の直前の `# 説明` → 関数の説明
