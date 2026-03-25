#!/usr/bin/env bash
set -euo pipefail

# Verify DKMS and upstream patches produce identical code changes.
#
# Both patch sets are derived from the same git branch but target different
# bases (DKMS: kernel tarball + mt7902, upstream: wireless-next). This script
# verifies they introduce the same code changes by comparing the added/removed
# lines (stripping context and path differences).
#
# Usage:
#   ./verify-patches.sh                    # verify all patches
#   ./verify-patches.sh --upstream-only    # just verify upstream matches git

DKMS_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_TREE="${KERNEL_TREE:-$HOME/repos/personal/linux-stable}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-mt7927-wifi-support-v3}"
DKMS_BRANCH="${DKMS_BRANCH:-mt7927-wifi-dkms}"
BASE_REF="${BASE_REF:-dkms-base}"
MT76_SUBDIR="drivers/net/wireless/mediatek/mt76"

upstream_only=false
for arg in "$@"; do
	case "$arg" in
	--upstream-only) upstream_only=true ;;
	esac
done

errors=0

# ── Step 1: Verify upstream patches match git branch ────────────────
echo "==> Verifying upstream patches match git branch ($UPSTREAM_BRANCH)..."

upstream_patches_dir="$DKMS_DIR/linux-stable/patches"
if [[ ! -d "$upstream_patches_dir" ]]; then
	echo "ERROR: upstream patches directory not found: $upstream_patches_dir"
	exit 1
fi

# Count upstream commits (excluding cover letter commit and merge base)
mapfile -t upstream_commits < <(
	git -C "$KERNEL_TREE" log --reverse --format='%H' \
		"${UPSTREAM_BRANCH}~13..${UPSTREAM_BRANCH}"
)

