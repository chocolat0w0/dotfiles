# 補完機能を有効にする
# because:複数ファイル内でcomp関数を呼ぶため事前に初期化
autoload -Uz compinit
compinit

# .zdh.dディレクトリ内のファイル読み込み
ZSHHOME="${HOME}/.zsh.d"

if [ -d $ZSHHOME -a -r $ZSHHOME -a \
     -x $ZSHHOME ]; then
    for i in $ZSHHOME/*; do
        [[ ${i##*/} = *.zsh ]] &&
            [ \( -f $i -o -h $i \) -a -r $i ] && . $i
    done
fi
if command -v anyenv >/dev/null 2>&1; then
    eval "$(anyenv init -)"
fi
