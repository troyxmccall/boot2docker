

FROM debian:bullseye-slim

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-xc"]

RUN apt-get update; \
  apt-get install -y --no-install-recommends \
    bash-completion \
    bc \
    bison \
    ca-certificates \
    cpio \
    flex \
    gcc \
    git \
    gnupg dirmngr \
    golang-go \
    kmod \
    libc6-dev \
    libelf-dev \
    libssl-dev \
    liblzma-dev \
    liblzo2-dev \
    liblz4-dev \
    libzstd-dev \
    make \
    p7zip-full \
    patch \
    rsync \
    squashfs-tools \
    wget \
    xorriso \
    xz-utils \
  ; \
  rm -rf /var/lib/apt/lists/*

# cleaner wget output
RUN echo 'progress = dot:giga' >> ~/.wgetrc; \
# color prompt (better debugging/devel)
  cp /etc/skel/.bashrc ~/

WORKDIR /rootfs

# updated via "update.sh"
ENV TCL_MIRRORS https://distro.ibiblio.org/tinycorelinux
ENV TCL_MAJOR 14.x
ENV TCL_VERSION 14.0

# updated via "update.sh"
ENV TCL_ROOTFS="rootfs64.gz" TCL_ROOTFS_MD5="9b83cc61e606c631fa58dd401ee3f631"

COPY files/tce-load.patch files/udhcpc.patch /tcl-patches/

RUN for mirror in $TCL_MIRRORS; do \
    if \
      { \
        wget -O /rootfs.gz "$mirror/$TCL_MAJOR/x86_64/archive/$TCL_VERSION/distribution_files/$TCL_ROOTFS" \
          || wget -O /rootfs.gz "$mirror/$TCL_MAJOR/x86_64/release/distribution_files/$TCL_ROOTFS" \
      ; } && echo "$TCL_ROOTFS_MD5 */rootfs.gz" | md5sum -c - \
    ; then \
      break; \
    fi; \
  done; \
  echo "$TCL_ROOTFS_MD5 */rootfs.gz" | md5sum -c -; \
  zcat /rootfs.gz | cpio \
    --extract \
    --make-directories \
    --no-absolute-filenames \
  ; \
  rm /rootfs.gz; \
  \
  for patch in /tcl-patches/*.patch; do \
    patch \
      --input "$patch" \
      --strip 1 \
      --verbose \
    ; \
  done; \
  \
  { \
    echo '# https://1.1.1.1/'; \
    echo 'nameserver 1.1.1.1'; \
    echo 'nameserver 1.0.0.1'; \
  } > etc/resolv.conf; \
  cp etc/resolv.conf etc/resolv.conf.b2d; \
  { \
    echo '#!/usr/bin/env bash'; \
    echo 'set -Eeuo pipefail'; \
    echo "cd '$PWD'"; \
    echo 'cp -T etc/resolv.conf etc/resolv.conf.bak'; \
    echo 'cp -T /etc/resolv.conf etc/resolv.conf'; \
    echo 'cp -T /proc/cpuinfo proc/cpuinfo 2>/dev/null || :'; \
    echo 'trap "mv -T etc/resolv.conf.bak etc/resolv.conf || :; rm proc/cpuinfo 2>/dev/null || :" EXIT'; \
    echo 'env -i PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" TERM="$TERM" chroot '"'$PWD'"' "$@"'; \
  } > /usr/local/bin/tcl-chroot; \
  chmod +x /usr/local/bin/tcl-chroot

