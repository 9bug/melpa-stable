#!/bin/bash

set -euxo pipefail

SOURCE_BRANCH="master"
TARGET_BRANCH="gh-pages"
MELPA_RSYNC_URL="rsync://stable.melpa.org/packages/"
BUILD_DIR="$HOME"/gh-pages/

# reduce git memory usage
git config --global pack.windowMemory "100m"
git config --global pack.packSizeLimit "100m"
git config --global pack.threads 1

# Pull requests and commits to other branches shouldn't try to deploy,
# just build to verify
if [[ "$TRAVIS_PULL_REQUEST" != "false" || "$TRAVIS_BRANCH" != "$SOURCE_BRANCH" ]]; then
    echo 'does nothing, as building on non-master branch'
    exit 0
fi

# Save some useful information
REPO=$(git config remote.origin.url)
SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}
SHA=$(git rev-parse --verify HEAD)

# Sync MELPA to output directory
mkdir "$BUILD_DIR"
rsync -avz --delete "$MELPA_RSYNC_URL" "$BUILD_DIR"

# Commit the mirror
pushd "$BUILD_DIR"
git init
git checkout -b "$TARGET_BRANCH"
git config user.name "Travis CI"
git config user.email "$COMMIT_AUTHOR_EMAIL"
git remote add origin "$SSH_REPO"
cp "$TRAVIS_BUILD_DIR"/index.html .
date > mirror-updated-date.txt
git add .
git commit -m "Deploy to GitHub Pages: ${SHA}"
popd

# Get the deploy key by using Travis's stored variables to decrypt deploy_key.enc
ENCRYPTED_KEY_VAR="encrypted_${ENCRYPTION_LABEL}_key"
ENCRYPTED_IV_VAR="encrypted_${ENCRYPTION_LABEL}_iv"
ENCRYPTED_KEY=${!ENCRYPTED_KEY_VAR}
ENCRYPTED_IV=${!ENCRYPTED_IV_VAR}
openssl aes-256-cbc -K "$ENCRYPTED_KEY" -iv "$ENCRYPTED_IV" -in deploy_key.enc -out deploy_key -d
chmod 600 deploy_key
eval "$(ssh-agent -s)"
ssh-add deploy_key

# Now that we're all set up, we can push.
pushd "$BUILD_DIR"
git push --force origin $TARGET_BRANCH
popd
