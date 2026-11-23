#!/bin/bash
# Lay out a ghc/ghc-pkg/hsc2hs directory for cabal-install's bootstrap.py,
# unpack the vendored plan and bootstrap-sources, and run the bootstrap.
# ROOT is an absolute build directory.
set -euo pipefail

ROOT=${1:?usage: cabal-install-build.sh ROOT}
case "$ROOT" in
/*) ;;
*) printf 'cabal-install: ROOT must be absolute\n'; exit 1 ;;
esac

unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS RPM_OPT_FLAGS RPM_LD_FLAGS || true

export TMPDIR=$ROOT/work/tmp
export TEMP=$TMPDIR
export TMP=$TMPDIR
mkdir -p "$TMPDIR" "$ROOT/work/boot/bin" "$ROOT/build/sources" "$ROOT/incoming"

GHC=${GHC98:-$(command -v ghc98 || true)}
GHC_PKG=${GHC_PKG98:-$(command -v ghc-pkg98 || true)}
[ -n "$GHC" ] && [ -x "$GHC" ] || { printf 'cabal-install: ghc98 is not on PATH\n'; exit 1; }
[ -n "$GHC_PKG" ] && [ -x "$GHC_PKG" ] || { printf 'cabal-install: ghc-pkg98 is not on PATH\n'; exit 1; }
GHC=$(readlink -f "$GHC")
GHC_PKG=$(readlink -f "$GHC_PKG")
ver=$("$GHC" --numeric-version | tr -d '[:space:]')
[ "$ver" = "9.8.4" ] || { printf 'cabal-install: ghc98 numeric-version is %s\n' "$ver"; exit 1; }

# ghc98 --print-libdir is .../lib/ghc-9.8.4/lib. hsc2hs is the sibling bin,
# not $libdir/bin/hsc2hs. The libdir program does not find its template.
libdir=$("$GHC" --print-libdir)
hsc2hs=$(dirname "$libdir")/bin/hsc2hs
[ -x "$hsc2hs" ] || { printf 'cabal-install: hsc2hs missing: %s\n' "$hsc2hs"; exit 1; }
[ -f "$libdir/template-hsc.h" ] || { printf 'cabal-install: hsc2hs template missing: %s\n' "$libdir/template-hsc.h"; exit 1; }

cat > "$ROOT/work/boot/bin/ghc" << EOF
#!/bin/sh
exec $(printf '%q' "$GHC") "\$@"
EOF
cat > "$ROOT/work/boot/bin/ghc-pkg" << EOF
#!/bin/sh
exec $(printf '%q' "$GHC_PKG") "\$@"
EOF
cat > "$ROOT/work/boot/bin/hsc2hs" << EOF
#!/bin/sh
exec $(printf '%q' "$hsc2hs") --template=$(printf '%q' "$libdir/template-hsc.h") --lflag=-fuse-ld=lld "\$@" -I$(printf '%q' "$libdir/include/")
EOF
chmod 755 "$ROOT/work/boot/bin/ghc" "$ROOT/work/boot/bin/ghc-pkg" "$ROOT/work/boot/bin/hsc2hs"

cp -a "$ROOT/incoming/cabal-install-v3.12.1.0-src.tar.gz" \
	"$ROOT/build/sources/cabal-install-v3.12.1.0-src.tar.gz"
rm -rf "$ROOT/build/sources/cabal-install-3.12.1.0"
mkdir -p "$ROOT/build/sources/cabal-install-3.12.1.0"
tar -C "$ROOT/build/sources/cabal-install-3.12.1.0" -xzf \
	"$ROOT/incoming/cabal-install-3.12.1.0-bootstrap.tar.gz"
[ -f "$ROOT/build/sources/cabal-install-3.12.1.0/linux-9.8.2.json" ]
[ -f "$ROOT/build/sources/cabal-install-3.12.1.0/bootstrap-sources/zlib-0.7.1.0.tar.gz" ]
[ -f "$ROOT/build/sources/cabal-install-3.12.1.0/bootstrap-sources/zlib.cabal" ]

export STAGE=$ROOT
export BOOT=$ROOT/work/boot
bash "$ROOT/incoming/cabal-install-bootstrap.sh"
