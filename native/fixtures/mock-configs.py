import configparser
import json
from pathlib import Path
import shutil
import sys
import tempfile
from mockbuild.config import load_config

source = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory() as directory:
    config_path = Path(directory)
    templates = config_path / 'templates'
    templates.mkdir()
    for installed in Path('/etc/mock/templates').glob('*.tpl'):
        shutil.copyfile(installed, templates / installed.name)
    shutil.copyfile(source / 'templates/openeuler-lts-xcat.tpl', templates / 'openeuler-lts-xcat.tpl')
    result = {}
    for wrapper in sorted(source.glob('openeuler-*.cfg')):
        try:
            config = load_config(str(config_path), str(wrapper))
        except Exception as why:
            result[wrapper.stem] = {'error': str(why)}
            continue
        repos = configparser.ConfigParser(interpolation=None)
        repos.read_string(config['dnf.conf'])
        result[wrapper.stem] = {key: config[key] for key in ('root', 'target_arch', 'legal_host_arches', 'releasever', 'dist', 'use_bootstrap_image')}
        result[wrapper.stem]['repos'] = {section: dict(repos[section]) for section in repos.sections()}
    print(json.dumps(result))
