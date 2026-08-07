#!/usr/bin/env bash
set -Eeuo pipefail

# http://tinycorelinux.net/
major='17.x'
version='17.1'
mirrors=(
  https://distro.ibiblio.org/tinycorelinux
)

# https://www.kernel.org/
kernelBase='6.1'
# https://download.docker.com/linux/static/stable/x86_64/
dockerBase='29'
# https://github.com/plougher/squashfs-tools/releases
squashfsBase='4.6'
# https://download.virtualbox.org/virtualbox/
vboxBase='7.1'
# https://www.parallels.com/products/desktop/download/
parallelsBase='19'
# https://github.com/bcicen/ctop/releases
ctopBase='0.7'

# avoid issues with slow Git HTTP interactions (*cough* sourceforge *cough*)
export GIT_HTTP_LOW_SPEED_LIMIT='100'
export GIT_HTTP_LOW_SPEED_TIME='2'
# ... or servers being down
wget() { command wget --timeout=2 "$@" -o /dev/null; }

latest_tcl_for_major() {
  {
    wget -qO- "${mirrors[0]}/${major}/x86_64/archive/" \
      | grep -oE 'href="[0-9]+([.][0-9]+)?/' \
      | cut -d'"' -f2 \
      | cut -d/ -f1 \
      || :
    wget -qO- 'https://distro.ibiblio.org/tinycorelinux/latest-x86_64' \
      || :
  } | sort -Vu | tail -1
}

tclLatest="$(latest_tcl_for_major)"
if [ "$tclLatest" != "$version" ]; then
  echo "Tiny Core Linux has an update! ($tclLatest)"
  # exit 1
fi

kernelLatest="$(
  wget -qO- 'https://www.kernel.org/releases.json' \
    | jq -r '[.releases[] | select(.moniker == "longterm")] | sort_by(.version | split(".") | map(tonumber)) | reverse | .[0].version'
)"
if ! [[ $kernelLatest =~ ^$kernelBase[0-9.]+ ]]; then
  echo "Linux Kernel has an update! ($kernelLatest)"
  # exit 1
fi

dockerLatest="$(
  wget -qO- 'https://download.docker.com/linux/static/stable/x86_64/' \
    | grep -oE 'docker-[0-9]+([.][0-9]+)+[.]tgz' \
    | sed -E 's/^docker-//; s/[.]tgz$//' \
    | sort -Vu \
    | tail -1
)"
if [ -z "$dockerLatest" ] || ! [[ $dockerLatest =~ ^$dockerBase[0-9.]+ ]]; then
  echo "Docker has an update! ($dockerLatest)"
  exit 1
fi

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

seds=(
  -e 's!^ENV TCL_MIRRORS=.*!ENV TCL_MIRRORS="'"${mirrors[*]}"'"!'
  -e 's!^ENV TCL_MAJOR=.*!ENV TCL_MAJOR='"$major"'!'
  -e 's!^ENV TCL_VERSION=.*!ENV TCL_VERSION='"$version"'!'
)

fetch() {
  local file
  for file; do
    local mirror
    for mirror in "${mirrors[@]}"; do
      if wget -qO- "$mirror/$major/$file"; then
        return 0
      fi
    done
  done
  return 1
}

arch='x86_64'
rootfs='rootfs64.gz'

rootfsMd5="$(
  fetch \
    "$arch/archive/$version/distribution_files/$rootfs.md5.txt" \
    "$arch/release/distribution_files/$rootfs.md5.txt"
)"
rootfsMd5="${rootfsMd5%% *}"
seds+=(
  -e 's!^ENV TCL_ROOTFS.*!ENV TCL_ROOTFS="'"$rootfs"'" TCL_ROOTFS_MD5="'"$rootfsMd5"'"!'
)

kernelVersion="$(
  wget -qO- 'https://www.kernel.org/releases.json' \
    | jq -r --arg base "$kernelBase" '.releases[] | .version | select(startswith($base + "."))'
)"
seds+=(
  -e 's!^ENV LINUX_VERSION=.*!ENV LINUX_VERSION='"$kernelVersion"'!'
)

