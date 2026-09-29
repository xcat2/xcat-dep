# Native openEuler Go build input

The native openEuler RPM build uses Go 1.25.12 inside the exact target mock root.
The committed module graph requires this version. The build retains GOTOOLCHAIN=local and CGO_ENABLED=0.

The checksums in go1.25.12.sha256 come from the [official Go release list](https://go.dev/dl/#go1.25.12).
The builder verifies the archive before including it as Source3, and the generated spec verifies it again before extraction.
The toolchain stays in the RPM build directory and is excluded from the goconserver binary package.
The source RPM contains the exact compiler archive, including its Go sources and license, for subsequent rebuilds.

Build x86_64 and ppc64le packages on matching native architecture builders. The package release retains the native empty dist suffix.
Existing EL compilation and cross-build paths retain their original toolchain selection.
