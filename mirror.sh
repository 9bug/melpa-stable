#!/bin/bash

set -euo pipefail

SOURCE_BRANCH="master"
TARGET_BRANCH="gh-pages"
declare -A RSYNC_URLS=(
    [melpa]=rsync://melpa.org/packages/
    [melpa_stable]=rsync://stable.melpa.org/packages/
)
declare -A GIT_REPOS=(
    [melpa]=git@github.com:9bug/melpa.git
    [melpa_stable]=git@github.com:9bug/melpa-stable.git
)
declare -A DEPLOY_KEYS=(
    [melpa]=melpa
    [melpa_stable]=melpa_stable
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

for name in "${!RSYNC_URLS[@]}"; do
    rsync_url="${RSYNC_URLS[$name]}"
    git_repo="${GIT_REPOS[$name]}"
    deploy_key="${DEPLOY_KEYS[$name]}"
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
    git add .
    git commit -m "Mirror from $rsync_url to $git_repo at $now"
    popd

    # Get the deploy key by using Travis's stored variables to decrypt deploy_key.enc
    encrypted_key_var="encrypted_${ENCRYPTION_LABEL}_key"
    encrypted_iv_var="encrypted_${ENCRYPTION_LABEL}_iv"
    encrypted_key=${!encrypted_key_var}
    encrypted_iv=${!encrypted_iv_var}
    openssl aes-256-cbc -K "$encrypted_key" -iv "$encrypted_iv" \
            -in "$deploy_key".enc -out "$deploy_key" -d
    chmod 600 "$deploy_key"
    eval "$(ssh-agent -s)"
    ssh-add "$deploy_key"

    # Now that we're all set up, we can push.
    pushd "$build_dir"
    git push --force origin $TARGET_BRANCH
    popd
done