# add new "docker" user (and replace "tc" user usage with "docker")
RUN tcl-chroot adduser \
    -h /home/docker \
    -g 'Docker' \
    -s /bin/sh \
    -G staff \
    -D \
    -u 1000 \
    docker \
  ; \
  echo 'docker:tcuser' | tcl-chroot chpasswd; \
  echo 'docker ALL = NOPASSWD: ALL' >> etc/sudoers; \
  sed -i 's/USER="tc"/USER="docker"/g' etc/init.d/tc-* etc/init.d/services/*

# https://github.com/tatsushid/docker-tinycore/blob/017b258a08a41399f65250c9865a163226c8e0bf/8.2/x86_64/Dockerfile
RUN mkdir -p proc; \
  touch proc/cmdline; \
  mkdir -p tmp/tce/optional usr/local/tce.installed/optional; \
  chown -R root:staff tmp/tce usr/local/tce.installed; \
  chmod -R g+w tmp/tce; \
  ln -sT ../../tmp/tce etc/sysconfig/tcedir; \
  echo -n docker > etc/sysconfig/tcuser; \
  tcl-chroot sh -c '. /etc/init.d/tc-functions && setupHome'

# as of squashfs-tools 4.4, TCL's unsquashfs is broken... (fails to unsquashfs *many* core tcz files)
# https://github.com/plougher/squashfs-tools/releases
# updated via "update.sh"
ENV SQUASHFS_VERSION 4.6.1
RUN wget -O squashfs.tgz "https://github.com/plougher/squashfs-tools/archive/$SQUASHFS_VERSION.tar.gz"; \
  tar --directory=/usr/src --extract --file=squashfs.tgz; \
  make -C "/usr/src/squashfs-tools-$SQUASHFS_VERSION/squashfs-tools" \
    -j "$(nproc)" \
# https://github.com/plougher/squashfs-tools/blob/4.6.1/squashfs-tools/Makefile#L1
    GZIP_SUPPORT=1 \
    XZ_SUPPORT=1 \
    LZO_SUPPORT=1 \
    LZ4_SUPPORT=1 \
    ZSTD_SUPPORT=1 \
    EXTRA_CFLAGS='-static' \
    EXTRA_LDFLAGS='-static' \
    INSTALL_DIR="$PWD/usr/local/bin" \
    install \
  ; \
  tcl-chroot unsquashfs -v || :

RUN { \
    echo '#!/bin/bash -Eeux'; \
    echo 'tcl-chroot su -c "tce-load -wicl \"\$@\"" docker -- - "$@"'; \
  } > /usr/local/bin/tcl-tce-load; \
  chmod +x /usr/local/bin/tcl-tce-load

RUN tcl-tce-load bash; \
  tcl-chroot bash --version; \
# delete all the TCL user-specific profile/rc files -- they have odd settings like auto-login from interactive root directly to "tcuser"
# (and the bash-provided defaults are reasonably sane)
  rm -vf \
    home/docker/.ashrc \
    home/docker/.bashrc \
    home/docker/.profile \
    root/.ashrc \
    root/.bashrc \
    root/.profile \
  ; \
  echo 'source /etc/profile' > home/docker/.profile; \
  echo 'source /etc/profile' > root/.profile; \
# swap "docker" (and "root") user shell from /bin/sh to /bin/bash now that it exists
  sed -ri '/^(docker|root):/ s!:[^:]*$!:/bin/bash!' etc/passwd; \
  grep -E '^root:' etc/passwd | grep bash; \
  grep -E '^docker:' etc/passwd | grep bash; \
# /etc/profile has a minor root bug where it uses "\#" in PS1 instead of "\$" (so we get a counter in our prompt instead of a "#")
# but also, does not use \[ and \] for escape sequences, so Bash readline gets confused, so let's replace it outright with something perty
  grep '\\#' etc/profile; \
  echo 'PS1='"'"'\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '"'"'' > etc/profile.d/boot2docker-ps1.sh; \
  source etc/profile.d/boot2docker-ps1.sh; \
  [ "$PS1" = '\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ ' ]

# https://www.kernel.org/category/signatures.html#important-fingerprints
ENV LINUX_GPG_KEYS \
# Linus Torvalds
    ABAF11C65A2970B130ABE3C479BE3E4300411886 \
# Greg Kroah-Hartman
    647F28654894E3BD457199BE38DBBDC86092693E \
# Sasha Levin
    E27E5D8A3403A2EF66873BBCDEA66FF797772CDC \
# Ben Hutchings
    AC2B29BD34A6AFDDB3F68F35E7BFC8EC95861109

# updated via "update.sh"
ENV LINUX_VERSION 6.1.141

RUN wget -O /linux.tar.xz "https://cdn.kernel.org/pub/linux/kernel/v${LINUX_VERSION%%.*}.x/linux-${LINUX_VERSION}.tar.xz"; \
  wget -O /linux.tar.asc "https://cdn.kernel.org/pub/linux/kernel/v${LINUX_VERSION%%.*}.x/linux-${LINUX_VERSION}.tar.sign"; \
  \
# decompress (signature is for the decompressed file)
  xz --decompress /linux.tar.xz; \
  [ -f /linux.tar ] && [ ! -f /linux.tar.xz ]; \
  \
# verify
  export GNUPGHOME="$(mktemp -d)"; \
  for key in $LINUX_GPG_KEYS; do \
    for mirror in \
      gpg-hkps://keyring.debian.org \
      gpg-hkps://keyserver.ubuntu.com \
      gpg-hkps://pgp.surf.nl \
      wget-https://keyserver.ubuntu.com/pks/lookup\?search=0x$key\&fingerprint=on\&op=get \
      wget-https://pgp.surf.nl/pks/lookup\?search=0x$key\&fingerprint=on\&op=get \
      gpg-hkp://pgp.rediris.es \
      gpg-hkp://keyserver.ubuntu.com \
      gpg-hkp://keyserver.ubuntu.com:80 \
      wget-http://keyserver.ubuntu.com/pks/lookup\?search=0x$key\&fingerprint=on\&op=get \
      wget-http://pgp.surf.nl/pks/lookup\?search=0x$key\&fingerprint=on\&op=get \
      gpg-ldap://keyserver-legacy.pgp.com \
    ; do \
      if url=$(echo "$mirror" | grep "^gpg-"| sed -e 's|^gpg-||g') && \
        gpg --batch --verbose --keyserver "$url" --keyserver-options timeout=5 --recv-keys "$key"; \
      then \
        break; \
      elif url=$(echo "$mirror" | grep "^wget-"| sed -e 's|^wget-||g') && \
        wget -O- "$url" | gpg --import; \
      then \
        break; \
      fi; \
    done; \
    gpg --batch --fingerprint "$key"; \
  done; \
  gpg --batch --verify /linux.tar.asc /linux.tar; \
  gpgconf --kill all; \
  rm -rf "$GNUPGHOME"; \
  \
# extract
  tar --extract --file /linux.tar --directory /usr/src; \
  rm /linux.tar /linux.tar.asc; \
  ln -sT "linux-$LINUX_VERSION" /usr/src/linux; \
  [ -d /usr/src/linux ]

RUN { \
    echo '#!/usr/bin/env bash'; \
    echo 'set -Eeuo pipefail'; \
    echo 'while [ "$#" -gt 0 ]; do'; \
    echo 'conf="${1%%=*}"; shift'; \
    echo 'conf="${conf#CONFIG_}"'; \
# https://www.kernel.org/doc/Documentation/kbuild/kconfig-language.txt
# TODO somehow capture "if" directives (https://github.com/torvalds/linux/blob/52e60b754438f34d23348698534e9ca63cd751d7/drivers/message/fusion/Kconfig#L12) since they're dependency related (can't set "CONFIG_FUSION_SAS" without first setting "CONFIG_FUSION")
    echo 'find /usr/src/linux/ \
      -name Kconfig \
      -exec awk -v conf="$conf" '"'"' \
        $1 ~ /^(menu)?config$/ && $2 == conf { \
          yes = 1; \
          printf "-- %s:%s --\n", FILENAME, FNR; \
          print; \
          next; \
        } \
        $1 ~ /^(end)?((menu)?config|choice|comment|menu|if|source)$/ { yes = 0; next } \
# TODO parse help text properly (indentation-based) to avoid false positives when scraping deps
        yes { print; next } \
      '"'"' "{}" + \
    '; \
    echo 'done'; \
  } > /usr/local/bin/linux-kconfig-info; \
  chmod +x /usr/local/bin/linux-kconfig-info; \
  linux-kconfig-info CGROUPS

COPY files/kernel-config.d /kernel-config.d

RUN setConfs="$(grep -vEh '^[#-]' /kernel-config.d/* | sort -u)"; \
  unsetConfs="$(sed -n 's/^-//p' /kernel-config.d/* | sort -u)"; \
  IFS=$'\n'; \
  setConfs=( $setConfs ); \
  unsetConfs=( $unsetConfs ); \
  unset IFS; \
  \
# https://www.mail-archive.com/linux-kernel@vger.kernel.org/msg2140886.html
  make -C /usr/src/linux \
    defconfig \
    kvm_guest.config \
    xen.config \
    > /dev/null; \
  \
  ( \
    set +x; \
    for conf in "${unsetConfs[@]}"; do \
      sed -i -e "s!^$conf=.*\$!# $conf is not set!" /usr/src/linux/.config; \
    done; \
    for confV in "${setConfs[@]}"; do \
      conf="${confV%%=*}"; \
      sed -ri -e "s!^($conf=.*|# $conf is not set)\$!$confV!" /usr/src/linux/.config; \
      if ! grep -q "^$confV\$" /usr/src/linux/.config; then \
        echo "$confV" >> /usr/src/linux/.config; \
      fi; \
    done; \
  ); \
  make -C /usr/src/linux olddefconfig; \
  set +x; \
  ret=; \
  for conf in "${unsetConfs[@]}"; do \
    if grep "^$conf=" /usr/src/linux/.config; then \
      echo "$conf is set!"; \
      ret=1; \
    fi; \
  done; \
  for confV in "${setConfs[@]}"; do \
    if ! grep -q "^$confV\$" /usr/src/linux/.config; then \
      kconfig="$(linux-kconfig-info "$confV")"; \
      echo >&2; \
      echo >&2 "'$confV' is not set:"; \
      echo >&2; \
      echo >&2 "$kconfig"; \
      echo >&2; \
      for dep in $(awk '$1 == "depends" && $2 == "on" { $1 = ""; $2 = ""; gsub(/[^a-zA-Z0-9_-]+/, " "); print }' <<<"$kconfig"); do \
        grep >&2 -E "^CONFIG_$dep=|^# CONFIG_$dep is not set$" /usr/src/linux/.config || :; \
      done; \
      echo >&2; \
      ret=1; \
    fi; \
  done; \
  [ -z "$ret" ] || exit "$ret"

RUN make -C /usr/src/linux -j "$(nproc)" bzImage modules; \
  make -C /usr/src/linux INSTALL_MOD_PATH="$PWD" modules_install
RUN mkdir -p /tmp/iso/boot; \
  cp -vLT /usr/src/linux/arch/x86_64/boot/bzImage /tmp/iso/boot/vmlinuz

RUN tcl-tce-load \
    acpid \
    bash-completion \
    ca-certificates \
    curl \
    e2fsprogs \
    git \
    iproute2 \
    iptables \
    ncursesw-terminfo \
    nfs-utils \
    openssh \
    openssl-1.1.1 \
    parted \
    procps-ng \
    rsync \
    tar \
    util-linux \
    xz

# bash-completion puts auto-load in /usr/local/etc/profile.d instead of /etc/profile.d
# (this one-liner is the same as the loop at the end of /etc/profile with an adjusted search path)
RUN echo 'for i in /usr/local/etc/profile.d/*.sh ; do if [ -r "$i" ]; then . $i; fi; done' > etc/profile.d/usr-local-etc-profile-d.sh; \
# Docker expects to find certs in /etc/ssl
  ln -svT ../usr/local/etc/ssl etc/ssl; \
# make sure the Docker group exists and we're part of it
  tcl-chroot sh -eux -c 'addgroup -S docker && addgroup docker docker'

# install kernel headers so we can use them for building xen-utils, etc
RUN make -C /usr/src/linux INSTALL_HDR_PATH=/usr/local headers_install

# https://download.virtualbox.org/virtualbox/
# updated via "update.sh"
ENV VBOX_VERSION 7.1.10
# https://www.virtualbox.org/download/hashes/$VBOX_VERSION/SHA256SUMS
ENV VBOX_SHA256 59c92f7f5fd7e081211e989f5117fc53ad8d8800ad74a01b21e97bb66fe62972
# (VBoxGuestAdditions_X.Y.Z.iso SHA256, for verification)

RUN wget -O /vbox.iso "https://download.virtualbox.org/virtualbox/$VBOX_VERSION/VBoxGuestAdditions_$VBOX_VERSION.iso"; \
  echo "$VBOX_SHA256 */vbox.iso" | sha256sum -c -; \
  7z x -o/ /vbox.iso VBoxLinuxAdditions.run; \
  rm /vbox.iso; \
  sh /VBoxLinuxAdditions.run --noexec --target /usr/src/vbox; \
  mkdir /usr/src/vbox/amd64; \
  7z x -so /usr/src/vbox/VBoxGuestAdditions-amd64.tar.bz2 | tar --extract --directory /usr/src/vbox/amd64; \
  rm /usr/src/vbox/VBoxGuestAdditions-*.tar.bz2; \
  ln -sT "vboxguest-$VBOX_VERSION" /usr/src/vbox/amd64/src/vboxguest
