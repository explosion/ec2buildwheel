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

export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get -y update
sudo -E apt-get -y install jq git python3-pip python3-venv docker.io

REPO_URL="$(jq -r .repo_url ~/build-info.json)"
COMMIT="$(jq -r .commit ~/build-info.json)"
PACKAGE_NAME="$(jq -r .package_name ~/build-info.json)"
MODULE_NAME="${PACKAGE_NAME//-/_}"

git clone $REPO_URL checkout
cd checkout
git checkout $COMMIT
git submodule update --init

python3 -m venv ~/myenv
~/myenv/bin/pip install cibuildwheel

export CIBW_BEFORE_ALL="curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal --default-toolchain stable"
export CIBW_ENVIRONMENT='PATH="$PATH:$HOME/.cargo/bin" SPACY_NUM_BUILD_JOBS=8'
export CIBW_BUILD_VERBOSITY=1
if [ -e build-constraints.txt ]; then
    export CIBW_ENVIRONMENT="$CIBW_ENVIRONMENT PIP_CONSTRAINT=build-constraints.txt"
fi
# build constraints through PIP_CONSTRAINT only work with pip frontend,
# with the drawback that the pip builds aren't isolated
export CIBW_BUILD_FRONTEND=pip
export CIBW_SKIP="pp* *-musllinux* *i686* cp312-*"
# clean cython-generated files between builds to handle profiling
# settings, since the builds aren't isolated
export CIBW_BEFORE_BUILD="pip install numpy 'cython<3' && python setup.py clean"
# torch is not always compiled against the oldest support numpy, so upgrade
# before testing
export CIBW_BEFORE_TEST="unset PIP_CONSTRAINT && pip install -U -r requirements.txt && pip cache purge"
# torch v2.1.0 deadlocks on multiprocessing on aarch64
export CIBW_TEST_COMMAND="unset PIP_CONSTRAINT && pip install -U 'urllib3<2' numpy tokenizers 'torch<2.1.0' transformers {wheel} && pytest --tb=native --pyargs $MODULE_NAME"
# By default cibuildwheel doesn't strip debug info from libraries:
#    https://github.com/pypa/cibuildwheel/issues/331
# But you pretty much always want this for production end-user releases, so we override
# this to add the --strip flag.
export CIBW_REPAIR_WHEEL_COMMAND_LINUX="auditwheel repair --strip -w {dest_dir} {wheel}"

~/myenv/bin/cibuildwheel --platform linux --output-dir ~/wheelhouse
