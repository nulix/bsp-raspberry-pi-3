# syntax = devthefuture/dockerfile-x

###
### STAGE 1 - build
###
FROM ./Dockerfile.builder AS build

ARG MACHINE
ARG ARCH
ARG UBOOT_REPO
ARG UBOOT_BRANCH
ARG UBOOT_REV
ARG UBOOT_DEFCONFIG
ARG KERNEL_REPO
ARG KERNEL_BRANCH
ARG KERNEL_REV
ARG KERNEL_DEFCONFIG
ARG KERNEL_IMAGE
ARG RPIFW_REPO="https://github.com/raspberrypi/firmware.git"
ARG RPIFW_BRANCH="master"
ARG RPIFW_SRC_REV="f1ea7092589bc9627c23916132baa7841932b707"

# clone rpi kernel
RUN git clone --depth=1 --branch $KERNEL_BRANCH $KERNEL_REPO && \
    cd linux && \
    git checkout $KERNEL_REV

# build kernel, modules and dtbs
RUN cd linux && \
    make O=build -j$(nproc) $KERNEL_DEFCONFIG && \
    make O=build -j$(nproc) $KERNEL_IMAGE modules dtbs && \
    make O=build INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=modules modules_install

# prepare kernel build artifacts
RUN cd linux && \
    rm -r build/modules/lib/modules/*/build && \
    mkdir -p install/overlays && \
    cp build/arch/${ARCH}/boot/dts/broadcom/*.dtb install && \
    cp build/arch/${ARCH}/boot/dts/overlays/*.dtb* install/overlays && \
    cp arch/${ARCH}/boot/dts/overlays/README install/overlays && \
    cp build/arch/${ARCH}/boot/${KERNEL_IMAGE} install

# clone u-boot
RUN git clone --depth=1 --branch $UBOOT_BRANCH $UBOOT_REPO && \
    cd u-boot && \
    git checkout $UBOOT_REV

# build u-boot
COPY machines/$MACHINE/u-boot/*.config u-boot/defconfig/
COPY machines/$MACHINE/u-boot/boot.cmd.in u-boot/boot.cmd
RUN cd u-boot && \
    make -j$(nproc) $UBOOT_DEFCONFIG && \
    scripts/kconfig/merge_config.sh -m .config defconfig/*.config && \
    make -j$(nproc) olddefconfig
RUN cd u-boot && \
    make -j$(nproc)
RUN cd u-boot && \
    # tools/mkenvimage -s 4096 -o uboot.env include/generated/env.txt && \
    tools/mkimage -A arm64 -T script -C none -n "Boot script" -d boot.cmd boot.scr

# prepare u-boot build artifacts
RUN cd u-boot && mkdir install && \
    cp -v u-boot.bin install && \
    # cp -v uboot.env install && \
    cp -v boot.scr install

# prepare rpi boot files
RUN git clone --depth=1 --branch $RPIFW_BRANCH $RPIFW_REPO && \
    cd firmware && \
    git checkout $RPIFW_SRC_REV
RUN cp firmware/boot/bootcode.bin u-boot/install && \
    cp firmware/boot/fixup*.dat u-boot/install && \
    cp firmware/boot/start*.elf u-boot/install
COPY machines/$MACHINE/u-boot/config.txt u-boot/install
# NOTE: not used with ostree!
COPY machines/$MACHINE/u-boot/cmdline.txt u-boot/install

# create linux kernel build archives
RUN cd linux && \
    K_VER=$(grep "^VERSION =" Makefile | cut -d ' ' -f 3) && \
    K_PATCH=$(grep "^PATCHLEVEL =" Makefile | cut -d ' ' -f 3) && \
    K_SUB=$(grep "^SUBLEVEL =" Makefile | cut -d ' ' -f 3) && \
    KERNEL_VER=${K_VER}.${K_PATCH}.${K_SUB} && \
    tar czf kernel-modules-${KERNEL_VER}.tar.gz -C build/modules/lib/modules . && \
    tar czf kernel-artifacts-${KERNEL_VER}.tar.gz -C install .

# create boot files archive
RUN cd u-boot && \
    U_VER=$(grep "^VERSION =" Makefile | cut -d ' ' -f 3) && \
    U_PATCH=$(grep "^PATCHLEVEL =" Makefile | cut -d ' ' -f 3) && \
    UBOOT_VER=${U_VER}.${U_PATCH} && \
    tar czf boot-artifacts-${UBOOT_VER}.tar.gz -C install .

###
### STAGE 2 - export build artifacts
###
FROM scratch

# copy build artifacts
COPY --from=build linux/kernel-modules-*.tar.gz /
COPY --from=build linux/kernel-artifacts-*.tar.gz /
COPY --from=build u-boot/boot-artifacts-*.tar.gz /