RUN make -C /usr/src/vbox/amd64/src/vboxguest -j "$(nproc)" \
    KERN_DIR='/usr/src/linux' \
    KERN_VER="$(< /usr/src/linux/include/config/kernel.release)" \
    vboxguest vboxsf \
  ; \
  cp -v /usr/src/vbox/amd64/src/vboxguest/*.ko lib/modules/*/; \
# create hacky symlink so these binaries can work as-is
  ln -sT lib lib64; \
  cp -v /usr/src/vbox/amd64/other/mount.vboxsf /usr/src/vbox/amd64/sbin/VBoxService sbin/; \
  cp -v /usr/src/vbox/amd64/bin/VBoxControl bin/

# TCL includes VMware's open-vm-tools 10.2.0.1608+ (no reason to compile that ourselves)
RUN tcl-tce-load open-vm-tools; \
  tcl-chroot vmhgfs-fuse --version; \
  tcl-chroot which vmtoolsd; \
  rm etc/profile.d/open-vm-tools.sh

# https://www.parallels.com/products/desktop/download/
# updated via "update.sh"
ENV PARALLELS_VERSION 19.0.0-54570

RUN wget -O /parallels.tgz "https://download.parallels.com/desktop/v${PARALLELS_VERSION%%.*}/$PARALLELS_VERSION/ParallelsTools-$PARALLELS_VERSION-boot2docker.tar.gz"; \
  mkdir /usr/src/parallels; \
  tar --extract --file /parallels.tgz --directory /usr/src/parallels --strip-components 1; \
  rm /parallels.tgz
