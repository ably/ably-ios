//
// Copyright (c) 2016-present, Facebook, Inc.
// All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.
//

#import <Foundation/Foundation.h>

#import "ARTSRWebSocket.h"

NS_ASSUME_NONNULL_BEGIN

extern NSError *ARTSRErrorWithDomainCodeDescription(NSString *domain, NSInteger code, NSString *description);
extern NSError *ARTSRErrorWithCodeDescription(NSInteger code, NSString *description);
extern NSError *ARTSRErrorWithCodeDescriptionUnderlyingError(NSInteger code, NSString *description, NSError *underlyingError);

extern NSError *ARTSRHTTPErrorWithCodeDescription(NSInteger httpCode, NSInteger errorCode, NSString *description);

NS_ASSUME_NONNULL_END
