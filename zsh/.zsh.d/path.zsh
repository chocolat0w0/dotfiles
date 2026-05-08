########################################
# PATH
echo "set path"

## 重複パスを登録しない
typeset -U path cdpath fpath manpath

## sudo用のpathを設定
typeset -xT SUDO_PATH sudo_path
typeset -U sudo_path
sudo_path=({/usr/local,/usr,}/sbin(N-/))

## pathを設定
## (N-/)は存在しないディレクトリを排除する
path=(
      ${HOME}/.anyenv/envs/nodenv/shims(N-/)
      ${HOME}/.anyenv/envs/nodenv/bin(N-/)
      ${HOME}/.anyenv/envs/pyenv/shims(N-/)
      /opt/homebrew/bin(N-/)
      /opt/homebrew/sbin(N-/)
      /opt/homebrew/opt/libpq/bin(N-/)
      /opt/homebrew/opt/postgresql@13/bin(N-/)
      /usr/local/bin(N-/)
      /usr/bin(N-/)
      /usr/sbin(N-/)
      /sbin(N-/)
      ${HOME}/minio-binaries/(N-/)
      ${path})

## brewの時、Homebrew以外のパスを通らないようにする（doctorでのWarning対応）
## https://zenn.dev/ryuu/scraps/fddefc2ca60f88
if [ "$(uname -m)" = "arm64" ]; then
  alias brew="PATH=/opt/homebrew/bin brew"
else
  alias brew="PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin brew"
fi
