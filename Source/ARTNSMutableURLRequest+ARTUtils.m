//
//  NSMutableURLRequest+ARTUtils.m
//  Ably
//
//  Created by Łukasz Szyszkowski on 05/07/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import "ARTNSMutableURLRequest+ARTUtils.h"

@implementation NSMutableURLRequest (ARTUtils)

- (void)appendQueryItem:(NSURLQueryItem *)item {
    NSURLComponents *components = [NSURLComponents componentsWithURL:self.URL resolvingAgainstBaseURL:YES];
    if(components == nil) {
        return;
    }
    
    NSMutableArray<NSURLQueryItem *> *mutableQueryItems = [NSMutableArray arrayWithArray:components.queryItems];
    [mutableQueryItems addObject:item];
    components.queryItems = mutableQueryItems;
    
    NSURL *modifiedURL = components.URL;
    if (modifiedURL != nil) {
        self.URL = modifiedURL;
    }
}

@end
