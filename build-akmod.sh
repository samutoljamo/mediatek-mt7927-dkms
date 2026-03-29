#!/usr/bin/env bash
# Build an akmod SRPM for akmod-mediatek-mt7927.
#
# The SRPM bundles pre-patched mt76/bluetooth sources so users can rebuild
# it for any kernel without needing the original kernel tarball or driver ZIP.
#
# Usage: ./build-akmod.sh
#
# Prerequisites: rpmbuild, kmodtool (from akmods), make, python3, curl

set -euo pipefail

SPEC="akmod-mediatek-mt7927.spec"
VERSION=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)
TOPDIR="${PWD}/rpmbuild"
SRCDIR="${PWD}/_build"
TARNAME="mediatek-mt7927-src-${VERSION}"

if ! command -v rpmbuild &>/dev/null; then
    echo >&2 "rpmbuild not found. Install rpm-build:"
    echo >&2 "  Fedora: sudo dnf install rpm-build"
    exit 1
fi

if ! command -v kmodtool &>/dev/null; then
    echo >&2 "kmodtool not found. Install akmods:"
    echo >&2 "  Fedora: sudo dnf install akmods"
    exit 1
fi

echo "==> Building akmod-mediatek-mt7927 ${VERSION} SRPM"

# Prepare pre-patched sources (downloads kernel tarball + driver ZIP if needed)
make download
make sources SRCDIR="${SRCDIR}"

echo "==> Creating source tarball ${TARNAME}.tar.gz..."
mkdir -p "${TOPDIR}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Bundle mt76/, bluetooth/, and firmware/ under a versioned top-level directory
TMPSTAGE=$(mktemp -d)
trap 'rm -rf "${TMPSTAGE}"' EXIT
mkdir "${TMPSTAGE}/${TARNAME}"
cp -r "${SRCDIR}/mt76" "${SRCDIR}/bluetooth" "${SRCDIR}/firmware" \
    "${TMPSTAGE}/${TARNAME}/"
tar -czf "${TOPDIR}/SOURCES/${TARNAME}.tar.gz" \
    -C "${TMPSTAGE}" "${TARNAME}"

cp "${SPEC}" "${TOPDIR}/SPECS/"

echo "==> Building SRPM..."
rpmbuild --define "_topdir ${TOPDIR}" \
         --define "_pkg_version ${VERSION}" \
         --nodeps \
         -bs "${TOPDIR}/SPECS/${SPEC}"

echo "==> SRPM:"
find "${TOPDIR}/SRPMS" -name '*.src.rpm' -print
echo ""
echo "To build for the current kernel:"
echo "  sudo rpmbuild --rebuild \$(find ${TOPDIR}/SRPMS -name '*.src.rpm') \\"
echo "    --define 'kernels \$(uname -r)'"
echo ""
echo "Or let akmods handle it after installing the SRPM:"
echo "  sudo akmods --kernels \$(uname -r)"
