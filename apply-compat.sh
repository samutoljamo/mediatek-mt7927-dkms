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

# Fix 3: radio_idx parameter in mac80211 ops (added in commit b74947b4f6ff)
# Older kernels don't have the int radio_idx parameter in ieee80211_ops
# callbacks (config, set_rts_threshold, set/get_antenna, set_coverage_class).
# mt76 never uses the parameter, so stripping it is safe.
if ! grep -q 'int radio_idx' "${KHEADERS}/include/net/mac80211.h" 2>/dev/null; then
    _radio_files=(
        "${MT76_SRC}/mt76.h"
        "${MT76_SRC}/mac80211.c"
        "${MT76_SRC}/mt792x.h"
        "${MT76_SRC}/mt792x_core.c"
        "${MT76_SRC}/mt7921/main.c"
        "${MT76_SRC}/mt7925/main.c"
    )
    _fixed=0
    for f in "${_radio_files[@]}"; do
        if [[ -f "$f" ]] && grep -q 'int radio_idx' "$f" 2>/dev/null; then
            sed -i 's/, int radio_idx//' "$f"
            _fixed=$((_fixed + 1))
        fi
    done
    if (( _fixed > 0 )); then
        echo "compat: stripped radio_idx parameter from ${_fixed} file(s)"
    else
        echo "compat: radio_idx not found in mt76 sources, skipped"
    fi
else
    echo "compat: radio_idx already in mac80211 headers, skipped"
fi

# Fix 4: system_percpu_wq (added in commit ee518f914cd9)
# Older kernels use system_wq; system_percpu_wq was introduced later.
if ! grep -q 'system_percpu_wq' "${KHEADERS}/include/linux/workqueue.h" 2>/dev/null; then
    _fixed=0
    for f in "${MT76_SRC}/mt7921/init.c" "${MT76_SRC}/mt7925/init.c"; do
        if [[ -f "$f" ]] && grep -q 'system_percpu_wq' "$f" 2>/dev/null; then
            sed -i 's/system_percpu_wq/system_wq/g' "$f"
            _fixed=$((_fixed + 1))
        fi
    done
    if (( _fixed > 0 )); then
        echo "compat: replaced system_percpu_wq with system_wq in ${_fixed} file(s)"
    else
        echo "compat: system_percpu_wq not found in mt76 sources, skipped"
    fi
else
    echo "compat: system_percpu_wq already in kernel headers, skipped"
fi

