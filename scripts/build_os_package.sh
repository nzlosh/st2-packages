#!/bin/bash
set -e
set -o pipefail

package_name="$1"
artifact_dir="${ARTIFACT_DIR}"
cores_num=$(/usr/bin/nproc)

export WHEELDIR

platform() {
    # Detect deb based distributions
    if grep -q "debian" <<<$(source /etc/os-release; echo $ID $ID_LIKE); then
        echo "deb"
        return 0
    # Detect rpm based distributions
    elif grep -q "rhel" <<<$(source /etc/os-release; echo $ID $ID_LIKE); then
        echo 'rpm'
        return 0
    # Unidentified/Unsupported distribution.
    else
        return 1
    fi
}

# NOTE: To troubleshoot rpmbuild, add -vv flag to enable debug mode
function build_rpm()
{
    rpmbuild -bb --define '_topdir %(readlink -f build)' rpm/"$package_name".spec
}
function build_deb
{
    dpkg-buildpackage -b -uc -us -j"$cores_num"
}
function copy_rpm
{
    sudo cp -v build/RPMS/*/$1*.rpm "$artifact_dir";
    # Also print some package info for easier troubleshooting
    rpm -q --requires -p build/RPMS/*/$1*.rpm
    rpm -q --provides -p build/RPMS/*/$1*.rpm
}
function copy_deb
{
  sudo cp -v ../"$package_name"*.deb "$artifact_dir" || { echo "Failed to copy .deb file into artifact directory \`$artifact_dir'" ; exit 1; }
  sudo cp -v ../"$package_name"{*.changes,*.dsc} "$artifact_dir" || :;
}

[[ -z "$package_name" ]] && { echo "usage: $0 package_name" && exit 1; }

build_$(platform)
copy_$(platform)
