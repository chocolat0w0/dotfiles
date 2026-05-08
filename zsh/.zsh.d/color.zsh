echo "set color"

########################################
# 色の定義
local DEFAULT=$'%{\e[m%}'$
# local DEFAULT="%{\e[m%}"
local LIGHTBLUE="%F%{\e[38;5;044m%}"
local YELLOW="%F%{\e[38;5;011m%}"
local PINK="%S%B%F%{\e[38;5;200m%}"


########################################
# プロンプトに色を付ける
autoload -Uz colors; colors
# 一般ユーザ時
tmp_prompt="%{${fg[cyan]}%}%n%# %{${reset_color}%}"
tmp_prompt2="%{${fg[cyan]}%}%_> %{${reset_color}%}"
tmp_rprompt="%{${fg[green]}%}[%~]%{${reset_color}%}"
tmp_sprompt="%{${fg[yellow]}%}%r is correct? [Yes, No, Abort, Edit]:%{${reset_color}%}"

# rootユーザ時(太字にし、アンダーバーをつける)
if [ ${UID} -eq 0 ]; then
  tmp_prompt="%B%U${tmp_prompt}%u%b"
  tmp_prompt2="%B%U${tmp_prompt2}%u%b"
  tmp_rprompt="%B%U${tmp_rprompt}%u%b"
  tmp_sprompt="%B%U${tmp_sprompt}%u%b"
fi

PROMPT=$tmp_prompt    # 通常のプロンプト
PROMPT2=$tmp_prompt2  # セカンダリのプロンプト(コマンドが2行以上の時に表示される)
RPROMPT=$tmp_rprompt  # 右側のプロンプト
SPROMPT=$tmp_sprompt  # スペル訂正用プロンプト

# SSHログイン時のプロンプト
[ -n "${REMOTEHOST}${SSH_CONNECTION}" ] &&
  PROMPT="%{${fg[white]}%}${HOST%%.*} ${PROMPT}"
;


########################################
# 色付け
## terminal configuration
#
unset LSCOLORS
case "${TERM}" in
xterm*)
  export TERM=xterm-color
  unset LANG
  export CLICOLOR=1
  export LSCOLORS=DxGxcxdxCxegedabagacad
  export LS_COLORS='di=33:ln=36:so=32:pi=33:ex=31:bd=46;34:cd=43;34:su=41;30:sg=46;30:tw=42;30:ow=43;30'
  zstyle ':completion:*' list-colors \
    'di=33' 'ln=36' 'so=32' 'ex=31' 'bd=46;34' 'cd=43;34'
  ;;
kterm*)
  export TERM=kterm-color
  # set BackSpace control character
  stty erase
  ;;
cons25*)
  ;;
esac

