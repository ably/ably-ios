//
//  ARTFallback.h
//  ably
//
//  Created by vic on 19/06/2015.
//  Copyright (c) 2015 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ARTHttpResponse;
@class ARTClientOptions;

@interface ARTFallback : NSObject

/**
 Init with fallback hosts array.
 */
- (instancetype)initWithFallbackHosts:(nullable NSArray<NSString *> *)fallbackHosts;

/**
 returns a random fallback host, returns null when all hosts have been popped.
 */
- (nullable NSString *)popFallbackHost;

@end

NS_ASSUME_NONNULL_END
