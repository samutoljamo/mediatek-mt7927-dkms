%global akmod_name  mediatek-mt7927
%global kmod_name   %{akmod_name}

Name:           akmod-%{akmod_name}
Version:        %{?_pkg_version}%{!?_pkg_version:0}
Release:        1%{?dist}
Summary:        Akmod for MediaTek MT7927 WiFi 7 and Bluetooth 5.4
License:        GPL-2.0-only
URL:            https://github.com/jetm/mediatek-mt7927-dkms
ExclusiveArch:  x86_64

# Pre-patched source tree produced by 'make sources' before SRPM creation.
# Contains: mt76/ bluetooth/ firmware/
Source0:        %{akmod_name}-src-%{version}.tar.gz

BuildRequires:  %{_bindir}/kmodtool

%{expand:%(kmodtool --target %{_target_cpu} --repo local --kmodname %{kmod_name} %{?kernels} 2>/dev/null)}

%description
Akmod package for MediaTek MT7927 (Filogic 380) combo WiFi 7 + BT 5.4.

Builds btusb/btmtk (Bluetooth) and mt76 (WiFi) kernel modules from
pre-patched upstream sources. Supports kernels 6.17+.

When MT7927 support is merged into mainline kernels and linux-firmware,
remove this package to use the in-tree drivers.

Conflicts:      btusb-mt7925-dkms
Conflicts:      btusb-mt7927-dkms

%package -n mediatek-mt7927-firmware
Summary:        Firmware for MediaTek MT7927 (Filogic 380)
BuildArch:      noarch

%description -n mediatek-mt7927-firmware
Firmware blobs for MediaTek MT7927 combo WiFi 7 + BT 5.4 (Filogic 380).
Required for both WiFi and Bluetooth operation.

%prep
%setup -q -n %{akmod_name}-src-%{version}

%build
for kernel_version in %{?kernels}; do
    # Auto-detect Clang/LLVM toolchain from kernel config (e.g. CachyOS)
    _llvm=
    if grep -qs '^CONFIG_CC_IS_CLANG=y' /usr/src/kernels/${kernel_version}/.config 2>/dev/null; then
        _llvm="LLVM=1"
    fi

    mkdir -p _kmod_build_${kernel_version}
    cp -r bluetooth mt76 _kmod_build_${kernel_version}/

    # Skip Bluetooth build if this kernel already ships native MT6639 support
    if ! grep -q 'MT6639' /usr/src/kernels/${kernel_version}/drivers/bluetooth/btmtk.h 2>/dev/null; then
        make ${_llvm} -C /usr/src/kernels/${kernel_version} \
            M=${PWD}/_kmod_build_${kernel_version}/bluetooth \
            modules
    fi

    # WiFi: mt76 core + mt792x-lib + mt7921 + mt7925
    make ${_llvm} -C /usr/src/kernels/${kernel_version} \
        M=${PWD}/_kmod_build_${kernel_version}/mt76 \
        modules
done

%install
for kernel_version in %{?kernels}; do
    install -dm755 %{buildroot}/lib/modules/${kernel_version}/extra/

    find _kmod_build_${kernel_version} -name '*.ko' \
        -exec install -m644 '{}' %{buildroot}/lib/modules/${kernel_version}/extra/ ';'
done

install -Dm644 firmware/BT_RAM_CODE_MT6639_2_1_hdr.bin \
    %{buildroot}/usr/lib/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin
install -Dm644 firmware/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin \
    %{buildroot}/usr/lib/firmware/mediatek/mt7927/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin
install -Dm644 firmware/WIFI_RAM_CODE_MT6639_2_1.bin \
    %{buildroot}/usr/lib/firmware/mediatek/mt7927/WIFI_RAM_CODE_MT6639_2_1.bin

%{expand:%(kmodtool --target %{_target_cpu} --repo local --kmodname %{kmod_name} --rpmtemplate %{?kernels} 2>/dev/null)}

%files -n mediatek-mt7927-firmware
%dir /usr/lib/firmware/mediatek/mt7927
/usr/lib/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin
/usr/lib/firmware/mediatek/mt7927/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin
/usr/lib/firmware/mediatek/mt7927/WIFI_RAM_CODE_MT6639_2_1.bin

%changelog
