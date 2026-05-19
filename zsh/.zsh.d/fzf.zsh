echo "set fzf"

# fzf が存在しない場合は何もしない
if ! command -v fzf >/dev/null 2>&1; then
  return
fi

export FZF_DEFAULT_OPTS='--height 40% --reverse --border'

########################################
# シェル統合 (Ctrl+R, Ctrl+T, Alt+C)
if [[ "$(fzf --version | awk '{print $1}')" > "0.48" ]]; then
  eval "$(fzf --zsh)"
else
  # Homebrew
  if [[ -f "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/key-bindings.zsh" ]]; then
    source "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/key-bindings.zsh"
    source "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/completion.zsh"
  # Debian/Ubuntu apt
  elif [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]]; then
    source /usr/share/doc/fzf/examples/key-bindings.zsh
    source /usr/share/doc/fzf/examples/completion.zsh
  fi
fi

########################################
#> git / fzf

# ブランチをfzfで選択して checkout（origin/ でリモートのみ絞込）
function gbf() {
  local selected branch
  selected=$(git branch -a --sort=-committerdate |
    sed 's/^[* ]*//' |
    sed 's|^remotes/||' |
    sort -u |
    fzf --prompt="checkout> " --preview="git log --oneline -20 {1}" \
        --preview-window=right:60%)
  [[ -z "$selected" ]] && return
  if [[ "$selected" == origin/* ]]; then
    git checkout -t "$selected"
  else
    git checkout "$selected"
  fi
}

# reviewing ブランチ作成（fzf でベースブランチを選択）
function grvf() {
  local selected
  selected=$(git branch -a --sort=-committerdate |
    sed 's/^[* ]*//' |
    sed 's|^remotes/||' |
    grep -v ' -> ' |
    sort -u |
    fzf --prompt="reviewing base> " --preview="git log --oneline -20 {}")
  [[ -z "$selected" ]] && return
  git checkout -B reviewing "$selected"
}

# ブランチをfzfで選択して削除（複数選択可）
function gbdf() {
  local branches
  branches=$(git branch --sort=-committerdate |
    sed 's/^[* ]*//' |
    fzf --multi --prompt="delete branch> " --preview="git log --oneline -20 {}")
  [[ -n "$branches" ]] && echo "$branches" | xargs git branch -D
}

# ブランチをfzfで選択してlogをブラウズ（Enter で詳細表示、デフォルトは現在のブランチ）
function gllf() {
  local branch current
  current=$(git rev-parse --abbrev-ref HEAD)
  branch=$({ echo "$current"; git branch -a --sort=-committerdate |
    sed 's/^[* ]*//' |
    sed 's|^remotes/||' |
    sort -u; } |
    awk '!seen[$0]++' |
    fzf --prompt="log branch> " --preview="git log --oneline -10 {}")
  [[ -z "$branch" ]] && return
  git log --date=short \
    --pretty=format:'%C(yellow)%h%Creset %ad %C(cyan)%an%Creset %s%C(auto)%d%Creset' "$branch" |
  fzf --ansi --no-sort \
    --preview='git show --stat --color=always {1}' \
    --bind='enter:execute(git show --color=always {1} | less -R)'
}

# pull前に incoming commits を確認（fetch してから HEAD..origin/<branch> を表示）
function gplf() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  git fetch origin "$branch"
  git log --oneline --date=short \
    --pretty=format:'%C(yellow)%h%Creset %ad %C(cyan)%an%Creset %s%C(auto)%d%Creset' \
    "HEAD..origin/${branch}" |
  fzf --ansi --no-sort --prompt="incoming> " \
      --preview='git show --stat --color=always {1}' \
      --bind='enter:execute(git show --color=always {1} | less -R)'
}

# ブランチをfzfで選択して rebase
function grbf() {
  local branch
  branch=$(git branch -a --sort=-committerdate |
    sed 's/^[* ]*//' |
    sed 's|^remotes/||' |
    sort -u |
    fzf --prompt="rebase onto> " --preview="git log --oneline -20 {}")
  [[ -n "$branch" ]] && git rebase "$branch"
}

# ブランチをfzfで選択して rebase --onto <newbase> <upstream>
function grbof() {
  local newbase upstream
  newbase=$(git branch -a --sort=-committerdate |
    sed 's/^[* ]*//' |
    sed 's|^remotes/||' |
    sort -u |
    fzf --prompt="rebase --onto (newbase)> " --preview="git log --oneline -20 {}")
  [[ -z "$newbase" ]] && return
  upstream=$(git branch -a --sort=-committerdate |
    sed 's/^[* ]*//' |
    sed 's|^remotes/||' |
    sort -u |
    fzf --prompt="rebase --onto (upstream)> " --preview="git log --oneline -20 {}")
  [[ -z "$upstream" ]] && return
  git rebase --onto "$newbase" "$upstream"
}

# コミットをfzfで選択して rebase -i（そのコミットを含む）
function grbif() {
  local hash
  hash=$(git log --oneline --date=short \
    --pretty=format:'%C(yellow)%h%Creset %ad %C(cyan)%an%Creset %s%C(auto)%d%Creset' |
    fzf --ansi --no-sort --prompt="rebase -i> " \
        --preview='git show --stat --color=always {1}' |
    awk '{print $1}')
  [[ -n "$hash" ]] && git rebase -i --autosquash "${hash}^"
}

