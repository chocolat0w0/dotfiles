echo "set prompt"

########################################
# プロンプト右側にGitのブランチ名とステータスを表示する

autoload -Uz VCS_INFO_get_data_git; VCS_INFO_get_data_git 2> /dev/null

function rprompt-git-current-branch {
        local name st color gitdir action
        local max_branch_length=30
        if [[ "$PWD" =~ '/¥.git(/.*)?$' ]]; then
                return
        fi
        name=`git rev-parse --abbrev-ref=loose HEAD 2> /dev/null`
        if [[ -z $name ]]; then
                return
        fi
        if (( ${#name} > max_branch_length )); then
                name="${name[1,14]}…${name[-15,-1]}"
        fi

        gitdir=`git rev-parse --git-dir 2> /dev/null`
        action=`VCS_INFO_git_getaction "$gitdir"` && action="($action)"

        st=`git status 2> /dev/null`
        if [[ -n `echo "$st" | grep "^nothing to"` ]]; then
                color="$LIGHTBLUE"
        elif [[ -n `echo "$st" | grep "^nothing added"` ]]; then
                color="$YELLOW"
        elif [[ -n `echo "$st" | grep "^Untracked"` ]]; then
                color="%S%B%F%U%{\e[38;5;202m%} !! "
        else
                # color="%S%B%F%{\e[38;5;200m%}"
                color="%S%B"$PINK
        fi

        echo "[$color$name$action%u%f%b%s]"
}

setopt prompt_subst
setopt transient_rprompt

RPROMPT='`rprompt-git-current-branch`'


########################################
# ターミナルタイトル
##  set terminal title including current directory
case "${TERM}" in
kterm*|xterm*)
  if [ -n "${REMOTEHOST}${SSH_CONNECTION}" ]
  then
    precmd() {
      echo -ne "\033]0;${USER}@${HOST%%.*}:${PWD}\007"
    }
  else
    precmd() {
      echo -ne "\033]0;${PWD}\007"
    }
  fi
esac
