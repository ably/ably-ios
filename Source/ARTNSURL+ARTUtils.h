//
//  NSURL+ARTUtils.h
//  Ably
//
//  Created by Łukasz Szyszkowski on 07/07/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSURL (ARTUtils)

+ (nullable NSURL *)copyFromURL:(NSURL *)url withHost:(NSString *)host;

@end

NS_ASSUME_NONNULL_END
