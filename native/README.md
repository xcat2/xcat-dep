# Native packaging tests

The openEuler packaging tests build and sign RPMs or require Linux namespaces.
They run separately from `prove -r t` on a disposable host with the required
native tools:

```
prove -v native/*.t
```

Use an ordinary user for RPM builds. `openeuler-power-inputs.t` exercises the
whole build owner only on POWER with native Mock; its RPM admission checks also
run on x86_64. When running that test as root, set `XCAT_TEST_BUILD_USER` to an
unprivileged account for the fixture builds.

The fixtures are command doubles at the downloader and Mock boundaries. The
POWER Mock adapter uses the installed Python API directly to load generated
configurations. It does not execute another Python interpreter.

The Mock configuration test loads the installed Python API from a checked-in
fixture and is kept outside the unit run.

Inspect TAP skips: a successful exit does not qualify an unavailable native
tool or architecture.
