#!/usr/bin/python3
import json, os, pathlib, shutil, sys
import mockbuild
from mockbuild.util import load_config
args = sys.argv[1:]
call = {'mock': args}
def value(name): return args[args.index(name)+1]
if '--rebuild' in args or '--buildsrpm' in args:
    load_config('/etc/mock', value('-r'), None, 'native-contract',
                str(pathlib.Path(mockbuild.__file__).parent))
    call['config_rc'] = 0
if '--rebuild' in args:
    name = pathlib.Path(value('--rebuild')).name.split('-1-1.oe2403')[0]
    call['name'] = name
if '--buildsrpm' in args:
    call['spec'] = pathlib.Path(value('--spec')).read_text()
with open(os.environ['NATIVE_CALLS'], 'a') as f: f.write(json.dumps(call) + '\n')
if '--buildsrpm' in args:
    dest = pathlib.Path(value('--resultdir')); dest.mkdir(parents=True, exist_ok=True)
    source = json.loads(pathlib.Path(os.environ['NATIVE_OUTPUTS']).read_text())['native-leaf'][1]
    shutil.copyfile(source, dest / pathlib.Path(source).name)
    sys.exit(0)
if '--rebuild' not in args: sys.exit(0)
if name == os.environ.get('NATIVE_FAIL'): sys.exit(42)
dest = pathlib.Path(value('--resultdir')); dest.mkdir(parents=True, exist_ok=True)
if name == os.environ.get('NATIVE_EMPTY'): sys.exit(0)
fixtures = json.loads(pathlib.Path(os.environ['NATIVE_OUTPUTS']).read_text())
for source in fixtures[name]: shutil.copyfile(source, dest / pathlib.Path(source).name)
