#!/usr/bin/env python3
"""Owned native lab checks. --physical is required to qualify tracking-area hover."""
import argparse
import json
import time
import urllib.request
from urllib.parse import urlparse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('url', help='Loopback MODAL_LAB_URL printed by flutter run')
parser.add_argument('--physical', action='store_true', help='Move the real mouse continuously over the lab during each phase')
parser.add_argument('--seconds', type=float, default=10, help='Real mouse observation interval per phase')
parser.add_argument('--output', default=None)
args = parser.parse_args()
base = args.url.rstrip('/')
assert urlparse(base).hostname in ('127.0.0.1', 'localhost'), 'Use only the owned loopback lab'
assert 1 <= args.seconds <= 60
output = Path(args.output or ('evidence/physical-qualification.json' if args.physical else 'evidence/routing-smoke.json'))

def request(path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=8) as response:
        return json.load(response)

def state(): return request('/state')
def action(name, **kwargs): return request('/action', {'action': name, **kwargs})
def wait(predicate, description):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        snapshot = state()
        if snapshot.get('error'): raise RuntimeError(snapshot['error'])
        if predicate(snapshot): return snapshot
        time.sleep(.12)
    raise RuntimeError('Timed out: ' + description)

def sample(label):
    action('reset')
    before = state()
    print(label + (': MOVE THE REAL MOUSE over the webpage and popup now' if args.physical else ': self-posted routing probe'), flush=True)
    if args.physical:
        time.sleep(args.seconds)
    else:
        for x, y in [(.85, .72), (.86, .74), (.87, .76), (.84, .78), (.82, .72), (.88, .70)]:
            action('pointer', type='move', x=x, y=y)
            time.sleep(.08)
        time.sleep(.25)
    observed = state()
    report['runs'].append({'phase': label, 'before': before, 'snapshot': observed})
    assert observed['page']['loadId'] == identity, 'WebView reloaded'
    assert observed['page']['text'] == original_text, 'WebView field changed'
    return before, observed

def count(s):
    types = ['mousemove', 'pointermove', 'iframe:mousemove', 'iframe:pointermove', 'mousedown', 'mouseup', 'click', 'wheel']
    return sum(v for k, v in s['page']['counts'].items() if k in types)

report = {'tag': 'WV-MODAL-GUARD', 'input': 'physical mouse' if args.physical else 'self-posted NSEvents',
          'trackingAreaQualified': False, 'routingSmokePassed': False, 'runs': []}
initial = wait(lambda s: s['ready'], 'probe loaded')
assert initial['dialogs'] == 0, 'Close existing dialogs before qualification'
identity, original_text = initial['page']['loadId'], initial['page']['text']
try:
    for enabled, kind in [(False, 'Settings'), (True, 'Settings'), (True, 'URL')]:
        action('mode', guarded=enabled)
        action('open', kind=kind)
        wait(lambda s: s['dialogs'] == 1 and s['guard']['leases'] == int(enabled), 'dialog open')
        time.sleep(.3)
        before, observed = sample(('Protected ' if enabled else 'Baseline ') + kind)
        if enabled:
            assert count(observed) == 0, 'Page input leaked'
            assert observed['popupMoves'] > 0, 'No input reached Flutter; zero DOM counts prove nothing'
            assert observed['guard']['routed'] > before['guard']['routed'], 'Native monitor did not see input'
            assert observed['page']['scrollY'] == before['page']['scrollY'], 'Page scrolled behind modal'
            action('nested')
            wait(lambda s: s['dialogs'] == 2 and s['guard']['leases'] == 2, 'nested scope')
            action('close')
            wait(lambda s: s['dialogs'] == 1 and s['guard']['leases'] == 1, 'nested close')
            _, nested = sample('Protected parent after nested close')
            assert count(nested) == 0 and nested['popupMoves'] > 0
        elif args.physical:
            assert count(observed) > 0, 'Baseline did not reproduce; qualification is inconclusive'
        action('close')
        wait(lambda s: s['dialogs'] == 0 and s['guard']['leases'] == 0, 'dialog fully removed')
        _, restored = sample('WebView after close')
        if args.physical: assert count(restored) > 0, 'WebView input did not recover'
    report['routingSmokePassed'] = True
    report['trackingAreaQualified'] = args.physical
except Exception as exception:
    report['failure'] = str(exception)
    raise
finally:
    try:
        while state()['dialogs'] > 0:
            action('close')
            time.sleep(.4)
        action('mode', guarded=True)
    finally:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({'routingSmokePassed': report['routingSmokePassed'],
                          'trackingAreaQualified': report['trackingAreaQualified'], 'evidence': str(output)}), flush=True)
