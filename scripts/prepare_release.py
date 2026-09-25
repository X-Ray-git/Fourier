#!/usr/bin/env python3
"""Prepare an immutable release after cloud preflight; never force-push tags."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile


def git(*args, cwd=None):
    return subprocess.check_output(['git', *args], cwd=cwd, text=True).strip()


def version_of(text):
    match = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)$', text, re.M)
    if not match:
        raise ValueError('Invalid pubspec version')
    return tuple(map(int, match[1].split('.'))), int(match[2])


def write_metadata(root, version, build, candidate, notes):
    root = Path(root)
    pubspec = root / 'pubspec.yaml'
    pubspec.write_text(re.sub(r'^version: .*$', f'version: {version}+{build}', pubspec.read_text(), flags=re.M))
    history = root / 'docs/agent_handoff/history/releases.html'
    text = history.read_text()
    start = text.index('<script type="text/markdown" id="wiki-content">')
    end = text.index('</script>', start)
    section = f'\n## v{version}\n\nCloud release; candidate `{candidate}`, build `{build}`.\n\n{notes}\n'
    history.write_text(text[:end] + section.replace('</script>', '<\\/script>') + text[end:])
    subprocess.run(['./scripts/docs.sh', 'index'], cwd=root, check=True)
    subprocess.run(['./scripts/docs.sh', 'check'], cwd=root, check=True)
    git('add', 'pubspec.yaml', 'docs/agent_handoff/history/releases.html',
        'docs/agent_handoff/assets/data/search-index.js', cwd=root)
    git('commit', '-m', f'chore: bump version to {version}+{build}', cwd=root)
    return git('rev-parse', 'HEAD', cwd=root)


def prepare(version, candidate, notes, expected_main):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Invalid release version')
    if not re.fullmatch(r'[0-9a-f]{40}', candidate):
        raise ValueError('Candidate must be a full commit SHA')
    if '## 本版重点' not in notes or '**完整变更**' not in notes or not any(
        h in notes for h in ('## 新功能', '## 修复与改进', '## 升级说明', '## 重要变更', '## 性能改进')
    ):
        raise ValueError('Release notes must use the standard structure')
    git('fetch', 'origin', 'main', '--tags')
    subprocess.run(['git', 'merge-base', '--is-ancestor', candidate, 'origin/main'], check=True)
    tag = f'v{version}'
    exists = subprocess.run(['git', 'rev-parse', '--verify', f'refs/tags/{tag}'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if exists:
        # A failed upload can be retried without bumping, retagging or changing scope.
        if git('cat-file', '-t', f'refs/tags/{tag}') != 'tag':
            raise ValueError('Existing release tag is not annotated')
        if git('rev-parse', f'{tag}^') != candidate:
            raise ValueError('Existing release tag has a different candidate')
        if git('tag', '-l', '--format=%(contents)', tag) != notes.strip():
            raise ValueError('Existing release notes differ')
        tagged_version, _ = version_of(git('show', f'{tag}:pubspec.yaml'))
        if tagged_version != tuple(map(int, version.split('.'))):
            raise ValueError('Existing tag version mismatch')
        return tag, git('rev-parse', f'{tag}^{{commit}}')
    if git('rev-parse', 'origin/main') != expected_main:
        raise ValueError('main changed during preflight; dispatch again with an explicit candidate')
    if git('status', '--porcelain'):
        raise ValueError('Dirty release checkout')
    git('checkout', '-B', 'main', 'origin/main')
    current_version, current_build = version_of(Path('pubspec.yaml').read_text())
    if tuple(map(int, version.split('.'))) <= current_version:
        raise ValueError('Release version must increase')
    build = current_build + 1
    # Historical main candidates support recovery without silently including
    # later changes. main receives metadata only; the tag keeps candidate application code
    # and current approved release automation.
    if candidate == expected_main:
        release_sha = write_metadata('.', version, build, candidate, notes)
    else:
        with tempfile.TemporaryDirectory(prefix='fourier-release-') as tmp:
            checkout = str(Path(tmp) / 'candidate')
            git('worktree', 'add', '--detach', checkout, candidate)
            try:
                # GitHub treats a historical tag's workflow difference from
                # default main as a workflow write. Keep approved automation
                # identical to main; application code/lockfile stay pinned.
                paths = ['.github/workflows']
                for path in ('scripts/release.sh', 'scripts/prepare_release.py',
                             'scripts/tests/test_prepare_release.py'):
                    if git('ls-tree', expected_main, '--', path):
                        paths.append(path)
                git('restore', '--source', expected_main, '--staged', '--worktree',
                    '--', *paths, cwd=checkout)
                if git('diff', '--cached', expected_main, '--', '.github/workflows', cwd=checkout):
                    raise ValueError('Release workflows must match approved main')
                release_sha = write_metadata(checkout, version, build, candidate, notes)
            finally:
                git('worktree', 'remove', checkout)
        write_metadata('.', version, build, candidate, notes)
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8') as file:
        file.write(notes)
        file.flush()
        git('tag', '-a', tag, release_sha, '--cleanup=verbatim', '-F', file.name)
    # Fail atomically on a concurrently advanced main; never publish a tag alone.
    git('push', '--atomic', 'origin', 'main', f'refs/tags/{tag}')
    return tag, release_sha


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--expected-main', required=True)
    parser.add_argument('--notes-file', required=True)
    args = parser.parse_args()
    tag, sha = prepare(args.version, args.candidate, Path(args.notes_file).read_text(), args.expected_main)
    print(f'Prepared {tag}: {sha}')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'tag={tag}\nsha={sha}\n')
