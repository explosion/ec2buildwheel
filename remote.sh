#!/bin/bash

# This script is uploaded to the builder VM, and executes as the 'ubuntu' user.
# It expects ~/build-info.json to contain an object with the following keys:
#   repo_url: URL of a git repo to clone
#   commit: the commit to check out from that repo (can be a tag)
#   package_name: the python package import name, to pass to pytest --pyargs
#
# On successful exit, the wheels are in ~/wheelhouse

set -euxo pipefail

id
date
uname -a
env

# cloud-init modifies /etc/apt/sources.list, so make sure it's finished before we
# continue
cloud-init status --wait

sudo apt-get -y update
sudo apt-get -y install jq git python3-pip python3-venv docker.io

REPO_URL="$(jq -r .repo_url ~/build-info.json)"
COMMIT="$(jq -r .commit ~/build-info.json)"
PACKAGE_NAME="$(jq -r .package_name ~/build-info.json)"
MODULE_NAME="${PACKAGE_NAME//-/_}"

git clone $REPO_URL checkout
cd checkout
git checkout $COMMIT

python3 -m venv ~/myenv
~/myenv/bin/pip install cibuildwheel

export CIBW_BEFORE_ALL="curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal --default-toolchain stable && source ~/.cargo/env"
if [ -e build-constraints.txt ]; then
    export CIBW_ENVIRONMENT='PIP_CONSTRAINT=build-constraints.txt'
fi
export CIBW_BUILD_FRONTEND=pip
export CIBW_SKIP="pp* *-musllinux*"
export CIBW_BEFORE_TEST="pip install -r requirements.txt"
export CIBW_TEST_COMMAND="pytest --tb=native --pyargs $MODULE_NAME"

~/myenv/bin/cibuildwheel --platform linux --output-dir ~/wheelhouse

ls -l ~/wheelhouse
