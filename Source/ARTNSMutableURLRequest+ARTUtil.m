//
//  NSMutableURLRequest+ARTUtil.m
//  Ably
//
//  Created by Łukasz Szyszkowski on 09/07/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import "ARTNSMutableURLRequest+ARTUtil.h"

@implementation NSMutableURLRequest (ARTUtil)

- (void)replaceHostWith:(NSString *)host {
    NSURLComponents *components = [NSURLComponents componentsWithURL:self.URL resolvingAgainstBaseURL:YES];
    components.host = host;
    
    if(components != nil) {
        self.URL = components.URL;
    }
}

@end
