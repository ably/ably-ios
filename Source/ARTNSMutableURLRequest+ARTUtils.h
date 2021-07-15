//
//  NSMutableURLRequest+ARTUtils.h
//  Ably
//
//  Created by Łukasz Szyszkowski on 05/07/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSMutableURLRequest (ARTUtils)

- (void)appendQueryItem:(NSURLQueryItem *)item;

@end

NS_ASSUME_NONNULL_END
