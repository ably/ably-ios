//
// Copyright (c) 2016-present, Facebook, Inc.
// All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.
//

#import "ARTSRURLUtilities.h"

#import "ARTSRHash.h"

NS_ASSUME_NONNULL_BEGIN

NSString *ARTSRURLOrigin(NSURL *url)
{
    NSMutableString *origin = [NSMutableString string];

    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"wss"]) {
        scheme = @"https";
    } else if ([scheme isEqualToString:@"ws"]) {
        scheme = @"http";
    }
    [origin appendFormat:@"%@://%@", scheme, url.host];

    NSNumber *port = url.port;
    BOOL portIsDefault = (!port ||
                          ([scheme isEqualToString:@"http"] && port.integerValue == 80) ||
                          ([scheme isEqualToString:@"https"] && port.integerValue == 443));
    if (!portIsDefault) {
        [origin appendFormat:@":%@", port.stringValue];
    }
    return origin;
}

extern BOOL ARTSRURLRequiresSSL(NSURL *url)
{
    NSString *scheme = url.scheme.lowercaseString;
    return ([scheme isEqualToString:@"wss"] || [scheme isEqualToString:@"https"]);
}

extern NSString *_Nullable ARTSRBasicAuthorizationHeaderFromURL(NSURL *url)
{
    NSData *data = [[NSString stringWithFormat:@"%@:%@", url.user, url.password] dataUsingEncoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:@"Basic %@", ARTSRBase64EncodedStringFromData(data)];
}

/**
 Evaluates to true if we're building on Xcode 11 or later, which means that
 our Foundation build SDK is at least one of the following:
 - iOS 13.0
 - tvOS 13.0
 - macOS 10.15
 - watchOS 6.0
 */
#define _ARTSR_XCODE_VERSION_11_OR_LATER ( \
    __MAC_OS_X_VERSION_MAX_ALLOWED >= 101500 || \
    __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000 || \
    __TV_OS_VERSION_MAX_ALLOWED >= 130000 || \
    __WATCH_OS_VERSION_MAX_ALLOWED >= 60000 \
)

extern NSString *_Nullable ARTSRStreamNetworkServiceTypeFromURLRequest(NSURLRequest *request)
{
    NSString *networkServiceType = nil;
    switch (request.networkServiceType) {
        case NSURLNetworkServiceTypeDefault:
            break;
        case NSURLNetworkServiceTypeResponsiveData:
            break;
        case NSURLNetworkServiceTypeVoIP:
            networkServiceType = NSStreamNetworkServiceTypeVoIP;
            break;
        case NSURLNetworkServiceTypeVideo:
            networkServiceType = NSStreamNetworkServiceTypeVideo;
            break;
        case NSURLNetworkServiceTypeBackground:
            networkServiceType = NSStreamNetworkServiceTypeBackground;
            break;
        case NSURLNetworkServiceTypeVoice:
            networkServiceType = NSStreamNetworkServiceTypeVoice;
            break;

#if _ARTSR_XCODE_VERSION_11_OR_LATER
        case NSURLNetworkServiceTypeAVStreaming:
            networkServiceType = NSStreamNetworkServiceTypeVideo;
            break;
        case NSURLNetworkServiceTypeResponsiveAV:
            networkServiceType = NSStreamNetworkServiceTypeVideo;
            break;
#endif // _ARTSR_XCODE_VERSION_11_OR_LATER

#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 101200 || __IPHONE_OS_VERSION_MAX_ALLOWED >= 100000 || __TV_OS_VERSION_MAX_ALLOWED >= 100000 || __WATCH_OS_VERSION_MAX_ALLOWED >= 30000)
        case NSURLNetworkServiceTypeCallSignaling:
            if (@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)) {
                networkServiceType = NSStreamNetworkServiceTypeCallSignaling;
            }
            break;
#endif
    }
    return networkServiceType;
}

NS_ASSUME_NONNULL_END
