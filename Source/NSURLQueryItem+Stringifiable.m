//
//  NSURLQueryItem+ARTNSURLQueryItem_Stringifiable.m
//  Ably
//
//  Created by Łukasz Szyszkowski on 23/06/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import "NSURLQueryItem+Stringifiable.h"
#import "ARTStringifiable.h"

@implementation NSURLQueryItem (ARTNSURLQueryItem_Stringifiable)

+ (NSURLQueryItem *)itemWithName:(NSString *)name value:(ARTStringifiable *)value {
    return [NSURLQueryItem queryItemWithName:name value:[value stringValue]];
}

@end