# 変更ファイルをfzfで選択して git add / restore --staged（複数選択可、トグル）
function gaf() {
  local selected
  selected=$(git status --short |
    awk '
      {
        x = substr($0, 1, 1)
        if (x != " " && x != "?")
          print "\033[32m●\033[0m " $0
        else
          print "\033[90m○\033[0m " $0
      }
    ' |
    fzf --multi --prompt="stage> " --ansi \
      --header='● staged → unstage  ○ unstaged → stage' \
      --preview='f=$(echo {} | awk "{print \$NF}"); git diff --color=always "$f" 2>/dev/null; git diff --cached --color=always "$f" 2>/dev/null')
  [[ -z "$selected" ]] && return
  while IFS= read -r line; do
    local clean fname
    clean=$(echo "$line" | sed 's/\033\[[0-9;]*m//g')
    fname=$(echo "$clean" | awk '{print $NF}')
    if [[ "$clean" == '●'* ]]; then
      git restore --staged "$fname"
    else
      git add "$fname"
    fi
  done <<< "$selected"
  git status -s
}

########################################
#> git / worktree / fzf

# worktree をfzfで選択して cd
function gwf() {
  local worktree
  worktree=$(git worktree list | tail -n +2 | awk '{print $1}' |
    fzf --prompt="worktree cd> " \
        --preview="git -C {} log --oneline -10 2>/dev/null; echo '---'; ls {}")
  [[ -n "$worktree" ]] && cd "$worktree"
}

# 新規ブランチでworktree作成してcd: gwn <branch> [<base>]
function gwn() {
  local branch="$1"
  [[ -z "$branch" ]] && echo "Usage: gwn <new-branch> [<base>]" && return 1
  local repo_root worktree_path
  repo_root=$(git rev-parse --show-toplevel)
  worktree_path="${repo_root}/../$(basename "$repo_root").worktrees/${branch//\//-}"
  git worktree add --relative-paths -b "$branch" "$worktree_path" "${2:-HEAD}"
  echo "Created: $worktree_path"
  cd "$worktree_path"
}

# 既存ブランチをfzfで選択してworktree作成してcd
function gwaf() {
  local selected branch repo_root worktree_path
  selected=$(git branch -a --sort=-committerdate |
    sed 's/^[* ]*//' |
    sed 's|^remotes/||' |
    sort -u |
    fzf --prompt="worktree add branch> " --preview="git log --oneline -10 {}")
  [[ -z "$selected" ]] && return
  # origin/ プレフィックスを除いたブランチ名を取得
  branch="${selected#origin/}"
  repo_root=$(git rev-parse --show-toplevel)
  worktree_path="${repo_root}/../$(basename "$repo_root").worktrees/${branch//\//-}"
  if [[ "$selected" == origin/* ]]; then
    git worktree add --relative-paths -b "$branch" "$worktree_path" "$selected"
  else
    git worktree add --relative-paths "$worktree_path" "$branch"
  fi
  echo "Created: $worktree_path"
  cd "$worktree_path"
}

# worktreeをfzfで選択して削除（複数選択可、紐づくブランチの削除を追加確認）
function gwdf() {
  local worktrees
  worktrees=$(git worktree list | tail -n +2 | awk '{print $1}' |
    fzf --multi --prompt="worktree remove> " \
        --preview="git -C {} log --oneline -10 2>/dev/null; echo '---'; ls {}")
  [[ -z "$worktrees" ]] && return

  local wt branch branches=()
  while IFS= read -r wt; do
    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)
    [[ -n "$branch" && "$branch" != "HEAD" ]] && branches+=("$branch")
  done <<< "$worktrees"

  echo "$worktrees" | xargs -I{} git worktree remove {}

  if [[ ${#branches[@]} -gt 0 ]]; then
    printf "ブランチも削除しますか? (%s) [y/N] " "${(j:, :)branches}"
    local answer
    read -r answer
    if [[ "$answer" == [yY] ]]; then
      for branch in "${branches[@]}"; do
        git branch -D "$branch"
      done
    fi
  fi
}

########################################
#> navigation

# ディレクトリ移動履歴をファイルに記録（タブ間共有のため）
export ZSH_DIR_HISTORY="${HOME}/.zsh_dirhistory"
function chpwd() {
  echo "$PWD" >> "$ZSH_DIR_HISTORY"
  local tmp
  tmp=$(tail -1000 "$ZSH_DIR_HISTORY") && echo "$tmp" > "$ZSH_DIR_HISTORY"
}

# 最近のディレクトリをfzfで選択して cd（タブ間共有）
function cdf() {
  local dir
  dir=$({ command -v tac &>/dev/null && tac "$ZSH_DIR_HISTORY" || tail -r "$ZSH_DIR_HISTORY"; } 2>/dev/null | awk '!seen[$0]++' |
    fzf --prompt="cd> " --preview='ls -la {}')
  [[ -n "$dir" ]] && cd "$dir"
}
