
//
//  ARTRealtimeChannel+Private.h
//
//  Created by Ricardo Pereira on 30/09/2015.
//  Copyright (c) 2015 Ably. All rights reserved.
//

#import <Ably/ARTRestChannel+Private.h>
#import <Ably/ARTRealtimeChannel.h>
#import <Ably/ARTPresenceMap.h>
#import <Ably/ARTEventEmitter.h>
#import <Ably/ARTRealtime+Private.h>
#import <Ably/ARTQueuedDealloc.h>
#import <Ably/ARTPushChannel+Private.h>

@class ARTProtocolMessage;
@class ARTRealtimePresenceInternal;

NS_ASSUME_NONNULL_BEGIN

@interface ARTRealtimeChannelInternal : ARTChannel <ARTPresenceMapDelegate, ARTRealtimeChannelProtocol>

@property (readonly) ARTRealtimePresenceInternal *presence;
#if TARGET_OS_IPHONE
@property (readonly) ARTPushChannelInternal *push;
#endif

@property (readwrite, assign, nonatomic) ARTRealtimeChannelState state;
@property (readonly, strong, nonatomic, nullable) ARTErrorInfo *errorReason;
@property (readonly, nullable, getter=getOptions_nosync) ARTRealtimeChannelOptions *options_nosync;

- (ARTRealtimeChannelState)state_nosync;
- (ARTErrorInfo *)errorReason_nosync;
- (NSString *_Nullable)clientId_nosync;

@property (readonly, weak, nonatomic) ARTRealtimeInternal *realtime; // weak because realtime owns self
@property (readonly, strong, nonatomic) ARTRestChannelInternal *restChannel;
@property (readwrite, strong, nonatomic, nullable) NSString *attachSerial;
@property (readonly, nullable, getter=getClientId) NSString *clientId;
@property (readonly, strong, nonatomic) ARTEventEmitter<ARTEvent *, ARTChannelStateChange *> *internalEventEmitter;
@property (readonly, strong, nonatomic) ARTEventEmitter<ARTEvent *, ARTChannelStateChange *> *statesEventEmitter;
@property (readonly, strong, nonatomic) ARTEventEmitter<id<ARTEventIdentification>, ARTMessage *> *messagesEventEmitter;

@property (readonly, strong, nonatomic) ARTEventEmitter<ARTEvent *, ARTPresenceMessage *> *presenceEventEmitter;
@property (readwrite, strong, nonatomic) ARTPresenceMap *presenceMap;
@property (readwrite, assign, nonatomic) BOOL attachResume;

- (instancetype)initWithRealtime:(ARTRealtimeInternal *)realtime andName:(NSString *)name withOptions:(ARTRealtimeChannelOptions *)options;
+ (instancetype)channelWithRealtime:(ARTRealtimeInternal *)realtime andName:(NSString *)name withOptions:(ARTRealtimeChannelOptions *)options;

- (bool)isLastChannelSerial:(NSString *)channelSerial;

- (void)reattachWithReason:(nullable ARTErrorInfo *)reason callback:(nullable void (^)(ARTErrorInfo *))callback;

- (void)_attach:(void (^_Nullable)(ARTErrorInfo * _Nullable))callback;
- (void)_detach:(void (^_Nullable)(ARTErrorInfo * _Nullable))callback;

- (void)_unsubscribe;
- (void)off_nosync;

@property (nonatomic, strong) dispatch_queue_t queue;

@end

@interface ARTRealtimeChannelInternal (Private)

- (void)transition:(ARTRealtimeChannelState)state status:(ARTStatus *)status;

- (void)onChannelMessage:(ARTProtocolMessage *)message;
- (void)publishProtocolMessage:(ARTProtocolMessage *)pm callback:(void (^)(ARTStatus *))cb;

- (void)setAttached:(ARTProtocolMessage *)message;
- (void)setDetached:(ARTProtocolMessage *)message;

- (void)onMessage:(ARTProtocolMessage *)message;
- (void)onPresence:(ARTProtocolMessage *)message;
- (void)onSync:(ARTProtocolMessage *)message;
- (void)onError:(ARTProtocolMessage *)error;

- (void)setSuspended:(ARTStatus *)status;
- (void)setFailed:(ARTStatus *)status;
- (void)throwOnDisconnectedOrFailed;

- (void)broadcastPresence:(ARTPresenceMessage *)pm;
- (void)detachChannel:(ARTStatus *)status;

- (void)sync;
- (void)sync:(nullable void (^)(ARTErrorInfo *_Nullable))callback;
- (void)requestContinueSync;

@end

@interface ARTRealtimeChannel ()

@property (nonatomic, readonly) ARTRealtimeChannelInternal *internal;

- (void)internalAsync:(void (^)(ARTRealtimeChannelInternal *))use;
- (void)internalSync:(void (^)(ARTRealtimeChannelInternal *))use;

- (instancetype)initWithInternal:(ARTRealtimeChannelInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
