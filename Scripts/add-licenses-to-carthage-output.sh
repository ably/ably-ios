#!/usr/bin/env bash

set -e

ZIP_NAME="Ably.framework.zip"
TEMPDIR=`mktemp -d`
BUILD_DIR=`pwd`

# Unzip Carthage’s output into a temporary directory.
cp "${ZIP_NAME}" "${TEMPDIR}"
unzip "${TEMPDIR}/${ZIP_NAME}" -d "${TEMPDIR}"

# Copy our LICENSE files across.
cp LICENSE "${TEMPDIR}/Carthage"
mkdir "${TEMPDIR}/Carthage/SocketRocket"
cp SocketRocket/LICENSE "${TEMPDIR}/Carthage/SocketRocket"

# Re-zip (replacing the original zip file) then clean up.
cd "${TEMPDIR}"
zip --recurse-paths --symlinks Carthage Carthage
cp "${TEMPDIR}/Carthage.zip" "${BUILD_DIR}/${ZIP_NAME}"
rm -rf "${TEMPDIR}"
