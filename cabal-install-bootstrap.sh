#!/bin/bash
# Bootstrap cabal-install 3.12.1.0 from the upstream tag sources with
# packaged ghc98 (GHC 9.8.4). Dependencies are the vendored bootstrap-sources
# set. The linux-9.8.2 plan's builtin versions are rewritten to this 9.8.4's
# ghc-pkg versions before bootstrap.py's exact describe check.
# No Hackage access. STAGE is the build root. BOOT is a directory whose
# bin/ contains ghc, ghc-pkg, and hsc2hs.
set -euo pipefail
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS RPM_OPT_FLAGS RPM_LD_FLAGS || true

ROOT=${STAGE:?}
WORK=$ROOT/build/cabal312-work
TREE=$WORK/src/cabal-cabal-install-v3.12.1.0
PREFIX=$ROOT/dest
BOOT=${BOOT:?}
SRC=$ROOT/build/sources/cabal-install-v3.12.1.0-src.tar.gz
PLAN_SRC=$ROOT/build/sources/cabal-install-3.12.1.0/linux-9.8.2.json
DEPS=$ROOT/build/sources/cabal-install-3.12.1.0/bootstrap-sources
EXPECT_SHA=84e883989cf44341dada05f866ec2b0256ac1f3bd111fcf80e7b6a7b77942af3

export TMPDIR=$ROOT/work/tmp
export TEMP=$TMPDIR
export TMP=$TMPDIR
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
mkdir -p "$TMPDIR" "$WORK/logs" "$WORK/bin" "$WORK/src"

exec 9>"$WORK/bootstrap.lock"
flock -n 9 || { printf 'CABAL312_FAILED: another bootstrap holds %s\n' "$WORK/bootstrap.lock"; exit 1; }

phase() { printf 'CABAL312_PHASE %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
failed=0
fail() { failed=1; printf 'CABAL312_FAILED: %s\n' "$*"; exit 1; }
trap 'rc=$?; if [ "$rc" -ne 0 ] && [ "$failed" != 1 ]; then printf "CABAL312_FAILED: exit %s\n" "$rc"; fi' EXIT

printf '%s\n' "$$" > "$WORK/bootstrap.pid"
ulimit -s unlimited 2>/dev/null || true
phase "start pid $$"

[ -x "$BOOT/bin/ghc" ] || fail "boot compiler missing"
[ -x "$BOOT/bin/ghc-pkg" ] || fail "ghc-pkg missing"
[ -x "$BOOT/bin/hsc2hs" ] || fail "hsc2hs missing beside ghc"
ver=$("$BOOT/bin/ghc" --numeric-version | tr -d '[:space:]')
[ "$ver" = "9.8.4" ] || fail "boot numeric-version is '$ver'"
phase "boot compiler 9.8.4"
got_sha=$(sha256sum "$SRC" | awk '{print $1}')
[ "$got_sha" = "$EXPECT_SHA" ] || fail "tarball sha256 $got_sha"
[ -f "$PLAN_SRC" ] || fail "bootstrap plan missing"
[ -f /usr/include/zlib.h ] || fail "zlib.h missing"
command -v python >/dev/null || fail "python missing"

cat > "$WORK/bin/gcc" <<'EOF'
#!/bin/bash
link=1
for a in "$@"; do
	case "$a" in
	-c|-E|-S|-M|-MM|-shared|--version|-dumpversion) link=0 ;;
	esac
done
args=(-fno-pie "$@")
if [ "$link" = 1 ]; then
	args+=(-no-pie)
fi
exec /usr/bin/gcc "${args[@]}"
EOF
chmod +x "$WORK/bin/gcc"

clean=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -e '\.ghcup' -e '\.cabal' -e '/ghc66-work/' -e '/ghc610-work/' -e '/ghc612-work/' -e '/ghc74-work/' -e '/ghc74-tools/' -e '/ghc78-work/' -e '/ghc80-work/' -e '/ghc84-work/' -e '/ghc88-work/' -e '/ghc90-work/' -e '/ghc94-work/' -e '/ghc98-work/' -e '/ghc912-work/' -e '/ghc914-work/' -e '/happy11912-work/' -e '/happy120-work/' -e '/cabal312-work/' | paste -sd: -)
export PATH="$BOOT/bin:$WORK/bin:$clean"
export CC="$WORK/bin/gcc"
unset LD_LIBRARY_PATH || true
unset GHC_PACKAGE_PATH || true
hash -r
command -v ghc | grep -F -q "$BOOT/bin/ghc" || fail "PATH ghc is $(command -v ghc)"
command -v gcc | grep -q '/cabal312-work/bin/gcc' || fail "PATH gcc is $(command -v gcc)"
phase "tools on PATH"

