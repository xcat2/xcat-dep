#!/usr/bin/python3
import json, os, pathlib, shutil, sys
from mockbuild.config import load_config
args = sys.argv[1:]
call = {'mock': args}
config = None
def value(name): return args[args.index(name)+1]

def resultdir(path):
    """Create --resultdir and open its logs the way mock does.

    mock 6.8 reloads its uid manager from chrootuid, so it creates --resultdir and opens
    state.log, build.log and root.log in it as that uid, not as the user that started mock.
    """
    uid, gid = config['chrootuid'], config['chrootgid']
    pid = os.fork()
    if pid == 0:
        try:
            if os.geteuid() == 0:
                os.setregid(gid, gid)
                os.setresuid(uid, uid, 0)
            os.makedirs(path, exist_ok=True)
            for name in ('state.log', 'build.log', 'root.log'):
                open(os.path.join(path, name), 'a+').close()
        except OSError as why:
            print('mock: %s' % why, file=sys.stderr)
            os._exit(1)
        os._exit(0)
    if os.waitpid(pid, 0)[1] != 0:
        sys.exit(1)

if '--rebuild' in args or '--buildsrpm' in args:
    config = load_config('/etc/mock', value('-r'))
    call['config_rc'] = 0
if '--rebuild' in args:
    name = pathlib.Path(value('--rebuild')).name.split('-1-1.oe2403')[0]
    call['name'] = name
if '--buildsrpm' in args:
    call['spec'] = pathlib.Path(value('--spec')).read_text()
with open(os.environ['NATIVE_CALLS'], 'a') as f: f.write(json.dumps(call) + '\n')
if '--buildsrpm' in args:
    dest = pathlib.Path(value('--resultdir')); resultdir(dest)
    source = json.loads(pathlib.Path(os.environ['NATIVE_OUTPUTS']).read_text())['native-leaf'][1]
    shutil.copyfile(source, dest / pathlib.Path(source).name)
    sys.exit(0)
if '--rebuild' not in args: sys.exit(0)
if name == os.environ.get('NATIVE_FAIL'): sys.exit(42)
dest = pathlib.Path(value('--resultdir')); resultdir(dest)
if name == os.environ.get('NATIVE_EMPTY'): sys.exit(0)
fixtures = json.loads(pathlib.Path(os.environ['NATIVE_OUTPUTS']).read_text())
for source in fixtures[name]: shutil.copyfile(source, dest / pathlib.Path(source).name)
