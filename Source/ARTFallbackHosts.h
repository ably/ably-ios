//
//  ARTFallbackHosts.h
//  Ably
//
//  Created by Ricardo Pereira on 29/04/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ARTClientOptions;

NS_ASSUME_NONNULL_BEGIN

@interface ARTFallbackHosts : NSObject

+ (nullable NSArray<NSString *> *)hostsFromOptions:(ARTClientOptions *)options;

@end

NS_ASSUME_NONNULL_END
