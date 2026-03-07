#!/bin/bash
# Apply kernel compatibility fixes for building mt76 6.19 source against older kernels.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <kernel-headers-dir> <mt76-source-dir>" >&2
    exit 1
fi

KHEADERS="$1"
MT76_SRC="$2"

if [[ ! -d "${KHEADERS}" ]]; then
    echo "ERROR: kernel headers directory not found: ${KHEADERS}" >&2
    exit 1
fi

if [[ ! -d "${MT76_SRC}" ]]; then
    echo "ERROR: mt76 source directory not found: ${MT76_SRC}" >&2
    exit 1
fi

# Fix 1: airoha_offload.h (introduced in Linux 6.19, required by mt76 wed.c)
# Add a recursive include flag so both mt76 and mt792{1,5} subdirs
# can find the header extracted from the kernel tarball at build time.
AIROHA_SYS="${KHEADERS}/include/linux/soc/airoha/airoha_offload.h"
if [[ ! -f "${AIROHA_SYS}" ]]; then
    AIROHA_COMPAT="${MT76_SRC}/compat/include/linux/soc/airoha/airoha_offload.h"
    KBUILD="${MT76_SRC}/Kbuild"
    FLAG='subdir-ccflags-y += -I$(src)/compat/include'

    if [[ ! -f "${AIROHA_COMPAT}" ]]; then
        echo "ERROR: compat header not found: ${AIROHA_COMPAT}" >&2
        exit 1
    fi

    if [[ -f "${KBUILD}" ]] && ! grep -qF "${FLAG}" "${KBUILD}"; then
        sed -i "1i ${FLAG}" "${KBUILD}"
        echo "compat: added recursive compat include path to mt76 Kbuild for airoha_offload.h"
    else
        echo "compat: recursive compat include path already in Kbuild, skipped"
    fi
else
    echo "compat: airoha_offload.h already present in kernel headers, skipped"
fi

# Fix 2: pp_page_to_nmdesc() (added in kernel commit 89ade7c, not in older kernels)
# For page pool pages, netmem_desc overlays on struct page with identical layout,
# so page->pp is equivalent to pp_page_to_nmdesc(page)->pp.
if ! grep -q 'pp_page_to_nmdesc' "${KHEADERS}/include/net/netmem.h" 2>/dev/null; then
    if grep -q 'pp_page_to_nmdesc' "${MT76_SRC}/mt76.h" 2>/dev/null; then
        sed -i 's/pp_page_to_nmdesc(page)->pp/page->pp/g' "${MT76_SRC}/mt76.h"
        echo "compat: replaced pp_page_to_nmdesc() with page->pp in mt76.h"
    else
        echo "compat: pp_page_to_nmdesc() not found in mt76.h, skipped"
    fi
else
    echo "compat: pp_page_to_nmdesc() already in kernel headers, skipped"
fi

