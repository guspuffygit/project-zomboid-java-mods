"""Windows integration test: local process counters, bounded console tail and process exit."""
from pathlib import Path
import subprocess,os,json,sys,time

module=Path(__file__).resolve().parents[1]
out=Path(sys.argv[1]).resolve()
out.mkdir(parents=True,exist_ok=False)
console=out/'console.txt'
console.write_text('Exception old-session-marker\n',encoding='utf-8')
flags=getattr(subprocess,'CREATE_NO_WINDOW',0)
base=['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(module/'tools/Watch-AdminClient.ps1')]
def records(path):
    return [json.loads(line) for file in path.glob('admin-os-*.jsonl') for line in file.read_text(encoding='utf-8').splitlines()]
watch=subprocess.Popen(base+['-ClientProcessId',str(os.getpid()),'-ConsolePath',str(console),
    '-OutputDirectory',str(out/'running'),'-MaxSamples','3','-IntervalSeconds','1'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,creationflags=flags)
assert 'Monitoring PID' in watch.stdout.readline()
with console.open('a',encoding='utf-8') as file:
    file.write('x'*70000+'\nException timeout at 127.0.0.1\nException password=do-not-record\n'+('Exception repeated\n'*30))
stdout,stderr=watch.communicate(timeout=15)
assert watch.returncode==0,stderr
data=records(out/'running')
sample=next(r['sample'] for r in data if r['kind'] in ['checkpoint','incident'])
assert sample['privateBytesMiB']>0 and sample['workingSetMiB']>0
assert sample.get('systemCommitLimitMiB',0)>0, sample
warnings=[r for r in data if r['kind']=='native_log_warning']
assert warnings and all(len(r['lines'])<=20 for r in warnings)
text=json.dumps(warnings)
assert '127.0.0.1' not in text and 'do-not-record' not in text
assert 'old-session-marker' not in text
assert data[-1]['kind']=='monitor_stopped'
child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(4)'],creationflags=flags)
try:
    completed=subprocess.run(base+['-ClientProcessId',str(child.pid),'-OutputDirectory',str(out/'exit'),
        '-IntervalSeconds','1'],capture_output=True,text=True,timeout=15,creationflags=flags)
    assert completed.returncode==0,completed.stderr
    assert any(r['kind']=='process_exited' for r in records(out/'exit'))
finally:
    child.wait(timeout=5)
print('PASS: Windows memory counters, bounded/redacted console tail, old-log exclusion and process-exit detection')
