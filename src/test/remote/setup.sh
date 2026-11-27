#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Machine side of a long run (README.md here): installs what the runs need, at the versions of
# .github/workflows/formal-verification.yml (read from the payload's copy, so the pins never drift
# from CI) and checked against its SHA-256 where CI checks one. Debian/Ubuntu, as root.
#   tlc       tla2tools.jar (TLA_TOOLS_VERSION, TLA_TOOLS_SHA256)
#   apalache  Apalache (APALACHE_VERSION, APALACHE_SHA256) and a JDK 21 for it
#   jpf       jpf-core at JPF_SHA with the AtomicLong model patch of src/test/jpf, built with JDK 11
#   tlapm     tlapm built from TLAPM_SHA with OCaml OCAML_VERSION (about 10-20 min; Isabelle is a
#             1 GB download from one server, fetched with retries)
#   swap      a swap file of twice the memory (at most half the free disk), swappiness 10: a
#             guard against a memory peak (graphmin.py of a large graph) killing a run that has
#             computed for a day
# Writes <payload>/tools/env.sh, which run-a18.sh and run-formal.sh source. Logs in
# <payload>/out/setup.log; a failed step stops the script.
#
# Usage: <payload>/sb/src/test/remote/setup.sh [tlc] [apalache] [jpf] [tlapm] [swap]
#        (default: tlc jpf swap)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
payload="$(cd "$here/../../../.." && pwd)"
wf="$payload/sb/.github/workflows/formal-verification.yml"
tools="$payload/tools"
mkdir -p "$tools" "$payload/out"
exec > >(tee -a "$payload/out/setup.log") 2>&1
[ "$#" -gt 0 ] || set -- tlc jpf swap
want() { case " $* " in *" $1 "*) return 0 ;; esac; return 1; }
pin() { # the first value of a key in the workflow's env blocks
  local v
  v="$(sed -n "s/^ *$1: \"\(.*\)\".*/\1/p" "$wf" | head -1)"
  [ -n "$v" ] || { echo "no pin $1 in $wf"; exit 1; }
  echo "$v"
}
fetch() { # url, file, sha256 (or "" when CI pins none)
  curl -sS --fail --location --retry 5 --retry-all-errors --retry-delay 20 -o "$2" "$1"
  [ -z "$3" ] || echo "$3  $2" | sha256sum --check --strict
}
args=" $* "
echo "== $(date -u +%H:%M:%S) setup:$args (commit $(cut -c1-12 "$payload/COMMIT" 2>/dev/null || echo unknown))"

export DEBIAN_FRONTEND=noninteractive
pkgs="openjdk-11-jdk-headless python3 git curl"
case "$args" in *" apalache "*) pkgs="$pkgs openjdk-21-jdk-headless" ;; esac
case "$args" in *" tlapm "*) pkgs="$pkgs opam zlib1g-dev gawk time wget make gcc g++ unzip bubblewrap patch" ;; esac
apt-get update -q
# shellcheck disable=SC2086
apt-get install -y -q $pkgs
j11="$(ls -d /usr/lib/jvm/java-11-openjdk-*/bin/java | head -1)"
# a later call (setup.sh tlapm after setup.sh tlc ...) keeps the tools of the earlier ones
prev="$(grep -E '^export (TLA2TOOLS|APALACHE|JPF_CORE|TLAPM)=' "$tools/env.sh" 2>/dev/null || true)"
{
  echo "# written by setup.sh"
  echo "export PAYLOAD=$payload"
  echo "export JAVA_JPF=$j11 JAVA_TLC=$j11"
  echo "export TRACED=$payload/traced TRACED_MUTANT=$payload/traced-mutant TRACED_NOSIGNAL=$payload/traced-nosignal LIB=$payload/lib"
  [ -z "$prev" ] || echo "$prev"
} > "$tools/env.sh"

case "$args" in *" tlc "*)
  fetch "https://github.com/tlaplus/tlaplus/releases/download/$(pin TLA_TOOLS_VERSION)/tla2tools.jar" \
    "$tools/tla2tools.jar" "$(pin TLA_TOOLS_SHA256)"
  echo "export TLA2TOOLS=$tools/tla2tools.jar" >> "$tools/env.sh"
  echo "== tla2tools $(pin TLA_TOOLS_VERSION) ok" ;;
