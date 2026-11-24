%global debug_package %{nil}
%global _find_debuginfo_opts --no-ar-files
Summary:	cabal-install 3.12.1.0, the Haskell package installer
Name:		cabal-install
Version:	3.12.1.0
Release:	1
License:	BSD-3-Clause
Group:		Development/Other
Url:		https://hackage.haskell.org/package/cabal-install
# New package. Does not replace a distribution package, so no Epoch.
# Bootstrapped from upstream sources with packaged ghc98. No Hackage access.
ExclusiveArch:	x86_64 znver1
Source0:	cabal-install-v3.12.1.0-src.tar.gz
Source1:	cabal-install-3.12.1.0-bootstrap.tar.gz
Source2:	cabal-install-build.sh
Source3:	cabal-install-bootstrap.sh
Source4:	%{name}.rpmlintrc

BuildRequires:	ghc98
# ghc98 links with -lgmp and -lnuma. The .so symlinks come from the
# devel packages; the ghc98 runtime requires do not pull them in.
BuildRequires:	pkgconfig(gmp)
BuildRequires:	pkgconfig(numa)
BuildRequires:	pkgconfig(zlib)
BuildRequires:	gcc
BuildRequires:	python
BuildRequires:	perl
BuildRequires:	lld
BuildRequires:	file
BuildRequires:	tar
BuildRequires:	gzip
BuildRequires:	findutils
BuildRequires:	coreutils
BuildRequires:	diffutils
BuildRequires:	gawk
BuildRequires:	grep
BuildRequires:	sed
BuildRequires:	util-linux

%description
cabal-install 3.12.1.0 bootstrapped from the upstream 3.12.1.0 sources
with packaged ghc98 (GHC 9.8.4). Dependency sources are vendored.
The linux-9.8.2 bootstrap plan's builtin versions are rewritten to this
compiler's ghc-pkg versions. The build does not contact Hackage.
zlib is the system library, found with pkg-config.

%prep
	set -eu
	cd %{_builddir}
	rm -rf cabal-install-root
	mkdir -p cabal-install-root/incoming
	cp -a %{SOURCE0} cabal-install-root/incoming/cabal-install-v3.12.1.0-src.tar.gz
	cp -a %{SOURCE1} cabal-install-root/incoming/cabal-install-3.12.1.0-bootstrap.tar.gz
	cp -a %{SOURCE2} cabal-install-root/incoming/cabal-install-build.sh
	cp -a %{SOURCE3} cabal-install-root/incoming/cabal-install-bootstrap.sh
	chmod 755 cabal-install-root/incoming/cabal-install-build.sh \
		cabal-install-root/incoming/cabal-install-bootstrap.sh
	set +u

%build
	set -eu
	bash %{_builddir}/cabal-install-root/incoming/cabal-install-build.sh \
		"%{_builddir}/cabal-install-root"
	set +u

%install
	set -eu
	mkdir -p %{buildroot}%{_bindir}
	install -m 755 %{_builddir}/cabal-install-root/dest/bin/cabal \
		%{buildroot}%{_bindir}/cabal
	set +u

%files
%{_bindir}/cabal

%check
	set -eu
	b=%{buildroot}%{_bindir}/cabal
	export CABAL_DIR=%{_builddir}/cabal-install-root/work/cabal-version-check
	export TMPDIR=%{_builddir}/cabal-install-root/work/tmp
	export TEMP=$TMPDIR
	export TMP=$TMPDIR
	mkdir -p "$CABAL_DIR" "$TMPDIR"
	export http_proxy=http://127.0.0.1:9
	export https_proxy=http://127.0.0.1:9
	export HTTP_PROXY=http://127.0.0.1:9
	export HTTPS_PROXY=http://127.0.0.1:9
	export all_proxy=http://127.0.0.1:9
	export ALL_PROXY=http://127.0.0.1:9
	"$b" --numeric-version > numeric-1.out
	"$b" --numeric-version > numeric-2.out
	test "$(tr -d '[:space:]' < numeric-1.out)" = "3.12.1.0"
	test "$(tr -d '[:space:]' < numeric-2.out)" = "3.12.1.0"
	set +u
