#!/bin/bash
set -e

export NPROCS="$((`nproc --all 2>/dev/null || sysctl -n hw.ncpu` * 2))"
echo paralleism is $NPROCS

if [[ "$PERFORM_COVERITY_SCAN" == "1" ]]; then
  curl -s "https://scan.coverity.com/scripts/travisci_build_coverity_scan.sh" \
    --output /tmp/travisci_build_coverity_scan.sh
  sed -i -e "s/--form version=\$SHA/--form version=\"${TRAVIS_BRANCH}\"/g" \
    -e "s/--form description=\"Travis CI build\"/--form description=\"${SHA}\"/g" \
    -e "s/201/200/g" /tmp/travisci_build_coverity_scan.sh
  bash /tmp/travisci_build_coverity_scan.sh
  exit 0
fi

if [[ "$TRAVIS_OS_NAME" == "osx" ]]; then
  export CFLAGS="-O2 -g -arch i386 -arch x86_64"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-arch i386 -arch x86_64"
  ./bootstrap
  ./configure --disable-silent-rules --enable-shared --enable-static $CONF
  make -j$NPROCS
  make install DESTDIR="/opt/libxcrypt"
  make check -j$NPROCS || (cat test-suite.log && exit 1)
  exit 0
fi

if [[ "$CODECOV" == "1" ]]; then
  export CFLAGS="-O0 -g --coverage"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="--coverage"
else
  export CFLAGS="`cat cflags.txt`"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="`cat ldflags.txt`"
fi

echo $CFLAGS
echo $LDFLAGS

docker exec -t buildenv /bin/sh \
  -c "cat /etc/redhat-release"
docker exec -t buildenv /bin/sh \
  -c "cd /opt/libxcrypt && ./bootstrap"
docker exec -t buildenv /bin/sh \
  -c "cd /opt/libxcrypt && CFLAGS=\"$CFLAGS\" CXXFLAGS=\"$CXXFLAGS\" LDFLAGS=\"$LDFLAGS\" ./configure --prefix=/opt/libxcrypt --disable-silent-rules --enable-shared --enable-static $CONF"
docker exec -t buildenv /bin/sh \
  -c "make -C /opt/libxcrypt -j$NPROCS"
docker exec -t buildenv /bin/sh \
  -c "make -C /opt/libxcrypt install"
docker exec -t buildenv /bin/sh \
  -c "(make -C /opt/libxcrypt -j$NPROCS check || (cat /opt/libxcrypt/test-suite.log && exit 1))"

if [[ "$VALGRIND" == "1" ]]; then
  docker exec -t buildenv /bin/sh \
    -c "(make -C /opt/libxcrypt -j$NPROCS check-valgrind-memcheck || (cat /opt/libxcrypt/test-suite-memcheck.log && exit 1))"
fi

if [[ "$DISTCHECK" == "1" ]]; then
  docker exec -t buildenv /bin/sh \
    -c "make -C /opt/libxcrypt -j$NPROCS distcheck"
fi