RUN cp -vr /usr/src/parallels/tools/* ./; \
  make -C /usr/src/parallels/kmods -f Makefile.kmods -j "$(nproc)" compile \
    SRC='/usr/src/linux' \
    KERNEL_DIR='/usr/src/linux' \
    KVER="$(< /usr/src/linux/include/config/kernel.release)" \
    PRL_FREEZE_SKIP=1 \
  ; \
  find /usr/src/parallels/kmods -name '*.ko' -exec cp -v '{}' lib/modules/*/ ';'; \
  tcl-chroot prltoolsd -V

# https://github.com/xenserver/xe-guest-utilities/tags
# updated via "update.sh"
ENV XEN_VERSION 8.4.0

RUN wget -O /xen.tgz "https://github.com/xenserver/xe-guest-utilities/archive/v$XEN_VERSION.tar.gz"; \
  mkdir /usr/src/xen; \
  tar --extract --file /xen.tgz --directory /usr/src/xen --strip-components 1; \
  rm /xen.tgz
RUN cd /usr/src/xen; \
  go mod vendor; \
  mkdir vendor/xe-guest-utilities
RUN make -C /usr/src/xen -j "$(nproc)" VENDORDIR="/usr/src/xen/vendor/xe-guest-utilities" PRODUCT_VERSION="$XEN_VERSION" RELEASE='boot2docker'; \
  tar --extract --file "/usr/src/xen/build/dist/xe-guest-utilities_$XEN_VERSION-boot2docker_x86_64.tgz"; \
  tcl-chroot xenstore || [ "$?" = 1 ]

