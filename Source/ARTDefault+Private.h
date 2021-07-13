//
//  ARTDefault+Private.h
//  ably
//
//  Created by Ricardo Pereira on 09/02/16.
//  Copyright © 2016 Ably. All rights reserved.
//

#import <Ably/ARTDefault.h>

extern NSString *const ARTDefault_libName;
extern NSString *const ARTDefault_variant;

@interface ARTDefault (Private)

+ (void)setRealtimeRequestTimeout:(NSTimeInterval)value;
+ (void)setConnectionStateTtl:(NSTimeInterval)value;
+ (void)setMaxMessageSize:(NSInteger)value;

@end
