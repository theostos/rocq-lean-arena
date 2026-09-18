import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


def load(name):
    path = Path(__file__).with_name(name + '.py')
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class HandoffTests(unittest.TestCase):
    def test_private_index_preserves_worktree_index_and_authorship(self):
        s = load('snapshot_sources')
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp) / 'repo'
            repo.mkdir()
            s.git(repo, 'init', '-q')
            (repo / 'tracked').write_text('before\n')
            s.git(repo, 'add', 'tracked')
            s.git(repo, *s.IDENTITY, 'commit', '-qm', 'base')
            (repo / 'tracked').write_text('staged\n')
            s.git(repo, 'add', 'tracked')
            (repo / 'tracked').write_text('working\n')
            (repo / 'extra').write_text('extra\n')
            (repo / 'link').symlink_to('extra')
            before = s.git(repo, 'status', '--porcelain=v1')
            output = Path(temp) / 'receipt.json'
            s.snapshot(repo, repo, 'handoff/test', [Path('extra'), Path('link')], 'test', output)
            record = json.loads(output.read_text())
            self.assertEqual(before, s.git(repo, 'status', '--porcelain=v1'))
            self.assertEqual(s.git(repo, 'show', record['commit'] + ':tracked'), b'working\n')
            self.assertEqual(s.git(repo, 'show', record['commit'] + ':link'), b'extra')
            self.assertEqual(s.git(repo, 'log', '-1', '--format=%an', record['commit']).strip(), b'Codex')
            with self.assertRaises(RuntimeError):
                s.snapshot(repo, repo, 'handoff/test', [], 'test', Path(temp) / 'again.json')

    def test_source_selection_includes_manifest_not_binaries(self):
        s = load('snapshot_sources')
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ('HANDOFF.md', 'docs/handoff-20260918.json', 'work/demo/result.json',
                         'work/demo/code.ml', 'work/demo/file.vo', 'work/demo/file.log',
                         'work/demo/attempts/live/result.json', 'work/handoff-20260918/huge.json'):
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('{}')
            names = set(map(str, s.arena_extra(root)))
            self.assertEqual(names, {'HANDOFF.md', 'docs/handoff-20260918.json',
                                    'work/demo/result.json', 'work/demo/code.ml'})

    def test_evidence_roundtrip_and_no_overwrite(self):
        e = load('package_evidence')
        with tempfile.TemporaryDirectory() as temp:
            e.ROOT = Path(temp)
            p = e.ROOT / 'work/demo/result.json'
            p.parent.mkdir(parents=True)
            p.write_text('{"exit_code":0}')
            e.candidates = lambda: iter([p])
            output = e.ROOT / 'evidence.tar.gz'
            e.pack(output)
            e.verify(output)
            with self.assertRaises(RuntimeError):
                e.pack(output)


if __name__ == '__main__':
    unittest.main()
