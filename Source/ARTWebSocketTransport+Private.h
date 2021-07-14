//
//  ARTWebSocketTransport+Private.h
//  ably
//
//  Created by Ricardo Pereira on 17/2/16.
//  Copyright © 2016 Ably. All rights reserved.
//

#import <Ably/ARTWebSocketTransport.h>
#import <Ably/CompatibilityMacros.h>
#import <Ably/ARTSRWebSocket.h>
#import <Ably/ARTEncoder.h>
#import <Ably/ARTAuth.h>
#import <Ably/ARTWebSocket.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARTWebSocketTransport () <ARTWebSocketDelegate>

+ (void)setWebSocketClass:(Class)webSocketClass;

// From RestClient
@property (readwrite, strong, nonatomic) id<ARTEncoder> encoder;
@property (readonly, strong, nonatomic) ARTLog *logger;
@property (readonly, strong, nonatomic) ARTClientOptions *options;

@property (readwrite, strong, nonatomic, nullable) id<ARTWebSocket> websocket;
@property (readwrite, strong, nonatomic, nullable) NSURL *websocketURL;

- (NSURL *)setupWebSocket:(NSArray<NSURLQueryItem *> *)params withOptions:(ARTClientOptions *)options resumeKey:(NSString *_Nullable)resumeKey connectionSerial:(NSNumber *_Nullable)connectionSerial;

- (void)setState:(ARTRealtimeTransportState)state;

@end

#pragma mark - ARTEvent

@interface ARTEvent (TransportState)
- (instancetype)initWithTransportState:(ARTRealtimeTransportState)value;
+ (instancetype)newWithTransportState:(ARTRealtimeTransportState)value;

@end

NS_ASSUME_NONNULL_END
