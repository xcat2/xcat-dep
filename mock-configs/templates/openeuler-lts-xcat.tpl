config_opts['dist'] = ''
config_opts['use_bootstrap_image'] = False
config_opts['description'] = 'openEuler ' + config_opts['openeuler_repository_release']
config_opts['dnf.conf'] = """
[main]
keepcache=1
reposdir=/dev/null
logfile=/var/log/dnf.log
retries=20
timeout=300
obsoletes=1
gpgcheck=1
assumeyes=1
metadata_expire=0
best=1
install_weak_deps=0
skip_if_unavailable=0
protected_packages=
"""
_openeuler_mirrors = ('https://mirrors.tuna.tsinghua.edu.cn/openeuler',
                      'https://mirror.nju.edu.cn/openeuler',
                      'https://repo.openeuler.org')
_openeuler_root = 'https://repo.openeuler.org/openEuler-' + config_opts['openeuler_repository_release']
_openeuler_arch = config_opts['target_arch']
for _openeuler_repo in config_opts['openeuler_repositories']:
    _openeuler_baseurls = ''
    for _openeuler_mirror in _openeuler_mirrors:
        _openeuler_baseurls += '{0}/openEuler-{1}/{2}/{3}/ '.format(
            _openeuler_mirror, config_opts['openeuler_repository_release'],
            _openeuler_repo, _openeuler_arch)
    config_opts['dnf.conf'] += """
[{repo}]
name=openEuler {release} {repo}
baseurl={baseurls}
enabled=1
gpgcheck=1
gpgkey={root}/OS/{arch}/RPM-GPG-KEY-openEuler
skip_if_unavailable=0
""".format(repo=_openeuler_repo, release=config_opts['openeuler_repository_release'],
           root=_openeuler_root, arch=_openeuler_arch,
           baseurls=_openeuler_baseurls.strip())