dockerVersion="$(
  wget -qO- 'https://download.docker.com/linux/static/stable/x86_64/' \
    | grep -oE "docker-${dockerBase}[0-9.]*[.]tgz" \
    | sed -E 's/^docker-//; s/[.]tgz$//' \
    | sort -Vu \
    | tail -1
)"
dockerSha256="$(
  wget -qO- "https://download.docker.com/linux/static/stable/x86_64/docker-$dockerVersion.tgz" \
    | sha256sum \
    | cut -d' ' -f1
)"
seds+=(
  -e 's!^ENV DOCKER_VERSION=.*!ENV DOCKER_VERSION='"$dockerVersion"'!'
  -e 's!^ENV DOCKER_SHA256=.*!ENV DOCKER_SHA256='"$dockerSha256"'!'
)

squashfsVersion="$(
  git ls-remote --tags 'https://github.com/plougher/squashfs-tools' \
    | cut -d/ -f3 \
    | cut -d^ -f1 \
    | grep -E '^squashfs-tools-[[:digit:]]+' \
    | cut -d- -f3- \
    | sort -rV \
    | head -1
)"
seds+=(
  -e 's!^ENV SQUASHFS_VERSION=.*!ENV SQUASHFS_VERSION='"$squashfsVersion"'!'
  -e 's!^(# https://github.com/plougher/squashfs-tools/blob/).*(/squashfs-tools/Makefile#L1)$!\1'"$squashfsVersion"'\2!'
)

vboxVersion="$(
  wget -qO- 'https://download.virtualbox.org/virtualbox/' \
    | grep -oE 'href="[0-9.]+/?"' \
    | cut -d'"' -f2 \
    | cut -d/ -f1 \
    | tail -1
)"
vboxSha256="$(
  {
    wget -qO- "https://download.virtualbox.org/virtualbox/$vboxVersion/SHA256SUMS" \
    || wget -qO- "https://www.virtualbox.org/download/hashes/$vboxVersion/SHA256SUMS"
  } | awk '$2 ~ /^[*]?VBoxGuestAdditions_.*[.]iso$/ { print $1 }'
)"
seds+=(
  -e 's!^ENV VBOX_VERSION=.*!ENV VBOX_VERSION='"$vboxVersion"'!'
  -e 's!^ENV VBOX_SHA256=.*!ENV VBOX_SHA256='"$vboxSha256"'!'
)

parallelsVersion="$(
  command wget -SO- --spider "$(
    wget -qO- "https://download.parallels.com/website_links/$(
      wget -qO- https://download.parallels.com/website_links/desktop/index.json \
        | jq -r 'to_entries | sort_by(.key) | reverse | .[0].value.builds.en_US'
    )" \
    | jq -r '.[] | select(.category.name | startswith("Parallels Desktop")) | .contents[] | select(.name | startswith("Parallels Desktop")) | .files.DMG'
  )" 2>&1 >/dev/null \
  | grep -oE 'https://download.parallels.com/desktop/.* \[following]' \
  | sed -re 's|.*/([0-9.-]+)/.*|\1|'
)"
seds+=(
  -e 's!^ENV PARALLELS_VERSION=.*!ENV PARALLELS_VERSION='"$parallelsVersion"'!'
)

xenVersion="$(
  git ls-remote --tags 'https://github.com/xenserver/xe-guest-utilities' \
    | cut -d/ -f3 \
    | cut -d^ -f1 \
    | grep -E '^v[[:digit:]]+' \
    | cut -dv -f2- \
    | sort -rV \
    | head -1
)"
xenSha256="$(
  wget -qO- "https://github.com/xenserver/xe-guest-utilities/archive/v$xenVersion.tar.gz" \
    | sha256sum \
    | cut -d' ' -f1
)"
seds+=(
  -e 's!^ENV XEN_VERSION=.*!ENV XEN_VERSION='"$xenVersion"'!'
  -e 's!^ENV XEN_SHA256=.*!ENV XEN_SHA256='"$xenSha256"'!'
)

ctopVersion="$(
  git ls-remote --tags 'https://github.com/bcicen/ctop' \
    | cut -d/ -f3 \
    | cut -d^ -f1 \
    | grep -E '^v[[:digit:]]+' \
    | cut -dv -f2- \
    | sort -rV \
    | head -1
)"
ctopSha256="$(
  wget -qO- "https://github.com/bcicen/ctop/releases/download/v$ctopVersion/sha256sums.txt" \
    | awk '$2 == "ctop-'"$ctopVersion"'-linux-amd64" { print $1 }'
)"
seds+=(
  -e 's!^ENV CTOP_VERSION=.*!ENV CTOP_VERSION='"$ctopVersion"'!'
  -e 's!^ENV CTOP_SHA256=.*!ENV CTOP_SHA256='"$ctopSha256"'!'
)

set -x
sed -ri "${seds[@]}" Dockerfile
