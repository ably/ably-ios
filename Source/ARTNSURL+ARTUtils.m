//
//  NSURL+ARTUtils.m
//  Ably
//
//  Created by Łukasz Szyszkowski on 07/07/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import "ARTNSURL+ARTUtils.h"

@implementation NSURL (ARTUtils)

+ (NSURL *)copyFromURL:(NSURL *)url withHost:(NSString *)host {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];
    components.host = host;
    
    return components.URL;
}

@end
