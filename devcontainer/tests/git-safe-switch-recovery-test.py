#!/usr/bin/env python3
"""Integration tests for partial worktree writes and recovery guards."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SAFE_SWITCH = Path(__file__).resolve().parents[1] / 'bin/git-safe-switch'
REAL_GIT = shutil.which('git')


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='git-safe-partial-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'test')
        self.git('config', 'user.email', 'test@example.com')
        self.write('a/x', 'old x\n')
        self.write('a/removed', 'original only\n')
        self.write('b/y', 'old y\n')
        self.commit()
        self.orig = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('switch', '-qc', 'target')
        self.write('a/x', 'new x\n')
        self.write('a/new', 'target only\n')
        self.write('b/y', 'new y\n')
        self.write('b/z', 'new z\n')
        (self.repo / 'a/removed').unlink()
        self.commit()
        self.target = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('switch', '-q', 'main')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        # Fault injection surrounds real Git operations; no Git effects are mocked.
        wrapper = self.bin / 'git'
        wrapper.write_text('''#!/usr/bin/env python3
import os, pathlib, subprocess, sys
args = sys.argv[1:]
real = os.environ['TEST_REAL_GIT']
scenario = os.environ['TEST_SCENARIO']
def git(*args):
    return subprocess.run([real, *args], check=True, capture_output=True)
def write(path, text):
    pathlib.Path(path).write_text(text)
if args and args[0] in ('switch', 'merge'):
    if scenario in ('permission', 'retry'):
        os.chmod('b', 0o555)
        try:
            result = subprocess.run([real, *args])
        finally:
            os.chmod('b', 0o755)
        sys.exit(result.returncode)
    result = subprocess.run([real, *args])
    if result.returncode:
        sys.exit(result.returncode)
    if scenario == 'mixed':
        write('b/y', 'old y\\n')
        pathlib.Path('b/z').unlink()
    elif scenario == 'unrelated':
        write('notes', 'user data\\n')
    elif scenario == 'staged':
        write('a/x', 'staged user data\\n')
        git('add', 'a/x')
        write('a/x', 'new x\\n')
    elif scenario == 'mode':
        os.chmod('a/x', 0o755)
    elif scenario == 'symlink':
        pathlib.Path('a/x').unlink()
        pathlib.Path('a/x').symlink_to('new')
    elif scenario == 'collision':
        pathlib.Path('a/removed').mkdir()
        write('a/removed/user-data', 'user data\\n')
    elif scenario == 'untracked-old':
        write('a/removed', 'original only\\n')
    elif scenario == 'bad-data':
        write('a/x', 'user data\\n')
    elif scenario == 'truncated':
        write('a/x', '')
    elif scenario in ('old-index', 'old-index-extra'):
        git('read-tree', os.environ['TEST_ORIG'])
        if scenario == 'old-index-extra':
            write('node/user-data', 'user data\\n')
    elif scenario == 'ignored-collision':
        write('.git/info/exclude', 'a/removed/\\n')
        pathlib.Path('a/removed').mkdir()
        write('a/removed/user-data', 'user data\\n')
    sys.exit(1)
if args and args[0] == 'checkout':
    count = pathlib.Path('.git/recovery-attempts')
    n = int(count.read_text()) + 1 if count.exists() else 1
    count.write_text(str(n))
    if scenario == 'retry' and n == 1:
        os.chmod('a', 0o555)
        try:
            subprocess.run([real, *args])
        finally:
            os.chmod('a', 0o755)
        sys.exit(1)
os.execv(real, [real, *args])
''')
        wrapper.chmod(0o755)

    def git(self, *args):
        return subprocess.run([REAL_GIT, '-C', str(self.repo), *args],
                              text=True, capture_output=True, check=True)

    def write(self, path, text):
        dest = self.repo / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(text)

    def commit(self):
        self.git('add', '-A')
        self.git('commit', '-qm', 'fixture')

    def run_switch(self, scenario, *args, executable=SAFE_SWITCH, cwd=None):
        env = dict(os.environ, TEST_REAL_GIT=REAL_GIT, TEST_SCENARIO=scenario,
                   TEST_ORIG=self.orig,
                   PATH=str(self.bin) + os.pathsep + os.environ['PATH'])
        return subprocess.run([str(executable), *(args or ('target',))], cwd=cwd or self.repo,
                              env=env, text=True, capture_output=True)

    def assert_restored(self, result):
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout.strip(), self.orig)
        self.assertEqual(self.git('branch', '--show-current').stdout.strip(), 'main')
        self.git('diff', '--exit-code')
        self.git('diff', '--cached', '--exit-code')

    def require_permissions(self):
        probe = self.repo / 'b'
        probe.chmod(0o555)
        try:
            if os.access(probe, os.W_OK):
                self.skipTest('write permission denial requires an unprivileged user')
        finally:
            probe.chmod(0o755)

    def test_switch_permission_failure_recovers(self):
        self.require_permissions()
        self.assert_restored(self.run_switch('permission'))

    def test_ff_permission_failure_recovers_and_reports_leftover(self):
        self.require_permissions()
        result = self.run_switch('permission', '--ff', 'target')
        self.assert_restored(result)
        self.assertEqual((self.repo / 'a/new').read_text(), 'target only\n')
        self.assertIn('a/new', result.stderr)

    def test_partial_recovery_can_retry(self):
        self.require_permissions()
        self.assert_restored(self.run_switch('retry'))
        self.assertGreaterEqual(int((self.repo / '.git/recovery-attempts').read_text()), 2)

    def test_old_new_and_missing_tracked_files_are_allowed(self):
        self.assert_restored(self.run_switch('mixed'))

    def test_unrelated_untracked_file_survives_recovery(self):
        self.assert_restored(self.run_switch('unrelated'))
        self.assertEqual((self.repo / 'notes').read_text(), 'user data\n')

    def test_old_version_untracked_file_can_be_restored(self):
        self.assert_restored(self.run_switch('untracked-old'))

    def test_unknown_index_contents_are_preserved(self):
        result = self.run_switch('staged')
        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertEqual(self.git('show', ':a/x').stdout, 'staged user data\n')
        self.assertEqual((self.repo / 'a/x').read_text(), 'new x\n')

    def test_directory_collision_preserves_nested_user_file(self):
        result = self.run_switch('collision')
        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertEqual((self.repo / 'a/removed/user-data').read_text(), 'user data\n')

    def test_ignored_directory_collision_preserves_nested_user_file(self):
        result = self.run_switch('ignored-collision')
        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertEqual((self.repo / 'a/removed/user-data').read_text(), 'user data\n')

    def test_unknown_executable_mode_is_preserved(self):
        self.git('config', 'core.filemode', 'true')
        result = self.run_switch('mode')
        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertTrue((self.repo / 'a/x').stat().st_mode & 0o111)

    def test_unexpected_symlink_is_preserved(self):
        result = self.run_switch('symlink')
        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertTrue((self.repo / 'a/x').is_symlink())

    def test_unknown_worktree_contents_are_preserved(self):
        result = self.run_switch('bad-data')
        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertEqual((self.repo / 'a/x').read_text(), 'user data\n')

    def test_truncated_contents_are_not_assumed_safe(self):
        result = self.run_switch('truncated')
        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertEqual((self.repo / 'a/x').read_bytes(), b'')

    def test_installed_symlink_finds_checker(self):
        link = self.root / 'installed/git-safe-switch'
        link.parent.mkdir()
        link.symlink_to(SAFE_SWITCH)
        self.assert_restored(self.run_switch('mixed', executable=link))

    def test_relative_invocation_from_subdirectory_finds_checker(self):
        subdir = self.repo / 'subdir'
        subdir.mkdir()
        runner = self.repo / 'runner'
        runner.mkdir()
        shutil.copy2(SAFE_SWITCH, runner / SAFE_SWITCH.name)
        shutil.copy2(SAFE_SWITCH.with_name('git-safe-switch-check.py'), runner / 'git-safe-switch-check.py')
        relative = '../runner/git-safe-switch'
        self.assert_restored(self.run_switch('mixed', executable=relative, cwd=subdir))

    def add_topology_transition(self, reverse=False):
        self.write('node/child' if reverse else 'node', 'old node\n')
        self.commit()
        self.orig = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('switch', '-q', 'target')
        self.write('node' if reverse else 'node/child', 'new node\n')
        self.commit()
        self.target = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('switch', '-q', 'main')

    def test_file_to_directory_with_old_index_recovers(self):
        self.add_topology_transition()
        self.assert_restored(self.run_switch('old-index'))
        self.assertEqual((self.repo / 'node').read_text(), 'old node\n')

    def test_directory_to_file_with_old_index_recovers(self):
        self.add_topology_transition(reverse=True)
        self.assert_restored(self.run_switch('old-index'))
        self.assertEqual((self.repo / 'node/child').read_text(), 'old node\n')

    def test_file_to_directory_preserves_unknown_untracked_descendant(self):
        self.add_topology_transition()
        result = self.run_switch('old-index-extra')
        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertEqual((self.repo / 'node/user-data').read_text(), 'user data\n')

    def test_checker_removed_by_target_is_available_for_recovery(self):
        # The installed command and helper may themselves be in the switched repo.
        runner = self.repo / 'runner'
        runner.mkdir()
        shutil.copy2(SAFE_SWITCH, runner / SAFE_SWITCH.name)
        shutil.copy2(SAFE_SWITCH.with_name('git-safe-switch-check.py'), runner / 'git-safe-switch-check.py')
        self.commit()
        self.orig = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('switch', '-q', 'target')
        runner.mkdir(exist_ok=True)
        shutil.copy2(SAFE_SWITCH, runner / SAFE_SWITCH.name)
        self.commit()
        self.git('switch', '-q', 'main')
        link = self.root / 'installed/git-safe-switch'
        link.parent.mkdir()
        link.symlink_to(runner / SAFE_SWITCH.name)
        self.assert_restored(self.run_switch('mixed', executable=link))


if __name__ == '__main__':
    unittest.main()
