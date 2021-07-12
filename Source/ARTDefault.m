//
//  ARTDefault.m
//  ably
//
//  Created by vic on 01/06/2015.
//  Copyright (c) 2015 Ably. All rights reserved.
//

#import "ARTDefault+Private.h"

#import "Ably.h"

@implementation ARTDefault

NSString *const ARTDefault_restHost = @"rest.ably.io";
NSString *const ARTDefault_realtimeHost = @"realtime.ably.io";
NSString *const ARTDefault_version = @"1.2";
NSString *const ARTDefault_ablyBundleId = @"io.ably.Ably";
NSString *const ARTDefault_bundleVersionKey = @"CFBundleShortVersionString";
NSString *const ARTDefault_bundleBuildNumberKey = @"CFBundleVersion";
NSString *const ARTDefault_platform = @"cocoa";
NSString *const ARTDefault_variant =
    #if TARGET_OS_IOS
        @".ios"
    #elif TARGET_OS_TV
        @".tvos"
    #elif TARGET_OS_WATCH
        @".watchos"
    #elif TARGET_OS_OSX
        @".macos"
    #else
        @""
    #endif
    ;

static NSTimeInterval _realtimeRequestTimeout = 10.0;
static NSTimeInterval _fallbackRetryTimeout = 600.0; // TO3l10
static NSTimeInterval _connectionStateTtl = 60.0;
static NSInteger _maxMessageSize = 65536;

+ (NSArray*)fallbackHosts {
    return @[@"a.ably-realtime.com", @"b.ably-realtime.com", @"c.ably-realtime.com", @"d.ably-realtime.com", @"e.ably-realtime.com"];
}

+ (NSString*)restHost {
    return ARTDefault_restHost;
}

+ (NSString*)realtimeHost {
    return ARTDefault_realtimeHost;
}

+ (NSString *)version {
    return ARTDefault_version;
}

+ (int)port {
    return 80;
}

+ (int)tlsPort {
    return 443;
}

+ (NSTimeInterval)ttl {
    return 60 * 60;
}

+ (NSTimeInterval)fallbackRetryTimeout {
    return _fallbackRetryTimeout;
}

+ (NSTimeInterval)connectionStateTtl {
    return _connectionStateTtl;
}

+ (NSTimeInterval)realtimeRequestTimeout {
    return _realtimeRequestTimeout;
}

+ (NSInteger)maxMessageSize {
    return _maxMessageSize;
}

+ (void)setRealtimeRequestTimeout:(NSTimeInterval)value {
    @synchronized (self) {
        _realtimeRequestTimeout = value;
    }
}

+ (void)setConnectionStateTtl:(NSTimeInterval)value {
    @synchronized (self) {
        _connectionStateTtl = value;
    }
}

+ (void)setMaxMessageSize:(NSInteger)value {
    @synchronized (self) {
        _maxMessageSize = value;
    }
}

+ (void)setFallbackRetryTimeout:(NSTimeInterval)value {
    @synchronized (self) {
        _fallbackRetryTimeout = value;
    }
}

+ (NSString *)libraryVersion {
    return [NSString stringWithFormat:@"%@%@-%@", ARTDefault_platform, ARTDefault_variant, [self bundleVersion]];
}

+ (NSString *)bundleVersion {
    NSDictionary *infoDictionary = [[NSBundle bundleForClass: [ARTDefault class]] infoDictionary];
    return infoDictionary[ARTDefault_bundleVersionKey];
}

+ (NSString *)bundleBuildNumber {
    NSDictionary *infoDictionary = [[NSBundle bundleForClass: [ARTDefault class]] infoDictionary];
    return infoDictionary[ARTDefault_bundleBuildNumberKey];
}

@end