upstream_patch_count=$(find "$upstream_patches_dir" -name '*.patch' ! -name '0000-*' | wc -l)
if ((upstream_patch_count != ${#upstream_commits[@]})); then
	echo "FAIL: upstream patch count ($upstream_patch_count) != git commit count (${#upstream_commits[@]})"
	errors=$((errors + 1))
fi

# For each upstream commit, extract the mt76 diff and compare with the
# corresponding patch file's diff hunks (added/removed lines only)
for i in "${!upstream_commits[@]}"; do
	n=$((i + 1))
	nn=$(printf '%04d' "$n")
	commit=${upstream_commits[$i]}
	subject=$(git -C "$KERNEL_TREE" log -1 --format='%s' "$commit")

	# Find matching patch file
	patch_file=$(find "$upstream_patches_dir" -name "${nn}-*.patch" | head -1)
	if [[ -z "$patch_file" ]]; then
		echo "  FAIL: [$nn] no patch file for: $subject"
		errors=$((errors + 1))
		continue
	fi

	# Extract code changes from git (only +/- lines, strip leading +/-)
	git_changes=$(git -C "$KERNEL_TREE" diff "${commit}^..$commit" \
		-- "$MT76_SUBDIR/" |
		grep -E '^\+[^+]|^-[^-]' | sed 's/^[+-]//' | sort)

	# Extract code changes from patch file
	patch_changes=$(grep -E '^\+[^+]|^-[^-]' "$patch_file" |
		sed 's/^[+-]//' | sort)

	if [[ "$git_changes" == "$patch_changes" ]]; then
		echo "  [$nn] OK: $subject"
	else
		echo "  [$nn] FAIL: upstream patch differs from git"
		echo "       Patch: $(basename "$patch_file")"
		diff <(echo "$git_changes") <(echo "$patch_changes") | head -20
		errors=$((errors + 1))
	fi
done

if $upstream_only; then
	if ((errors > 0)); then
		echo "FAILED: $errors error(s)"
		exit 1
	fi
	echo "All upstream patches match git. Done."
	exit 0
fi

# ── Step 2: Verify DKMS patches match git branch ────────────────────
echo ""
echo "==> Verifying DKMS patches match git branch ($DKMS_BRANCH)..."

mapfile -t dkms_commits < <(
	git -C "$KERNEL_TREE" log --reverse --format='%H' \
		"$DKMS_BRANCH" --not "$BASE_REF"
)

dkms_patch_count=$(find "$DKMS_DIR" -maxdepth 1 -name 'mt7927-wifi-*.patch' | wc -l)
if ((dkms_patch_count != ${#dkms_commits[@]})); then
	echo "FAIL: DKMS patch count ($dkms_patch_count) != git commit count (${#dkms_commits[@]})"
	errors=$((errors + 1))
fi

# For each DKMS commit, compare code changes
for i in "${!dkms_commits[@]}"; do
	n=$((i + 1))
	nn=$(printf '%02d' "$n")
	commit=${dkms_commits[$i]}
	subject=$(git -C "$KERNEL_TREE" log -1 --format='%s' "$commit")

	# Find matching DKMS patch file
	patch_file=$(find "$DKMS_DIR" -maxdepth 1 -name "mt7927-wifi-${nn}-*.patch" | head -1)
	if [[ -z "$patch_file" ]]; then
		echo "  FAIL: [$nn] no DKMS patch for: $subject"
		errors=$((errors + 1))
		continue
	fi

	# Extract code changes from git (mt76 subdir, strip prefix)
	git_changes=$(git -C "$KERNEL_TREE" diff "${commit}^..$commit" \
		-- "$MT76_SUBDIR/" |
		grep -E '^\+[^+]|^-[^-]' | sed 's/^[+-]//' | sort)

	# Extract code changes from DKMS patch
	patch_changes=$(grep -E '^\+[^+]|^-[^-]' "$patch_file" |
		sed 's/^[+-]//' | sort)

	if [[ "$git_changes" == "$patch_changes" ]]; then
		echo "  [$nn] OK: $subject"
	else
		echo "  [$nn] FAIL: DKMS patch differs from git"
		echo "       Patch: $(basename "$patch_file")"
		diff <(echo "$git_changes") <(echo "$patch_changes") | head -20
		errors=$((errors + 1))
	fi
done

# ── Step 3: Cross-check upstream vs DKMS code changes ───────────────
# DKMS patches may contain additional lines from mt7902 merge resolution.
# Verify that all upstream code changes appear in the DKMS patch (subset check).
echo ""
echo "==> Cross-checking upstream vs DKMS patches..."

for i in "${!upstream_commits[@]}"; do
	n=$((i + 1))
	nn_up=$(printf '%04d' "$n")
	nn_dk=$(printf '%02d' "$n")

	up_file=$(find "$upstream_patches_dir" -name "${nn_up}-*.patch" | head -1)
	dk_file=$(find "$DKMS_DIR" -maxdepth 1 -name "mt7927-wifi-${nn_dk}-*.patch" | head -1)

	if [[ -z "$up_file" ]] || [[ -z "$dk_file" ]]; then
		continue
	fi

	up_changes=$(grep -E '^\+[^+]|^-[^-]' "$up_file" |
		sed 's/^[+-]//' | sort)
	dk_changes=$(grep -E '^\+[^+]|^-[^-]' "$dk_file" |
		sed 's/^[+-]//' | sort)

	if [[ "$up_changes" == "$dk_changes" ]]; then
		echo "  [$n] OK"
	else
		# Check if upstream is a subset of DKMS (DKMS may have
		# extra lines from mt7902 conflict resolution)
		missing=$(comm -23 <(echo "$up_changes") <(echo "$dk_changes"))
		extra=$(comm -13 <(echo "$up_changes") <(echo "$dk_changes"))
		if [[ -z "$missing" ]]; then
			extra_count=$(echo "$extra" | grep -c . || true)
			echo "  [$n] OK (DKMS has $extra_count extra lines from merge resolution)"
		else
			echo "  [$n] FAIL: upstream lines missing from DKMS patch"
			echo "$missing" | head -10
			errors=$((errors + 1))
		fi
	fi
done

echo ""
if ((errors > 0)); then
	echo "FAILED: $errors error(s)"
	exit 1
fi
