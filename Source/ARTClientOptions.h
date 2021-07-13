//
//  ARTClientOptions.h
//
//  Created by Jason Choy on 18/12/2014.
//  Copyright (c) 2014 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <Ably/ARTAuthOptions.h>
#import <Ably/ARTLog.h>

@class ARTPlugin;
@class ARTStringifiable;
@protocol ARTPushRegistererDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface ARTClientOptions : ARTAuthOptions

@property (readwrite, strong, nonatomic, getter=getRestHost) NSString *restHost;
@property (readwrite, strong, nonatomic, getter=getRealtimeHost) NSString *realtimeHost;

@property (nonatomic, assign) NSInteger port;
@property (nonatomic, assign) NSInteger tlsPort;
@property (readwrite, strong, nonatomic) NSString *environment;
@property (nonatomic, assign) BOOL tls;
@property (nonatomic, strong, readwrite) ARTLog *logHandler;
@property (nonatomic, assign) ARTLogLevel logLevel;

@property (readwrite, assign, nonatomic) BOOL queueMessages;
@property (readwrite, assign, nonatomic) BOOL echoMessages;
@property (readwrite, assign, nonatomic) BOOL useBinaryProtocol;
@property (readwrite, assign, nonatomic) BOOL autoConnect;
@property (nullable, readwrite, copy, nonatomic) NSString *recover;
@property (readwrite, assign, nonatomic) BOOL pushFullWait;

/**
 The id of the client represented by this instance.
 The clientId is relevant to presence operations, where the clientId is the principal identifier of the client in presence update messages. The clientId is also relevant to authentication; a token issued for a specific client may be used to authenticate the bearer of that token to the service.
 */
@property (readwrite, strong, nonatomic, nullable) NSString *clientId;

@property (readwrite, strong, nonatomic, nullable) ARTTokenParams *defaultTokenParams;

/**
 Represents the timeout (in seconds) to retry connection when it's disconnected.
 When the connection is in the DISCONNECTED state, how frequently the client library attempts to reconnect automatically.
 */
@property (readwrite, assign, nonatomic) NSTimeInterval disconnectedRetryTimeout;

/**
 Represents the timeout (in seconds) to retry connection when it's suspended.
 When the connection is in the SUSPENDED state, how frequently the client library attempts to reconnect automatically.
 */
@property (readwrite, assign, nonatomic) NSTimeInterval suspendedRetryTimeout;

/**
 Represents the timeout (in seconds) to re-attach the channel automatically.
 When a channel becomes SUSPENDED following a server initiated DETACHED, after this delay in milliseconds, if the channel is still SUSPENDED and the connection is CONNECTED, the client library will attempt to re-attach.
 */
@property (readwrite, assign, nonatomic) NSTimeInterval channelRetryTimeout;

/**
 Timeout for opening the connection, available in the client library if supported by the transport.
 */
@property (readwrite, assign, nonatomic) NSTimeInterval httpOpenTimeout;

/**
 Timeout for any single HTTP request and response.
 */
@property (readwrite, assign, nonatomic) NSTimeInterval httpRequestTimeout;

/**
 Max number of fallback host retries for HTTP requests that fail due to network issues or server problems.
 */
@property (readwrite, assign, nonatomic) NSUInteger httpMaxRetryCount;

/**
 Max elapsed time in which fallback host retries for HTTP requests will be attempted i.e. if the first default host attempt takes 5s, and then the subsequent fallback retry attempt takes 7s, no further fallback host attempts will be made as the total elapsed time of 12s exceeds the default 10s limit.
 */
@property (readwrite, assign, nonatomic) NSTimeInterval httpMaxRetryDuration;

/**
 Optionally allows one or more fallback hosts to be used instead of the default fallback hosts.
 */
@property (nullable, nonatomic, copy) NSArray<NSString *> *fallbackHosts;

/**
 Optionally allows the default fallback hosts `[a-e].ably-realtime.com` to be used when `environment` is not production or a custom realtime or REST host endpoint is being used. It is never valid to configure `fallbackHost` and set `fallbackHostsUseDefault` to `true`.
 */
@property (assign, nonatomic) BOOL fallbackHostsUseDefault;

/**
 Report uncaught exceptions to Ably, together with the last lines of the logger. This helps Ably fix bugs. Set to nil to disable.
 */
@property (readwrite, strong, nonatomic, nullable) NSString *logExceptionReportingUrl;

/**
 The queue to which all calls to user-provided callbacks will be dispatched
 asynchronously. It will be used as target queue for an internal, serial queue.

 It defaults to the main queue.
 */
@property (readwrite, strong, nonatomic) dispatch_queue_t dispatchQueue;

/**
 The queue to which all internal concurrent operations will be dispatched.
 It must be a serial queue. It shouldn't be the same queue as dispatchQueue.

 It defaults to a newly created serial queue.
 */
@property (readwrite, strong, nonatomic) dispatch_queue_t internalDispatchQueue;

/**
 True when idempotent publishing is enabled for all messages published via REST.

 When this feature is enabled, the client library will add a unique ID to every published message (without an ID) ensuring any failed published attempts (due to failures such as HTTP requests failing mid-flight) that are automatically retried will not result in duplicate messages being published to the Ably platform.

 Note: This is a beta unsupported feature!
 */
@property (readwrite, assign, nonatomic) BOOL idempotentRestPublishing;

/**
 If enabled, every REST request to Ably includes a `request_id` query string parameter. This request ID remain the same if a request is retried to a fallback host.
 */
@property (readwrite, assign, nonatomic) BOOL addRequestIds;

/**
 Additional parameters to be sent in the querystring when initiating a realtime connection. Keys are Strings, values are Stringifiable (a value that can be coerced to a string in order to be sent as a querystring parameter. Supported values should be at least strings, numbers, and booleans, with booleans stringified as true and false. If this is unidiomatic to the language, the implementer may consider this as equivalent to String).
 
 Note:  If a key in transportParams is one the library sends by default (for example, v or heartbeats), the value in transportParams takes precedence.
 */
@property (nonatomic, copy, nullable) NSDictionary<NSString *, ARTStringifiable *> *transportParams;

/**
 The object that processes Push activation/deactivation-related actions.
 */
@property (nullable, weak, nonatomic) id<ARTPushRegistererDelegate, NSObject> pushRegistererDelegate;

- (BOOL)isBasicAuth;
- (NSURL *)restUrl;
- (NSURL *)realtimeUrl;
- (BOOL)hasCustomRestHost;
- (BOOL)hasDefaultRestHost;
- (BOOL)hasCustomRealtimeHost;
- (BOOL)hasDefaultRealtimeHost;

@end

NS_ASSUME_NONNULL_END
