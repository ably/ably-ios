//
//  NSMutableDictionary+ARTNSMutableDictionary_ARTDictionaryUtil.m
//  Ably
//
//  Created by Łukasz Szyszkowski on 29/06/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import "ARTNSMutableDictionary+ARTDictionaryUtil.h"

@implementation NSMutableDictionary (ARTDictionaryUtil)

- (void)addValueAsURLQueryItem:(NSString *)value forKey:(NSString *)key {
    self[key] = [NSURLQueryItem queryItemWithName:key value:value];
}

@end