# Hyper-V KVP Daemon
RUN make -C /usr/src/linux/tools/hv hv_kvp_daemon; \
  cp /usr/src/linux/tools/hv/hv_kvp_daemon usr/local/sbin/; \
  tcl-chroot hv_kvp_daemon --help || [ "$?" = 1 ]

# Windows Subsystem for Linux config for Windows 11 and Server 2022 and later
COPY files/wsl.conf etc/wsl.conf

# TCL includes QEMU's guest agent 2.0.2+ (no reason to compile that ourselves)
RUN qemuTemp="$(mktemp -d)"; \
  pushd "$qemuTemp"; \
  for mirror in $TCL_MIRRORS; do \
    if wget -O qemu.tcz "$mirror/$TCL_MAJOR/x86_64/tcz/qemu.tcz" && \
      wget -O- "$mirror/$TCL_MAJOR/x86_64/tcz/qemu.tcz.md5.txt" | md5sum -c -; \
    then \
      break; \
    fi; \
  done; \
  wget -O- "$mirror/$TCL_MAJOR/x86_64/tcz/qemu.tcz.md5.txt" | md5sum -c -; \
  unsquashfs -f -d . qemu.tcz /usr/local/bin/qemu-ga; \
  popd; \
  cp "$qemuTemp/usr/local/bin/qemu-ga" usr/local/bin/; \
  rm -rf "$qemuTemp"; \
  tcl-chroot qemu-ga --help || [ "$?" = 1 ]

