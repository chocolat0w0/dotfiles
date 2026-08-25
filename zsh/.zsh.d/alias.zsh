echo "set alias"

########################################
# エイリアス

alias la='ls -a'
alias ll='ls -la'

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

alias mkdir='mkdir -p'

# sudo の後のコマンドでエイリアスを有効にする
alias sudo='sudo '

# グローバルエイリアス
alias -g L='| less'
alias -g G='| grep'

#> lazygit
alias lg='lazygit'                                                           # lazygit

#> devcontainer
alias dvc='devcontainer up --dotfiles-repository https://github.com/chocolat0w0/dotfiles.git --dotfiles-install-command setup-devcontainer.sh' # devcontainer with dotfiles

#> git / status
alias gst='git status -s'                                                    # status (short)
alias gdf='git diff'                                                         # diff

#> git / branch
alias gb='git checkout'                                                      # checkout
alias gbc='git checkout -b'                                                  # 新規ブランチ作成して checkout
alias gbs='git branch -a'                                                    # ブランチ一覧
alias gbd='git branch -D'                                                    # ブランチ強制削除

#> git / add
alias ga='git add'                                                           # add
alias gaa='git add --all'                                                    # add (all)

#> git / commit
alias gc='git commit'                                                        # commit
alias gcm='git commit -m'                                                    # commit -m
alias gca='git commit --amend'                                               # commit --amend

#> git / remote
alias gf='git fetch --prune'                                                 # fetch (prune)
alias gpl='git rev-parse --abbrev-ref HEAD | xargs git pull origin'         # pull origin (current branch)
alias gps='git rev-parse --abbrev-ref HEAD | xargs git push origin'         # push origin (current branch)

#> git / pull request
function gpr() { gh pr create --web --base main --head "$(git rev-parse --abbrev-ref HEAD)" }    # main 向けPR作成画面をブラウザで開く

#> git / log
alias gll='git log  -10 --date=short --pretty=format:'\''%C(yellow)%h%Creset %ad  %C(cyan bold)%an%Creset%x09%C(auto)%d%Creset %s'\'''    # log (10件)
alias glgg='git log --graph --date=short --format="%C(yellow)%h%C(reset) %C(magenta)[%ad]%C(reset)%C(auto)%d%C(reset) %s %C(cyan)@%an%C(reset)"'    # log (graph)
alias glgr='git log --graph --date-order --pretty=format:'\''%Cblue%h %Cgreen%ci %Cred%an %Cblue%m %Creset%s %Cred%d'\'''    # log (graph, date-order)

#> git / other
alias gcp='git cherry-pick'                                                  # cherry-pick
alias grma='git status | grep deleted: | awk '\''{print $2}'\'' | xargs git rm'    # deleted ファイルを git rm
alias grm='git rm'                                                           # rm
alias grmf='rm'                                                              # rm (force, git管理外)
alias grv='git checkout -B reviewing'                                        # reviewing ブランチに checkout
alias gign='git rm -r --cached .; git add .'                                # .gitignore を反映

#> git / worktree
alias gw='git worktree list'                                                 # worktree 一覧
function gwa() { git worktree add "$@" && cd "$1" }                        # worktree 追加して cd
alias gwd='git worktree remove'                                              # worktree 削除
# メイン worktree に戻る（worktree とブランチの削除を確認）
function gwb() {
  local current_path current_branch main_path answer
  current_path="$PWD"
  main_path=$(git worktree list | head -1 | awk '{print $1}')
  [[ "$current_path" == "$main_path" ]] && { echo "Already in main worktree." >&2; return; }
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  cd "$main_path"
  printf "worktree '%s' とブランチ '%s' を削除しますか? [y/N] " "$current_path" "$current_branch"
  read -r answer
  if [[ "$answer" == [yY] ]]; then
    git worktree remove "$current_path"
    git branch -D "$current_branch"
  fi
}

#> markdown

# markdown を HTML に変換してブラウザで開く: mdp <file.md>
function mdp() {
  local file="$1"
  if [[ -z "$file" ]]; then
    echo "Usage: mdp <file.md>" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "mdp: no such file: $file" >&2
    return 1
  fi
  if ! command -v pandoc >/dev/null 2>&1; then
    echo "mdp: pandoc が必要です。'brew install pandoc' でインストールしてください。" >&2
    return 1
  fi

  # pandoc のバージョンでオプション名が違うため --help を見て決める
  #   --self-contained  → --embed-resources    (2.19 で改称)
  #   --highlight-style → --syntax-highlighting (3.10 で改称)
  local help embed hl
  help=$(pandoc --help 2>&1)
  if [[ "$help" == *--embed-resources* ]]; then
    embed='--embed-resources'
  else
    embed='--self-contained'
  fi
  if [[ "$help" == *--syntax-highlighting* ]]; then
    hl='--syntax-highlighting'
  else
    hl='--highlight-style'
  fi

  local tmpdir base out
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/mdp.XXXXXXXX") || return 1
  base=$(basename "$file")
  out="${tmpdir}/${base%.*}.html"

  # 本文幅は pandoc 既定の 36em だと狭いので広げる（MDP_MAX_WIDTH で上書き可）
  # コードブロックは明色テーマだと背景色が付かず本文に埋もれるため暗色テーマにする
  # （MDP_HIGHLIGHT_STYLE で上書き可: pandoc --list-highlight-styles 参照）
  pandoc -f gfm -t html --standalone "$embed" --metadata title="$base" \
    "$hl=${MDP_HIGHLIGHT_STYLE:-zenburn}" \
    -V maxwidth="${MDP_MAX_WIDTH:-50em}" -o "$out" "$file" || return 1

  case ${OSTYPE} in
    darwin*) open "$out" ;;
    *)       xdg-open "$out" >/dev/null 2>&1 ;;
  esac
}

# C で標準出力をクリップボードにコピーする
# mollifier delta blog : http://mollifier.hatenablog.com/entry/20100317/p1
if which pbcopy >/dev/null 2>&1 ; then
    # Mac
    alias -g C='| pbcopy'
elif which xsel >/dev/null 2>&1 ; then
    # Linux
    alias -g C='| xsel --input --clipboard'
elif which putclip >/dev/null 2>&1 ; then
    # Cygwin
    alias -g C='| putclip'
fi


########################################
# 後方alias (Mac のみ)
case ${OSTYPE} in
    darwin*)
        ## 画像ファイルをプレビュー
        alias eog='open -a Preview'
        alias -s {png,jpg,bmp,PNG,JPG,BMP}=eog

        ## ブラウザで開く
        alias google-chrome='open -a Google\ Chrome'
        alias chrome='google-chrome'
        alias -s html=chrome
        ;;
esac

########################################
# OS 別の設定
case ${OSTYPE} in
    darwin*)
        #Mac用の設定
        export CLICOLOR=1
        alias ls='ls -G -F'
        ;;
    linux*)
        #Linux用の設定
        export LESSCHARSET=utf-8
        ;;
esac
