//
//  ARTStringifiable.m
//  Ably
//
//  Created by Łukasz Szyszkowski on 21/06/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import "ARTStringifiable.h"
#import "ARTStringifiable+Private.h"

@implementation ARTStringifiable

- (instancetype)initWithString:(NSString *)value {
    self = [super init];
    if (self) {
        _stringValue = value;
    }
    return self;
}

- (instancetype)initWithNumber:(NSNumber *)value {
    self = [super init];
    if (self) {
        _stringValue = [value stringValue];
    }
    return self;
}

- (instancetype)initWithBool:(BOOL)value {
    self = [super init];
    if (self) {
        _stringValue = [NSString stringWithFormat:@"%@", value ? @"true" : @"false"];
    }
    return self;
}


+ (ARTStringifiable *)withString:(NSString *)value {
    return [[ARTStringifiable alloc] initWithString:value];
}

+ (ARTStringifiable *)withNumber:(NSNumber *)value {
    return [[ARTStringifiable alloc] initWithNumber:value];
}

+ (ARTStringifiable *)withBool:(BOOL)value {
    return [[ARTStringifiable alloc] initWithBool:value];
}

@end
