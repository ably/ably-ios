//
//  ARTRest+Private.h
//
//  Created by Jason Choy on 21/12/2014.
//  Copyright (c) 2014 Ably. All rights reserved.
//

#import <Ably/ARTRest.h>
#import <Ably/ARTHttp.h>
#import "ARTRestChannels+Private.h"
#import "ARTPush+Private.h"

@protocol ARTEncoder;
@protocol ARTHTTPExecutor;
@protocol ARTDeviceStorage;
@class ARTRealtimeInternal;
@class ARTAuthInternal;

NS_ASSUME_NONNULL_BEGIN

/// ARTRest private methods that are used internally and for internal testing
@interface ARTRestInternal : NSObject <ARTRestProtocol, ARTHTTPAuthenticatedExecutor>

@property (nonatomic, strong, readonly) ARTRestChannelsInternal *channels;
@property (nonatomic, strong, readonly) ARTAuthInternal *auth;
@property (nonatomic, strong, readonly) ARTPushInternal *push;
#if TARGET_OS_IOS
@property (nonnull, nonatomic, readonly, getter=device) ARTLocalDevice *device;
@property (nonnull, nonatomic, readonly, getter=device_nosync) ARTLocalDevice *device_nosync;
#endif

@property (nonatomic, strong, readonly) ARTClientOptions *options;
@property (nonatomic, weak, nullable) ARTRealtimeInternal *realtime; // weak because realtime owns self
@property (readonly, strong, nonatomic) id<ARTEncoder> defaultEncoder;
@property (readonly, strong, nonatomic) NSString *defaultEncoding; //Content-Type
@property (readonly, strong, nonatomic) NSDictionary<NSString *, id<ARTEncoder>> *encoders;

// Must be atomic!
@property (readwrite, strong, atomic, nullable) NSString *prioritizedHost;

@property (nonatomic, strong) id<ARTHTTPExecutor> httpExecutor;
@property (nonatomic) id<ARTDeviceStorage> storage;

@property (nonatomic, readonly, getter=getBaseUrl) NSURL *baseUrl;
@property (nullable, nonatomic, copy) NSString *currentFallbackHost;
@property (readonly, nonatomic) CFAbsoluteTime fallbackRetryExpiration;

@property (nonatomic, strong, readonly) ARTLog *logger;

@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) dispatch_queue_t userQueue;

// MARK: Not accessible by tests
@property (readonly, strong, nonatomic) ARTHttp *http;
@property (readwrite, assign, nonatomic) int fallbackCount;

- (instancetype)initWithOptions:(ARTClientOptions *)options realtime:(ARTRealtimeInternal *_Nullable)realtime;
- (nullable NSObject<ARTCancellable> *)_time:(void (^)(NSDate *_Nullable, NSError *_Nullable))callback;

// MARK: ARTHTTPExecutor

- (nullable NSObject<ARTCancellable> *)executeRequest:(NSURLRequest *)request completion:(nullable void (^)(NSHTTPURLResponse *_Nullable, NSData *_Nullable, NSError *_Nullable))callback;

// MARK: Internal

- (nullable NSObject<ARTCancellable> *)executeRequest:(NSMutableURLRequest *)request withAuthOption:(ARTAuthentication)authOption completion:(void (^)(NSHTTPURLResponse *_Nullable, NSData * _Nullable, NSError * _Nullable))callback;

- (nullable NSObject<ARTCancellable> *)internetIsUp:(void (^)(BOOL isUp))cb;

#if TARGET_OS_IOS
- (void)resetDeviceSingleton;
#endif

@end

@interface ARTRest ()

@property (nonatomic, readonly) ARTRestInternal *internal;

- (void)internalAsync:(void (^)(ARTRestInternal *))use;

@end

NS_ASSUME_NONNULL_END
