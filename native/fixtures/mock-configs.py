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
    (config_path / 'templates').mkdir()
    for parent in ('openeuler-20.03-sp4.tpl', 'openeuler-22.03-sp4.tpl', 'openeuler-24.03.tpl'):
        shutil.copyfile(Path('/etc/mock/templates') / parent, config_path / 'templates' / parent)
    shutil.copyfile(source / 'templates/openeuler-lts-xcat.tpl', config_path / 'templates/openeuler-lts-xcat.tpl')
    result = {}
    for wrapper in sorted(source.glob('openeuler-*.cfg')):
        config = load_config(str(config_path), str(wrapper))
        repos = configparser.ConfigParser(interpolation=None)
        repos.read_string(config['dnf.conf'])
        result[wrapper.stem] = {key: config[key] for key in ('root', 'target_arch', 'legal_host_arches', 'releasever', 'dist', 'use_bootstrap_image')}
        result[wrapper.stem]['repos'] = {section: dict(repos[section]) for section in repos.sections()}
    print(json.dumps(result))
