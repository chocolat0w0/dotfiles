#!/usr/bin/env python3
"""Allow rollback only when affected files/index entries match either commit.

This recognizes a possible partial Git write, not its provenance. An edit back
to either committed version (or a deletion) is intentionally indistinguishable.
Checks and the following checkout are not one atomic transaction.
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

    # checkout -f may remove entries in the current index as well as write orig.
    affected = set(orig) | set(index)
    known = set(orig) | set(target)
    known_sorted = sorted(known)
    affected_sorted = sorted(affected)
    # Old index + target worktree can include a file/directory replacement.
    # Validate overlapping target paths before accepting them as untracked.
    relevant = affected | {
        path for path in target
        if any(parent in affected for parent in parents(path))
        or has_descendant(affected_sorted, path)
    }
    blob_cache = {}
    for path in sorted(relevant):
        # Never read through a symlink or a file in an ancestor component.
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
                # The ancestor itself is checked independently against the trees.
                blocked = True
                break
        if blocked:
            continue
        try:
            info = os.lstat(path)
        except FileNotFoundError:
            continue  # Missing old/new files can be a partial write.
        if stat.S_ISDIR(info.st_mode):
            if not has_descendant(known_sorted, path):
                refuse(path, '新旧のツリーでは説明できないディレクトリです')
            continue  # Its known children and untracked descendants are checked below.
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

    # Include ignored files: forced checkout can destroy them too. Check both
    # directions of a file/directory collision, not just identical path names.
    for path in git('ls-files', '--others', '-z').split(b'\0'):
        if not path or path in relevant:
            continue  # Exact affected paths were content-checked above.
        if (any(parent in affected for parent in parents(path))
                or has_descendant(affected_sorted, path)):
            refuse(path, '未追跡ファイルが復旧対象の親子パスと衝突します')


if __name__ == '__main__':
    try:
        check(*sys.argv[1:])
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'git-safe-switch: 安全に復旧できると判定できません: {error}', file=sys.stderr)
        sys.exit(1)
