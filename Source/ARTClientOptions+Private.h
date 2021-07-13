//
//  ARTClientOptions+Private.h
//  ably
//
//  Created by Toni Cárdenas on 24/2/16.
//  Copyright © 2016 Ably. All rights reserved.
//

#import <Ably/ARTClientOptions.h>

@interface ARTClientOptions ()

@property (nullable, strong, nonatomic) NSString *channelNamePrefix;

@property (readonly) BOOL isProductionEnvironment;
@property (readonly) BOOL hasEnvironment;
@property (readonly) BOOL hasEnvironmentDifferentThanProduction;
@property (readonly) BOOL hasCustomRestHost;
@property (readonly) BOOL hasDefaultRestHost;
@property (readonly) BOOL hasCustomRealtimeHost;
@property (readonly) BOOL hasDefaultRealtimeHost;
@property (readonly) BOOL hasCustomPort;
@property (readonly) BOOL hasCustomTlsPort;

+ (void)setDefaultEnvironment:(NSString *_Nullable)environment;
+ (BOOL)getDefaultIdempotentRestPublishingForVersion:(NSString *_Nonnull)version;
- (NSURLComponents *_Nonnull)restUrlComponents;

@end
