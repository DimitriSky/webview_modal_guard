#!/usr/bin/env python3
"""Launch the owned lab and check real engine restart/background registration.

Run from example/. Uses its loopback diagnostic API; does not inject OS input.
"""
import json
import queue
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

process = subprocess.Popen(
    ['flutter', 'run', '-d', 'macos', '--no-pub'], stdin=subprocess.PIPE,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
)
urls = queue.Queue()
reloads = queue.Queue()


def read_output():
    for line in process.stdout:
        if 'MODAL_LAB_URL=' in line:
            urls.put(line.split('MODAL_LAB_URL=', 1)[1].strip())
        if line.strip().startswith('Reloaded '):
            reloads.put(True)


threading.Thread(target=read_output, daemon=True).start()
base = ''
report = {'tag': 'WV-MODAL-GUARD', 'kind': 'engine lifecycle', 'passed': False, 'runs': []}


def request(path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=8) as response:
        return json.load(response)


def wait(dialogs, leases):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        state = request('/state')
        if state['error']:
            raise RuntimeError(state['error'])
        if state['ready'] and state['dialogs'] == dialogs and state['guard']['leases'] == leases:
            return {'dialogs': state['dialogs'], 'guard': state['guard']}
        time.sleep(.1)
    raise RuntimeError(f'Expected dialogs={dialogs}, leases={leases}; got {state["guard"]}')


def action(name, **kwargs):
    return request('/action', {'action': name, **kwargs})


try:
    base = urls.get(timeout=180)
    report['initial'] = wait(0, 0)
    for kind in ['Settings', 'URL']:
        action('open', kind=kind)
        wait(1, 1)
        action('nested')
        opened = wait(2, 2)
        background = action('background')
        assert background['leases'] == 2, 'Background registration cleared UI protection'
        wait(2, 2)
        process.stdin.write('r\n')
        process.stdin.flush()
        reloads.get(timeout=30)
        reloaded = wait(2, 2)
        print(f'{kind}: nested + background registration + hot reload passed; restarting', flush=True)
        process.stdin.write('R\n')
        process.stdin.flush()
        base = urls.get(timeout=30)
        restarted = wait(0, 0)
        action('open', kind=kind)
        reopened = wait(1, 1)
        action('close')
        closed = wait(0, 0)
        report['runs'].append({'popup': kind, 'beforeRestart': opened,
                               'background': background, 'afterHotReload': reloaded,
                               'afterRestart': restarted,
                               'reopened': reopened, 'closed': closed})
    subprocess.run([sys.executable, 'tool/qualify.py', base, '--output',
                    'evidence/review-routing-smoke.json'], check=True)
    report['routingSmokeAfterRestarts'] = True
    report['passed'] = True
    print('Engine lifecycle qualification passed', flush=True)
except Exception as error:
    report['failure'] = str(error)
    raise
finally:
    if process.poll() is None:
        try:
            process.stdin.write('q\n')
            process.stdin.flush()
            process.wait(timeout=15)
        except (BrokenPipeError, subprocess.TimeoutExpired):
            process.terminate()
            process.wait(timeout=10)
    output = Path('evidence/engine-lifecycle.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
