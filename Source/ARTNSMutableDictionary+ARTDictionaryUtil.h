//
//  NSMutableDictionary+ARTNSMutableDictionary_ARTDictionaryUtil.h
//  Ably
//
//  Created by Łukasz Szyszkowski on 29/06/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSMutableDictionary (ARTDictionaryUtil)

/**
 Creates NSURLQueryItem for given value, and key.
 */
- (void)addValueAsURLQueryItem:(NSString *)value forKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
