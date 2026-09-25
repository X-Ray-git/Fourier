import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'prepare_release.py'
spec = importlib.util.spec_from_file_location('prepare_release', MODULE)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
NOTES = '## 本版重点\n版本验证\n## 修复与改进\n正文含 `code` 和 $HOME\n**完整变更**\n'


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.old = Path.cwd()
        self.remote = self.root / 'origin.git'
        subprocess.run(['git', 'init', '--bare', str(self.remote)], check=True, capture_output=True)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        os.chdir(self.repo)
        release.git('init', '-b', 'main')
        release.git('config', 'user.name', 'Test')
        release.git('config', 'user.email', 'test@example.invalid')
        release.git('remote', 'add', 'origin', str(self.remote))
        Path('pubspec.yaml').write_text('version: 2.4.0+39\n')
        Path('feature.txt').write_text('original candidate')
        Path('docs/agent_handoff/history').mkdir(parents=True)
        Path('docs/agent_handoff/assets/data').mkdir(parents=True)
        Path('docs/agent_handoff/history/releases.html').write_text('<script type="text/markdown" id="wiki-content">\n</script>')
        Path('docs/agent_handoff/assets/data/search-index.js').write_text('index')
        Path('scripts').mkdir()
        Path('scripts/docs.sh').write_text('#!/bin/sh\nexit 0\n')
        Path('scripts/docs.sh').chmod(0o755)
        release.git('add', '.')
        release.git('commit', '-m', 'candidate')
        self.candidate = release.git('rev-parse', 'HEAD')
        release.git('push', '-u', 'origin', 'main')

    def tearDown(self):
        os.chdir(self.old)
        self.tmp.cleanup()

    def test_normal_release_and_retry(self):
        tag, sha = release.prepare('2.4.1', self.candidate, NOTES, self.candidate)
        self.assertEqual(sha, release.git('rev-parse', 'main'))
        self.assertEqual(release.git('show', f'{tag}:pubspec.yaml'), 'version: 2.4.1+40')
        self.assertEqual(release.prepare('2.4.1', self.candidate, NOTES, self.candidate), (tag, sha))
        self.assertEqual(release.git('rev-parse', 'main'), sha)
        with self.assertRaises(ValueError):
            release.prepare('2.4.1', self.candidate, NOTES + 'changed', sha)

    def test_historical_candidate_does_not_release_later_code(self):
        Path('feature.txt').write_text('later dependency changes')
        release.git('add', '.')
        release.git('commit', '-m', 'later changes')
        head = release.git('rev-parse', 'HEAD')
        release.git('push', 'origin', 'main')
        tag, sha = release.prepare('2.4.1', self.candidate, NOTES, head)
        self.assertEqual(release.git('show', f'{tag}:feature.txt'), 'original candidate')
        self.assertEqual(Path('feature.txt').read_text(), 'later dependency changes')
        self.assertEqual(Path('pubspec.yaml').read_text(), 'version: 2.4.1+40\n')
        self.assertNotEqual(sha, release.git('rev-parse', 'main'))
        self.assertEqual(release.prepare('2.4.1', self.candidate, NOTES, head), (tag, sha))

    def test_dispatcher_returns_after_cloud_acceptance_without_local_tag(self):
        fake_bin = self.root / 'bin'
        fake_bin.mkdir()
        fake_gh = fake_bin / 'gh'
        fake_gh.write_text("#!/usr/bin/env python3\nimport json, os, pathlib, sys\nargs = sys.argv[1:]\nif args[:2] == ['auth', 'status']: pass\nelif args[:2] == ['repo', 'view']: print('owner/repo')\nelif args[:1] == ['api']:\n    assert 'repos/owner/repo/actions/workflows/publish-release.yml/dispatches' in args\n    payload = pathlib.Path(args[args.index('--input') + 1]).read_text()\n    pathlib.Path(os.environ['CAPTURE']).write_text(payload)\nelse: raise SystemExit('Unexpected gh call: ' + repr(args))\n")
        fake_gh.chmod(0o755)
        notes_path = self.root / 'notes.md'
        notes_path.write_text(NOTES)
        env = os.environ.copy()
        env['PATH'] = str(fake_bin) + os.pathsep + env['PATH']
        env['CAPTURE'] = str(self.root / 'request.json')
        subprocess.run(['bash', str(MODULE.with_name('release.sh')), '2.4.1',
                        '--notes-file', str(notes_path), '--push'], check=True, env=env, capture_output=True)
        import json
        payload = json.loads(Path(env['CAPTURE']).read_text())
        self.assertEqual(payload['inputs']['candidate_sha'], self.candidate)
        self.assertEqual(payload['inputs']['notes'], NOTES.strip())
        self.assertEqual(release.git('tag', '--list'), '')
        self.assertEqual(release.git('rev-parse', 'HEAD'), self.candidate)

    def test_changed_main_and_invalid_inputs_fail_before_tag(self):
        with self.assertRaises(ValueError):
            release.prepare('2.4.1', self.candidate, NOTES, '0' * 40)
        with self.assertRaises(ValueError):
            release.prepare('2.4.0', self.candidate, NOTES, self.candidate)
        with self.assertRaises(ValueError):
            release.prepare('2.4.1', self.candidate, 'unstructured', self.candidate)
        self.assertEqual(release.git('tag', '--list'), '')
        self.assertEqual(Path('pubspec.yaml').read_text(), 'version: 2.4.0+39\n')


if __name__ == '__main__':
    unittest.main()