# TCL includes SPICE's agent 0.16.0+ (no reason to compile that ourselves)
RUN tcl-tce-load spice-vdagent; \
  tcl-chroot spice-vdagentd -h || [ "$?" = 1 ]; \
  tcl-chroot spice-vdagent -h || [ "$?" = 1 ]

# scan all built modules for kernel loading
RUN tcl-chroot depmod "$(< /usr/src/linux/include/config/kernel.release)"

# https://github.com/tianon/cgroupfs-mount/releases
ENV CGROUPFS_MOUNT_VERSION=1.4

RUN wget -O usr/local/sbin/cgroupfs-mount "https://github.com/tianon/cgroupfs-mount/raw/${CGROUPFS_MOUNT_VERSION}/cgroupfs-mount"; \
  chmod +x usr/local/sbin/cgroupfs-mount; \
  tcl-chroot cgroupfs-mount

# https://download.docker.com/linux/static/stable/x86_64/
# updated via "update.sh"
ENV DOCKER_VERSION 28.2.2

# Get the Docker binaries with version that matches our boot2docker version.
RUN DOCKER_CHANNEL='stable'; \
  case "$DOCKER_VERSION" in \
# all the pre-releases go in the "test" channel
    *-rc* | *-beta* | *-tp* ) DOCKER_CHANNEL='test' ;; \
  esac; \
  \
  wget -O /docker.tgz "https://download.docker.com/linux/static/$DOCKER_CHANNEL/x86_64/docker-$DOCKER_VERSION.tgz"; \
  tar -zxvf /docker.tgz -C "usr/local/bin" --strip-components=1; \
  rm /docker.tgz; \
  \
# download bash-completion too
  wget -O usr/local/share/bash-completion/completions/docker "https://github.com/docker/cli/raw/v${DOCKER_VERSION}/contrib/completion/bash/docker"; \
  \
  for binary in \
    containerd \
    ctr \
    docker \
    docker-init \
    dockerd \
    runc \
  ; do \
    chroot . "$binary" --version; \
  done

# CTOP - https://github.com/bcicen/ctop
# updated via "update.sh"
ENV CTOP_VERSION 0.7.7
RUN wget -O usr/local/bin/ctop "https://github.com/bcicen/ctop/releases/download/v$CTOP_VERSION/ctop-$CTOP_VERSION-linux-amd64" ; \
  chmod +x usr/local/bin/ctop

# set up docker
RUN mkdir -p etc/docker; \
  { \
    echo '{'; \
    echo '    "features": {'; \
    echo '        "buildkit": true'; \
    echo '    }'; \
    echo '}'; \
  } > etc/docker/daemon.json

# set up a few branding bits
RUN { \
    echo 'NAME=Boot2Docker'; \
    echo "VERSION=$DOCKER_VERSION"; \
    echo 'ID=boot2docker'; \
    echo 'ID_LIKE=tcl'; \
    echo "VERSION_ID=$DOCKER_VERSION"; \
    echo "PRETTY_NAME=\"Boot2Docker $DOCKER_VERSION (TCL $TCL_VERSION)\""; \
    echo 'ANSI_COLOR="1;34"'; \
    echo 'HOME_URL="https://github.com/troyxmccall/boot2docker"'; \
    echo 'SUPPORT_URL="https://blog.docker.com/2016/11/introducing-docker-community-directory-docker-community-slack/"'; \
    echo 'BUG_REPORT_URL="https://github.com/troyxmccall/boot2docker/issues"'; \
  } > etc/os-release; \
  sed -i 's/HOSTNAME="box"/HOSTNAME="boot2docker"/g' usr/bin/sethostname; \
  tcl-chroot sethostname; \
  [ "$(< etc/hostname)" = 'boot2docker' ]; \
  for num in 0 1 2 3; do \
    echo "server $num.boot2docker.pool.ntp.org"; \
  done > etc/ntp.conf; \
  rm -v etc/sysconfig/ntpserver; \
  sed -i "s|\$(grep '^VERSION_ID=' /etc/os-release)|VERSION_ID=$TCL_VERSION|g" etc/init.d/tc-functions

