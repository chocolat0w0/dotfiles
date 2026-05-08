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
alias -g S='| xargs subl'

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

#> git / log
alias gll='git log  -10 --date=short --pretty=format:'\''%C(yellow)%h%Creset %ad  %C(cyan bold)%an%Creset%x09%C(auto)%d%Creset %s'\'''    # log (10件)
alias glgg='git log --graph --date=short --format="%C(yellow)%h%C(reset) %C(magenta)[%ad]%C(reset)%C(auto)%d%C(reset) %s %C(cyan)@%an%C(reset)"'    # log (graph)
alias glgr='git log --graph --date-order --pretty=format:'\''%Cblue%h %Cgreen%ci %Cred%an %Cblue%m %Creset%s %Cred%d'\'''    # log (graph, date-order)

#> git / other
alias gcp='git cherry-pick'                                                  # cherry-pick
alias grma='git status | grep deleted: | awk '\''{print $2}'\'' | xargs git rm'    # deleted ファイルを git rm
alias grm='git rm'                                                           # rm
alias grmf='rm'                                                              # rm (force, git管理外)
alias grh='git reset --hard HEAD'                                            # reset --hard HEAD
alias grv='git checkout -B reviewing'                                        # reviewing ブランチに checkout
alias gign='git rm -r --cached .; git add .'                                # .gitignore を反映

#> git / worktree
alias gw='git worktree list'                                                 # worktree 一覧
function gwa() { git worktree add "$@" && cd "$1" }                        # worktree 追加して cd
alias gwd='git worktree remove'                                              # worktree 削除
function gwb() { cd "$(git worktree list | head -1 | awk '{print $1}')" }  # メイン worktree に戻る

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
