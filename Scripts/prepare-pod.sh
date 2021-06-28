#!/usr/bin/env bash

set -e

sed -i '' -e 's/#import <SocketRocketAblyFork\/\(.*\)>/#import "\1"/g' \
  SocketRocket/SocketRocket/Internal/Delegate/ARTSRDelegateController.h \
  SocketRocket/SocketRocket/Internal/Utilities/ARTSRError.h
