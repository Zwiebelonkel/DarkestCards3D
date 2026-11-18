import concurrent.futures
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'docs' / 'game-documentation' / 'audit'
OUTPUT.mkdir(parents=True, exist_ok=True)
GODOT = Path(r'C:\Users\Luca\Desktop\Godot_v4.4.1-stable_win64.exe')
POWERSHELL = Path(sys.executable).parents[1] / 'native' / 'powershell' / 'pwsh.exe'
if not POWERSHELL.exists():
    POWERSHELL = Path(r'C:\Program Files\WindowsApps\OpenAI.CodexPrimaryRuntime.v26-1112-737-0_26.1112.737.0_x64__3k8sg7r9htsxt\dependencies\native\powershell\pwsh.exe')
SKIP = {'basement_cat_backend_test', 'black_market_backend_test', 'cat_clicker_backend_test',
        'native_peer_lifetime_test', 'progression_test', 'rolling_audio_audibility_test'}
LOCK = threading.Lock()
RESULTS = []

def run_suite(scene):
    suite = scene.stem
    source = scene.with_suffix('.gd').read_text(encoding='utf-8-sig')
    marker = re.search(r'([A-Z0-9_]+_TESTS):', source)
    if not marker or suite in SKIP:
        return {'suite': suite, 'status': 'not_run', 'reason': 'special runner or custom completion contract'}
    start = time.monotonic()
    flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
    prep = subprocess.run([str(POWERSHELL), '-NoProfile', '-File', str(ROOT / 'tools/documentation_audit/prepare_test.ps1'), '-Suite', suite], capture_output=True, text=True, creationflags=flags, timeout=60)
    if prep.returncode:
        return {'suite': suite, 'status': 'setup_failed', 'details': prep.stderr[-3000:]}
    fixture = prep.stdout.strip().splitlines()[-1]
    log_path = OUTPUT / f'{suite}.log'
    command = [str(GODOT), '--headless', '--audio-driver', 'Dummy', '--path', fixture,
               '--log-file', str(log_path), '--quit-after', '12000', '--max-fps', '240', f'res://tests/{suite}.tscn']
    status = 'failed'
    try:
        process = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace', creationflags=flags, timeout=55)
        code = process.returncode
        output = process.stdout + '\n' + process.stderr
        if log_path.exists():
            output += '\n' + log_path.read_text(encoding='utf-8-sig', errors='replace')
        passed = marker.group(1) + ': PASS'
        if code == 0 and passed in output:
            status = 'passed'
    except subprocess.TimeoutExpired as error:
        code = None
        output = log_path.read_text(encoding='utf-8-sig', errors='replace') if log_path.exists() else str(error)
        status = 'timeout'
    checks = re.findall(r'\b(?:PASS|FAIL)\s*\((\d+) checks\)', output)
    failures = list(dict.fromkeys(re.findall(r'(?m)^.*(?:FAIL[: ]|SCRIPT ERROR:|Parse Error:|SHADER ERROR:).*$' , output)))
    engine_errors = list(dict.fromkeys(re.findall(r'(?m)^ERROR:.*$', output)))
    warnings = list(dict.fromkeys(re.findall(r'(?m)^WARNING:.*$', output)))
    return {'suite': suite, 'status': status, 'checks': int(checks[-1]) if checks else None,
            'seconds': round(time.monotonic()-start, 2), 'exit_code': code,
            'failure_lines': failures[:30], 'engine_errors': engine_errors[:15],
            'warnings': warnings[:8], 'fixture': fixture, 'log': str(log_path),
            'marker': marker.group(1) + ': PASS'}

def save(result):
    with LOCK:
        RESULTS.append(result)
        report = {'recorded_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'engine': 'Godot 4.4.1', 'mode': 'headless with isolated saves and Steam fixture',
                  'source': str(ROOT), 'results': sorted(RESULTS, key=lambda r:r['suite'])}
        (OUTPUT / 'test-results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        print(f"{len(RESULTS):3d} {result['status']:12s} {result['suite']} ({result.get('checks')})", flush=True)

if __name__ == '__main__':
    scenes = sorted((ROOT / 'tests').glob('*test.tscn'))
    print(f'Auditing {len(scenes)} scene suites', flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        futures = {pool.submit(run_suite, s):s for s in scenes}
        for future in concurrent.futures.as_completed(futures):
            try:
                save(future.result())
            except Exception as error:
                save({'suite': futures[future].stem, 'status': 'runner_error', 'details': str(error)})
    print('DOCUMENTATION_AUDIT_COMPLETE', flush=True)
