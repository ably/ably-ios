//
// Copyright (c) 2016-present, Facebook, Inc.
// All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef __attribute__((capability("mutex"))) pthread_mutex_t *ARTSRMutex;

extern ARTSRMutex ARTSRMutexInitRecursive(void);
extern void ARTSRMutexDestroy(ARTSRMutex mutex);

extern void ARTSRMutexLock(ARTSRMutex mutex) __attribute__((acquire_capability(mutex)));
extern void ARTSRMutexUnlock(ARTSRMutex mutex) __attribute__((release_capability(mutex)));

NS_ASSUME_NONNULL_END
