//
//  ARTStringifiable+Private.h
//  Ably
//
//  Created by Łukasz Szyszkowski on 21/06/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ARTStringifiable()

- (nonnull instancetype)initWithString:(nonnull NSString *)value;
- (nonnull instancetype)initWithNumber:(nonnull NSNumber *)value;
- (nonnull instancetype)initWithBool:(BOOL)value;

@end
