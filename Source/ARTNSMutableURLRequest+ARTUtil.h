//
//  NSMutableURLRequest+ARTUtil.h
//  Ably
//
//  Created by Łukasz Szyszkowski on 09/07/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSMutableURLRequest (ARTUtil)

/**
 Note: this method is using URLComponents to deconstruct URL of this request then it replacing `host` with new one.
 If for some reasons new URL constructed by URLComponents is `nil`, old URL is a valiid URL for this request.
 */
- (void)replaceHostWith:(NSString *)host;

@end

NS_ASSUME_NONNULL_END
