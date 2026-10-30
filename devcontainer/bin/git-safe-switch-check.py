#!/usr/bin/env python3
"""復旧対象のファイルとインデックスが新旧どちらかの版に一致する場合だけ許可する。

Git の途中書き込みとして説明できる状態かを判定し、変更の発生元までは特定しない。
新旧いずれかの版へ戻す編集や削除は、途中書き込みと区別しない。
判定と後続の checkout は、単一の原子的な操作ではない。
"""

from bisect import bisect_left
import os
import stat
import subprocess
import sys


def git(*args):
    return subprocess.run(['git', *args], check=True, stdout=subprocess.PIPE).stdout


def tree(revision):
    entries = {}
    for record in git('ls-tree', '-r', '-z', revision).split(b'\0'):
        if record:
            header, path = record.split(b'\t', 1)
            mode, _kind, oid = header.split()
            entries[path] = (mode, oid)
    return entries


def parents(path):
    parts = path.split(b'/')
    return [b'/'.join(parts[:i]) for i in range(1, len(parts))]


def has_descendant(sorted_paths, path):
    prefix = path + b'/'
    i = bisect_left(sorted_paths, prefix)
    return i < len(sorted_paths) and sorted_paths[i].startswith(prefix)


def refuse(path, reason):
    raise ValueError(f'{os.fsdecode(path)!r}: {reason}')


def check(orig_sha, target_sha):
    orig, target = tree(orig_sha), tree(target_sha)
    index = {}
    for record in git('ls-files', '--stage', '-z').split(b'\0'):
        if not record:
            continue
        header, path = record.split(b'\t', 1)
        mode, oid, stage = header.split()
        if stage != b'0' or (mode, oid) not in (orig.get(path), target.get(path)):
            refuse(path, 'インデックスが新旧どちらの版とも一致しません')
        index[path] = (mode, oid)

    # checkout -f は元の版を書き戻すほか、現在のインデックスにあるパスも削除し得る。
    affected = set(orig) | set(index)
    known = set(orig) | set(target)
    known_sorted = sorted(known)
    affected_sorted = sorted(affected)
    # インデックスが旧版、作業ツリーが切り替え先の版なら、ファイルとディレクトリの
    # 入れ替わりもあり得る。重なる切り替え先パスも照合してから未追跡として許可する。
    relevant = affected | {
        path for path in target
        if any(parent in affected for parent in parents(path))
        or has_descendant(affected_sorted, path)
    }
    blob_cache = {}
    for path in sorted(relevant):
        # 親パスにある symlink や通常ファイルをたどって読み込まない。
        blocked = False
        for parent in parents(path):
            try:
                info = os.lstat(parent)
            except FileNotFoundError:
                blocked = True
                break
            if not stat.S_ISDIR(info.st_mode):
                if parent not in relevant:
                    refuse(parent, '復旧対象の親パスがディレクトリではありません')
                # 親パス自体は、新旧のツリーとの照合で別途確認する。
                blocked = True
                break
        if blocked:
            continue
        try:
            info = os.lstat(path)
        except FileNotFoundError:
            continue  # 新旧いずれかのファイルの欠落は、途中書き込みとして許可する。
        if stat.S_ISDIR(info.st_mode):
            if not has_descendant(known_sorted, path):
                refuse(path, '新旧のツリーでは説明できないディレクトリです')
            continue  # 配下の既知パスと未追跡パスは、それぞれ別途確認する。
        if stat.S_ISLNK(info.st_mode):
            mode, content = b'120000', os.readlink(path)
        elif stat.S_ISREG(info.st_mode):
            mode = b'100755' if info.st_mode & 0o111 else b'100644'
            with open(path, 'rb') as stream:
                content = stream.read()
        else:
            refuse(path, '通常ファイルまたはsymlinkではありません')
        matched = False
        for entry in (orig.get(path), target.get(path)):
            if entry is None or entry[0] != mode:
                continue
            oid = entry[1]
            if oid not in blob_cache:
                blob_cache[oid] = git('cat-file', 'blob', oid.decode('ascii'))
            if content == blob_cache[oid]:
                matched = True
                break
        if not matched:
            refuse(path, '内容・種別・実行権限が新旧どちらの版とも一致しません')

    # 強制 checkout は ignored ファイルも壊し得るため、検査対象に含める。
    # 同一パスだけでなく、ファイルとディレクトリの親子関係による衝突も双方向で確認する。
    for path in git('ls-files', '--others', '-z').split(b'\0'):
        if not path or path in relevant:
            continue  # 復旧対象と同一のパスは、上で内容を照合済み。
        if (any(parent in affected for parent in parents(path))
                or has_descendant(affected_sorted, path)):
            refuse(path, '未追跡ファイルが復旧対象の親子パスと衝突します')


if __name__ == '__main__':
    try:
        check(*sys.argv[1:])
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'git-safe-switch: 安全に復旧できると判定できません: {error}', file=sys.stderr)
        sys.exit(1)