# fix tce-load
RUN mv etc/init.d/tc-functions etc/init.d/tc-functions.orig; \
  sed "s|\$(grep '^VERSION_ID=' /etc/os-release)|VERSION_ID=$TCL_VERSION|g" \
    etc/init.d/tc-functions.orig \
    > etc/init.d/tc-functions

COPY files/forgiving-getty files/shutdown ./usr/local/sbin/

# getty/inittab setup
RUN awk -F: ' \
    $1 == "tty1" { \
      print "tty1::respawn:/usr/local/sbin/forgiving-getty tty1"; \
      print "ttyS0::respawn:/usr/local/sbin/forgiving-getty ttyS0"; \
      next; \
    } \
    $1 ~ /^#?tty/ { next } \
    { print } \
  ' etc/inittab > etc/inittab.new; \
  mv etc/inittab.new etc/inittab; \
  grep forgiving-getty etc/inittab; \
# /sbin/autologin likes to invoke getty directly, so we skip that noise (especially since we want to always autologin)
# (and getty's "-l" argument cannot accept anything but a single command to "exec" directly -- no args)
# (and getty's "-n" argument to autologin doesn't seem to work properly)
  { \
    echo '#!/bin/sh'; \
    echo 'user="$(cat /etc/sysconfig/tcuser 2>/dev/null)"'; \
    echo 'exec login -f "${user:-docker}"'; \
  } > usr/local/sbin/autologin; \
  chmod +x usr/local/sbin/autologin

# ssh config prep
RUN [ ! -f usr/local/etc/sshd_config ]; \
  sed -r \
    -e 's/^#(UseDNS[[:space:]])/\1/' \
    -e 's/^#(PermitUserEnvironment)[[:space:]].*$/\1 yes/' \
    usr/local/etc/ssh/sshd_config.orig \
    > usr/local/etc/ssh/sshd_config; \
  grep '^UseDNS no$' usr/local/etc/ssh/sshd_config; \
# "This sshd was compiled with PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin
# (and there are several important binaries in /usr/local/sbin that "docker-machine" needs to invoke like "ip" and "iptables")
  grep '^PermitUserEnvironment yes$' usr/local/etc/ssh/sshd_config; \
  mkdir -p home/docker/.ssh; \
  echo 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' > home/docker/.ssh/environment; \
# acpid prep (looks in the wrong path for /etc/acpi)
  ln -sT ../usr/local/etc/acpi etc/acpi; \
  [ -z "$(ls -A etc/acpi/events)" ]; \
  { echo 'event=button/power'; echo 'action=/usr/bin/env poweroff'; } > etc/acpi/events/power; \
# explicit UTC timezone (especially for container bind-mounting)
  echo 'UTC' > etc/timezone; \
  cp -vL /usr/share/zoneinfo/UTC etc/localtime; \
# "dockremap" user/group so "--userns-remap=default" works out-of-the-box
  tcl-chroot addgroup -S dockremap; \
  tcl-chroot adduser -S -G dockremap dockremap; \
  echo 'dockremap:165536:65536' | tee etc/subuid | tee etc/subgid

RUN savedAptMark="$(apt-mark showmanual)"; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    isolinux \
    syslinux-common \
  ; \
  rm -rf /var/lib/apt/lists/*; \
  mkdir -p /tmp/iso/isolinux; \
  cp -v \
    /usr/lib/ISOLINUX/isolinux.bin \
    /usr/lib/syslinux/modules/bios/ldlinux.c32 \
    /usr/lib/syslinux/modules/bios/libutil.c32 \
    /usr/lib/syslinux/modules/bios/menu.c32 \
    /tmp/iso/isolinux/ \
  ; \
  cp -v /usr/lib/ISOLINUX/isohdpfx.bin /tmp/; \
  apt-mark auto '.*' > /dev/null; \
  apt-mark manual $savedAptMark; \
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false
COPY files/isolinux.cfg /tmp/iso/isolinux/

COPY files/init.d/* ./etc/init.d/
COPY files/bootsync.sh ./opt/

# temporary boot debugging aid
#RUN sed -i '2i set -x' etc/init.d/tc-config

COPY files/make-b2d-iso.sh /usr/local/bin/
RUN time make-b2d-iso.sh; \
  du -hs /tmp/boot2docker.iso

CMD ["sh", "-c", "[ -t 1 ] && exec bash || exec cat /tmp/boot2docker.iso"]
