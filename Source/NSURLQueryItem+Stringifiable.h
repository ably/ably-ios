//
//  NSURLQueryItem+ARTNSURLQueryItem_Stringifiable.h
//  Ably
//
//  Created by Łukasz Szyszkowski on 23/06/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>
@class ARTStringifiable;

NS_ASSUME_NONNULL_BEGIN

@interface NSURLQueryItem (ARTNSURLQueryItem_Stringifiable)

+ (NSURLQueryItem*)itemWithName:(NSString *)name value:(ARTStringifiable *)value;

@end

NS_ASSUME_NONNULL_END
