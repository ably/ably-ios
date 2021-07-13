//
//  ARTDefault.m
//  ably
//
//  Created by vic on 01/06/2015.
//  Copyright (c) 2015 Ably. All rights reserved.
//

#import "Ably.h"
#import "ARTDefault+Private.h"
#import <sys/utsname.h>

// NSOperatingSystemVersion has NSInteger as version components for some reason, so mitigate it here.
static inline UInt32 conformVersionComponent(const NSInteger component) {
    return (component < 0) ? 0 : (UInt32)component;
}

NSString *canonizeStringAsAgentToken(NSString *const inputString) {
    NSMutableString *const canonizedString = [NSMutableString string];
    NSMutableCharacterSet *const allowedSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"!#$%&'*+.^_`|~"]; // `-` is allowed character, but it will be inserted anyways, so it's not included here, which greatly simplifies algorithm
    [allowedSet formUnionWithCharacterSet:[NSCharacterSet alphanumericCharacterSet]];
    NSScanner *const scanner = [NSScanner scannerWithString:inputString];
    do {
        NSString *scannedString;
        [scanner scanCharactersFromSet:allowedSet intoString:&scannedString];
        if (scannedString == nil) {
            return @"";
        }
        [scanner scanCharactersFromSet:[allowedSet invertedSet] intoString:nil];
        if ([scanner isAtEnd]) {
            [canonizedString appendString:scannedString];
            break;
        } else {
            [canonizedString appendFormat:@"%@-", scannedString];
        }
    } while (YES);
    return canonizedString;
}

@implementation ARTDefault

NSString *const ARTDefault_restHost = @"rest.ably.io";
NSString *const ARTDefault_realtimeHost = @"realtime.ably.io";
NSString *const ARTDefault_version = @"1.2";
NSString *const ARTDefault_ablyBundleId = @"io.ably.Ably";
NSString *const ARTDefault_bundleVersionKey = @"CFBundleShortVersionString";
NSString *const ARTDefault_bundleBuildNumberKey = @"CFBundleVersion";
NSString *const ARTDefault_platform = @"cocoa";
NSString *const ARTDefault_libName = @"ably-cocoa";
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

+ (NSString *)osName {
    return
        #if TARGET_OS_IOS
            @"iOS"
        #elif TARGET_OS_TV
            @"tvOS"
        #elif TARGET_OS_WATCH
            @"watchOS"
        #elif TARGET_OS_OSX
            @"macOS"
        #else
            nil
        #endif
        ;
}

+ (NSString *)osVersionString {
    static NSString *versionString;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
        versionString = [NSString stringWithFormat:@"%u.%u.%u",
                         conformVersionComponent(version.majorVersion),
                         conformVersionComponent(version.minorVersion),
                         conformVersionComponent(version.patchVersion)];
    });
    return versionString;
}

+ (NSString *)deviceModel {
    struct utsname systemInfo;
    if (uname(&systemInfo) < 0) {
        return nil;
    }
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

+ (NSString *)deviceModelToken {
    static NSString *modelToken;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *deviceModel = [self deviceModel];
        modelToken = deviceModel != nil ? canonizeStringAsAgentToken(deviceModel) : nil;
    });
    return modelToken;
}

+ (NSString *)agent {
    NSMutableString *agentString = [NSMutableString stringWithFormat:@"%@/%@", ARTDefault_libName, [self bundleVersion]];
    NSString *osName = [self osName];
    if (osName != nil) {
        [agentString appendFormat:@" %@/%@", osName, [self osVersionString]];
    }
    NSString *deviceModelToken = [self deviceModelToken];
    if (deviceModelToken != nil) {
        [agentString appendFormat:@" %@", deviceModelToken];
    }
    return agentString;
}

@end