esac

case "$args" in *" apalache "*)
  v="$(pin APALACHE_VERSION)"
  fetch "https://github.com/apalache-mc/apalache/releases/download/v$v/apalache-$v.tgz" \
    "$tools/apalache.tgz" "$(pin APALACHE_SHA256)"
  mkdir -p "$tools/apalache"
  tar xzf "$tools/apalache.tgz" -C "$tools/apalache" --strip-components=1
  j21="$(ls -d /usr/lib/jvm/java-21-openjdk-*/bin | head -1)"
  echo "export APALACHE=$tools/apalache/bin/apalache-mc JAVA21_BIN=$j21" >> "$tools/env.sh"
  echo "== apalache $v ok" ;;
esac

case "$args" in *" jpf "*)
  sha="$(pin JPF_SHA)"
  rm -rf "$tools/jpf-core"
  git clone -q https://github.com/javapathfinder/jpf-core.git "$tools/jpf-core"
  git -C "$tools/jpf-core" checkout -q "$sha"
  cp "$payload/sb/src/test/jpf/jpf-model/java/util/concurrent/atomic/AtomicLong.java" \
    "$tools/jpf-core/src/classes/modules/java.base/java/util/concurrent/atomic/AtomicLong.java"
  (cd "$tools/jpf-core" && JAVA_HOME="$(dirname "$(dirname "$j11")")" ./gradlew -q --no-daemon buildJars -x test)
  echo "export JPF_CORE=$tools/jpf-core" >> "$tools/env.sh"
  echo "== jpf-core $sha ok" ;;
esac

case "$args" in *" tlapm "*)
  sha="$(pin TLAPM_SHA)"
  opam init -y --disable-sandboxing --bare
  opam switch create -y tlapm "ocaml-base-compiler.$(pin OCAML_VERSION)" || opam switch tlapm
  eval "$(opam env --switch=tlapm)"
  src="$tools/tlapm-src"
  rm -rf "$src"
  git init -q "$src"
  git -C "$src" fetch -q --depth 1 https://github.com/tlaplus/tlapm.git "$sha"
  git -C "$src" checkout -q --detach FETCH_HEAD
  mkdir -p "$src/_build_cache"
  isa="$(pin ISABELLE_ARCHIVE)"
  # tlapm's build checks the archive's SHA-256 against its own pin (deps/isabelle/dune.mk)
  fetch "https://isabelle.in.tum.de/website-${isa%_linux.tar.gz}/dist/$isa" "$src/_build_cache/$isa" ""
  make -C "$src" opam-deps
  make -C "$src" opam-deps-opt
  make -C "$src" release
  rm -rf "$tools/tlapm"
  mkdir -p "$tools/tlapm"
  tar xzf "$src"/_build/tlapm-*-x86_64-linux-gnu.tar.gz -C "$tools/tlapm"
  echo "export TLAPM=$tools/tlapm/tlapm/bin/tlapm" >> "$tools/env.sh"
  echo "== tlapm $sha ok: $("$tools/tlapm/tlapm/bin/tlapm" --version 2>&1 | head -1)" ;;
esac
case "$args" in *" swap "*)
  if [ -e /swap-run ]; then
    echo "== swap /swap-run exists"
  else
    mem_gb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))
    free_gb=$(( $(df --output=avail -k / | tail -n 1) / 1024 / 1024 ))
    gb=$(( 2 * mem_gb ))
    [ "$gb" -le $(( free_gb / 2 )) ] || gb=$(( free_gb / 2 ))
    fallocate -l "${gb}G" /swap-run
    chmod 600 /swap-run
    mkswap -q /swap-run
    swapon /swap-run
    sysctl -q vm.swappiness=10
    echo "== swap ${gb} GB on /swap-run (swappiness 10)"
  fi ;;
esac
echo "== $(date -u +%H:%M:%S) setup done; env in $tools/env.sh"
