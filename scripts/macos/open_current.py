#!/usr/bin/env python3
"""Build and open one exact project/scheme/app; prove the running process is ready."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time
import build_provenance as provenance


def run(*args, capture=False):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE if capture else None, check=True)
    return (result.stdout or '').strip()


def executable_path(pid):
    library = ctypes.CDLL('/usr/lib/libproc.dylib')
    buffer = ctypes.create_string_buffer(4096)
    size = library.proc_pidpath(int(pid), buffer, len(buffer))
    if size <= 0:
        raise RuntimeError('Reported app process is no longer running')
    return str(Path(os.fsdecode(buffer.value)).resolve())


def verify_running(ticket, receipt, expected_executable, current_executable):
    for key in ('session', 'build_id', 'commit', 'input_hash', 'target', 'configuration'):
        if receipt.get(key) != ticket[key]:
            raise RuntimeError(f'Running app differs from the reviewed build: {key}')
    if not receipt.get('window_ready'):
        raise RuntimeError('Normal startup window is not ready')
    if receipt.get('executable') != expected_executable or current_executable != expected_executable:
        raise RuntimeError('Running executable path differs from the built app')


def open_project(project, scheme):
    run('/usr/bin/open', '-a', 'Xcode', str(project))
    script = '''on run argv
set projectPath to item 1 of argv
set schemeName to item 2 of argv
set alternatePath to item 3 of argv
tell application "Xcode"
  repeat 120 times
    repeat with doc in workspace documents
      if (path of doc as text) is projectPath or (path of doc as text) is alternatePath then
        if loaded of doc then
          set active scheme of doc to first scheme of doc whose name is schemeName
          return (path of doc as text) & linefeed & (name of active scheme of doc)
        end if
      end if
    end repeat
    delay 0.25
  end repeat
end tell
error "Exact Xcode project/scheme could not be confirmed"
end run'''
    result = run('/usr/bin/osascript', '-e', script, str(project), scheme, str(project).replace('/private/tmp/', '/tmp/', 1), capture=True).splitlines()
    if len(result) != 2 or Path(result[0]).resolve() != project.resolve() or result[1] != scheme:
        raise RuntimeError('Xcode reported a different project or active scheme')
    return {'project': result[0], 'scheme': result[1]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--worktree', type=Path)
    parser.add_argument('--scheme', default='SIDEYAppStore', choices=['SIDEYAppStore', 'sidey-reals'])
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--build-only', action='store_true')
    args = parser.parse_args()
    root = (args.worktree or provenance.ROOT).resolve()
    if root != provenance.ROOT:
        # Execute the version of the tool belonging to the selected source tree.
        os.execv('/usr/bin/python3', ['/usr/bin/python3', str(root / 'scripts/macos/open_current.py'), *sys.argv[1:]])
    if not args.worktree:
        # Direct shell invocation has the same latest-main default as workflow open.
        records = run('git', '-C', str(root), 'worktree', 'list', '--porcelain', capture=True)
        primary = Path(records.splitlines()[0].split(' ', 1)[1]).resolve()
        workflow = root / 'scripts/skills/workflow.py'
        if not workflow.exists():
            raise RuntimeError('Use an explicit --worktree preview until the shared workflow is integrated')
        command = [sys.executable, str(workflow), '--repo', str(primary), 'open', '--scheme', args.scheme]
        if args.offline:
            raise RuntimeError('--offline requires an explicit --worktree')
        run(*command)
        return
    remote = None
    if not args.offline:
        run('git', '-C', str(root), 'fetch', '--no-tags', 'origin', '+refs/heads/main:refs/remotes/origin/main')
        remote = run('git', '-C', str(root), 'rev-parse', 'origin/main', capture=True)
        run('git', '-C', str(root), 'merge-base', '--is-ancestor', remote, 'HEAD')
    identifier = hashlib.sha256(str(root).encode()).hexdigest()[:16]
    derived = root / 'build/review' / identifier / args.scheme / 'Debug'
    project = root / ('macos/Recording/SIDEYRecording.xcodeproj' if args.scheme == 'sidey-reals' else 'macos/SIDEY.xcodeproj')
    # Persist only this worktree's Xcode personal DerivedData preference.
    username = __import__('getpass').getuser()
    settings = project / 'project.xcworkspace/xcuserdata' / f'{username}.xcuserdatad/WorkspaceSettings.xcsettings'
    settings.parent.mkdir(parents=True, exist_ok=True)
    value = plistlib.loads(settings.read_bytes()) if settings.exists() else {}
    value.update(DerivedDataLocationStyle='AbsolutePath', DerivedDataCustomLocation=str(derived))
    settings.write_bytes(plistlib.dumps(value))
    before = provenance.source_state()
    run('xcodebuild', '-project', str(project), '-scheme', args.scheme, '-configuration', 'Debug',
        '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', str(derived), 'build')
    product = 'sidey-reals' if args.scheme == 'sidey-reals' else 'SIDEY'
    app = derived / f'Build/Products/Debug/{product}.app'
    stamp, _ = provenance.verify(app, target=args.scheme, configuration='Debug')
    if before != provenance.source_state():
        raise RuntimeError('Source changed during the requested build; rebuild required')
    if args.build_only:
        print(json.dumps({'app': str(app), 'build': stamp, 'running_verified': False}, indent=2))
        return
    xcode = open_project(project, args.scheme)
    ticket, ready_path = provenance.prepare_launch(app, args.scheme)
    # -n requests this absolute artifact; it does not reuse a same-named installed app.
    run('/usr/bin/open', '-n', str(app))
    for _ in range(400):
        if ready_path.exists():
            receipt = json.loads(ready_path.read_text())
            verify_running(ticket, receipt, ticket['executable'], executable_path(receipt['pid']))
            provenance.verify(app, target=args.scheme, configuration='Debug')
            if not args.offline:
                run('git', '-C', str(root), 'fetch', '--no-tags', 'origin', '+refs/heads/main:refs/remotes/origin/main')
                if remote != run('git', '-C', str(root), 'rev-parse', 'origin/main', capture=True):
                    raise RuntimeError('Remote main advanced during app review; freshness invalidated')
            print(json.dumps({**xcode, 'source': str(root), 'remote_main': remote,
                'freshness': 'unverified-offline' if args.offline else 'verified',
                'app': str(app), 'running': receipt}, ensure_ascii=False, indent=2))
            return
        time.sleep(0.1)
    raise RuntimeError('App did not report this session/build/executable and a ready startup window')


if __name__ == '__main__':
    main()
