//
// Copyright (c) 2016-present, Facebook, Inc.
// All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.
//

#import "ARTSRError.h"

NS_ASSUME_NONNULL_BEGIN

NSError *ARTSRErrorWithDomainCodeDescription(NSString *domain, NSInteger code, NSString *description)
{
    return [NSError errorWithDomain:domain code:code userInfo:@{ NSLocalizedDescriptionKey: description }];
}

NSError *ARTSRErrorWithCodeDescription(NSInteger code, NSString *description)
{
    return ARTSRErrorWithDomainCodeDescription(ARTSRWebSocketErrorDomain, code, description);
}

NSError *ARTSRErrorWithCodeDescriptionUnderlyingError(NSInteger code, NSString *description, NSError *underlyingError)
{
    return [NSError errorWithDomain:ARTSRWebSocketErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: description,
                                       NSUnderlyingErrorKey: underlyingError }];
}

NSError *ARTSRHTTPErrorWithCodeDescription(NSInteger httpCode, NSInteger errorCode, NSString *description)
{
    return [NSError errorWithDomain:ARTSRWebSocketErrorDomain
                               code:errorCode
                           userInfo:@{ NSLocalizedDescriptionKey: description,
                                       ARTSRHTTPResponseErrorKey: @(httpCode) }];
}

NS_ASSUME_NONNULL_END
