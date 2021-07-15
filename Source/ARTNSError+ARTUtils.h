//
//  NSError+ARTUtils.h
//  Ably
//
//  Created by Łukasz Szyszkowski on 05/07/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSError (ARTUtils)

@property (nullable, readonly) NSString *requestId;

+ (NSError *)copyFromError:(NSError *)error withRequestId:(nullable NSString *)requestId;

@end

NS_ASSUME_NONNULL_END