if [ ! -d "$TREE/cabal-install" ]; then
	phase "unpack"
	tar -C "$WORK/src" -xzf "$SRC"
fi
[ -f "$TREE/bootstrap/bootstrap.py" ] || fail "unpack did not produce bootstrap.py"
[ -f "$TREE/Cabal/Cabal.cabal" ] || fail "Cabal library missing"
[ -f "$TREE/Cabal-syntax/Cabal-syntax.cabal" ] || fail "Cabal-syntax missing"
[ -f "$TREE/cabal-install/cabal-install.cabal" ] || fail "cabal-install missing"
[ -f "$TREE/cabal-install-solver/cabal-install-solver.cabal" ] || fail "cabal-install-solver missing"

if [ ! -x "$PREFIX/bin/cabal" ]; then
	phase "stage bootstrap sources"
	rm -rf "$WORK/bs" "$TREE/_build"
	mkdir -p "$WORK/bs"
	python - "$PLAN_SRC" "$DEPS" "$WORK/bs" "$BOOT/bin/ghc-pkg" <<'PY'
import hashlib, json, shutil, subprocess, sys
from pathlib import Path
plan_path, deps, bs, ghc_pkg = map(Path, sys.argv[1:])
plan = json.loads(plan_path.read_text())
for b in plan["builtin"]:
    p = subprocess.run([str(ghc_pkg), "field", b["package"], "version", "--simple-output"],
                       capture_output=True, text=True)
    if p.returncode != 0 or not p.stdout.split():
        sys.stderr.write(f"ghc-pkg field {b['package']} failed: {p.stderr}\n")
        sys.exit(1)
    v = p.stdout.split()[0]
    if v != b["version"]:
        print(f"plan: {b['package']} {b['version']} -> {v}", flush=True)
    b["version"] = v
seen = set()
for d in plan["dependencies"]:
    if d.get("source") != "hackage":
        continue
    tb = deps / f"{d['package']}-{d['version']}.tar.gz"
    cb = deps / f"{d['package']}.cabal"
    if not tb.is_file() or not cb.is_file():
        sys.stderr.write(f"missing vendored {d['package']}-{d['version']}\n")
        sys.exit(1)
    def sha(path):
        h = hashlib.sha256()
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()
    got = sha(tb)
    if got != d["src_sha256"]:
        sys.stderr.write(f"sha256 {tb.name} {got} != {d['src_sha256']}\n")
        sys.exit(1)
    if d.get("cabal_sha256"):
        cgot = sha(cb)
        if cgot != d["cabal_sha256"]:
            sys.stderr.write(f"sha256 {cb.name} {cgot} != {d['cabal_sha256']}\n")
            sys.exit(1)
    key = (tb.name, cb.name)
    if key not in seen:
        shutil.copyfile(tb, bs / tb.name)
        shutil.copyfile(cb, bs / cb.name)
        seen.add(key)
(bs / "plan-bootstrap.json").write_text(json.dumps(plan, indent=1) + "\n")
print(f"bootstrap sources staged {len(seen)} hackage pairs", flush=True)
PY
	tar -C "$WORK/bs" -czf "$WORK/bootstrap-sources.tar.gz" .
	phase "bootstrap cabal-install"
	if ! (cd "$TREE" && python bootstrap/bootstrap.py -w "$BOOT/bin/ghc" -s "$WORK/bootstrap-sources.tar.gz" --no-archive) \
		> "$WORK/logs/bootstrap-py.log" 2>&1
	then
		fail "bootstrap.py: $(tail -25 "$WORK/logs/bootstrap-py.log" | tr '\n' ' ' | cut -c1-800)"
	fi
	[ -x "$TREE/_build/bin/cabal" ] || fail "cabal binary missing"
	mkdir -p "$PREFIX/bin"
	/bin/cp -f "$TREE/_build/bin/cabal" "$PREFIX/bin/cabal"
	chmod +x "$PREFIX/bin/cabal"
fi

iver=$("$PREFIX/bin/cabal" --numeric-version | tr -d '[:space:]')
[ "$iver" = "3.12.1.0" ] || fail "cabal numeric-version '$iver'"
iver2=$("$PREFIX/bin/cabal" --numeric-version | tr -d '[:space:]')
[ "$iver2" = "3.12.1.0" ] || fail "second numeric-version '$iver2'"
printf '%s\n%s\n' "$iver" "$iver2" > "$WORK/logs/cabal-version.log"
phase "installed cabal-install $iver"
printf 'CABAL312_DONE installed %s numeric-version %s\n' "$PREFIX/bin/cabal" "$iver"
