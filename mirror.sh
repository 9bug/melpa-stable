#!/bin/bash

set -euxo pipefail

SOURCE_BRANCH="master"
TARGET_BRANCH="gh-pages"
DEPLOY_KEYS_DIR="$HOME"/deploy_keys
declare -A RSYNC_URLS=(
    [melpa]=rsync://melpa.org/packages/
    [melpa_stable]=rsync://stable.melpa.org/packages/
)
declare -A GIT_REPOS=(
    [melpa]=git@github.com:9bug/melpa.git
    [melpa_stable]=git@github.com:9bug/melpa-stable.git
)

# Reduce git memory usage
git config --global pack.windowMemory "100m"
git config --global pack.packSizeLimit "100m"
git config --global pack.threads 1

# Pull requests and commits to other branches shouldn't try to deploy,
# just build to verify
if [[ "$TRAVIS_PULL_REQUEST" != "false" || "$TRAVIS_BRANCH" != "$SOURCE_BRANCH" ]]; then
    echo 'does nothing, as building on non-master branch'
    exit 0
fi

# Get the deploy key by using Travis's stored variables to decrypt
# deploy_keys.tar.enc

mkdir -p "$DEPLOY_KEYS_DIR"
pushd "$DEPLOY_KEYS_DIR"
set +x
echo "decrypt deploy keys archive"
encrypted_key_var="encrypted_${ENCRYPTION_LABEL}_key"
encrypted_iv_var="encrypted_${ENCRYPTION_LABEL}_iv"
encrypted_key=${!encrypted_key_var}
encrypted_iv=${!encrypted_iv_var}
openssl aes-256-cbc -K "$encrypted_key" -iv "$encrypted_iv" \
        -in "$TRAVIS_BUILD_DIR"/deploy_keys.tar.enc -out deploy_keys.tar -d
set -x
tar xvf deploy_keys.tar
chmod 600 ./*
eval "$(ssh-agent -s)"
popd


for name in "${!RSYNC_URLS[@]}"; do
    rsync_url="${RSYNC_URLS[$name]}"
    git_repo="${GIT_REPOS[$name]}"
    build_dir="$HOME/$TARGET_BRANCH/$name"

    mkdir -p "$build_dir"
    rsync -aqz "$rsync_url" "$build_dir"

    pushd "$build_dir"
    git init
    git checkout -b "$TARGET_BRANCH"
    git config user.name "Travis CI"
    git config user.email "$COMMIT_AUTHOR_EMAIL"
    git remote add origin "$git_repo"
    now="$(date)"
    cp "$TRAVIS_BUILD_DIR"/index.html .
    git add . > /dev/null 2>&1
    git commit -m "Mirror from $rsync_url to $git_repo at $now" > /dev/null 2>&1

    ssh-add -D
    ssh-add "$DEPLOY_KEYS_DIR/$name"

    git push --force origin $TARGET_BRANCH
    popd
done
