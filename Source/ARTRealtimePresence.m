//
//  ARTRealtimePresence.m
//  ably
//
//  Created by Ricardo Pereira on 12/11/15.
//  Copyright © 2015 Ably. All rights reserved.
//

#import "ARTRealtimePresence+Private.h"

#import "ARTRealtime+Private.h"
#import "ARTChannel+Private.h"
#import "ARTRealtimeChannel+Private.h"
#import "ARTPresenceMap.h"
#import "ARTPresenceMessage.h"
#import "ARTStatus.h"
#import "ARTPresence+Private.h"
#import "ARTDataQuery+Private.h"
#import "ARTConnection+Private.h"
#import "ARTNSArray+ARTFunctional.h"

#pragma mark - ARTRealtimePresenceQuery

@implementation ARTRealtimePresenceQuery

- (instancetype)initWithLimit:(NSUInteger)limit clientId:(NSString *)clientId connectionId:(NSString *)connectionId {
    self = [super initWithLimit:limit clientId:clientId connectionId:connectionId];
    if (self) {
        _waitForSync = true;
    }
    return self;
}

@end

@implementation ARTRealtimePresence {
    ARTQueuedDealloc *_dealloc;
}

- (instancetype)initWithInternal:(ARTRealtimePresenceInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc {
    self = [super init];
    if (self) {
        _internal = internal;
        _dealloc = dealloc;
    }
    return self;
}

- (BOOL)syncComplete {
    return _internal.syncComplete;
}

- (void)get:(void (^)(NSArray<ARTPresenceMessage *> *_Nullable result, ARTErrorInfo *_Nullable error))callback {
    [_internal get:callback];
}

- (void)get:(ARTRealtimePresenceQuery *)query callback:(void (^)(NSArray<ARTPresenceMessage *> *_Nullable result, ARTErrorInfo *_Nullable error))callback {
    [_internal get:query callback:callback];
}

- (void)enter:(id _Nullable)data {
    [_internal enter:data];
}

- (void)enter:(id _Nullable)data callback:(nullable void (^)(ARTErrorInfo *_Nullable))cb {
    [_internal enter:data callback:cb];
}

- (void)update:(id _Nullable)data {
    [_internal update:data];
}

- (void)update:(id _Nullable)data callback:(nullable void (^)(ARTErrorInfo *_Nullable))cb {
    [_internal update:data callback:cb];
}

- (void)leave:(id _Nullable)data {
    [_internal leave:data];
}

- (void)leave:(id _Nullable)data callback:(nullable void (^)(ARTErrorInfo *_Nullable))cb {
    [_internal leave:data callback:cb];
}

- (void)enterClient:(NSString *)clientId data:(id _Nullable)data {
    [_internal enterClient:clientId data:data];
}

- (void)enterClient:(NSString *)clientId data:(id _Nullable)data callback:(nullable void (^)(ARTErrorInfo *_Nullable))cb {
    [_internal enterClient:clientId data:data callback:cb];
}

- (void)updateClient:(NSString *)clientId data:(id _Nullable)data {
    [_internal updateClient:clientId data:data];
}

- (void)updateClient:(NSString *)clientId data:(id _Nullable)data callback:(nullable void (^)(ARTErrorInfo *_Nullable))cb {
    [_internal updateClient:clientId data:data callback:cb];
}

- (void)leaveClient:(NSString *)clientId data:(id _Nullable)data {
    [_internal leaveClient:clientId data:data];
}

- (void)leaveClient:(NSString *)clientId data:(id _Nullable)data callback:(nullable void (^)(ARTErrorInfo *_Nullable))cb {
    [_internal leaveClient:clientId data:data callback:cb];
}

- (ARTEventListener *_Nullable)subscribe:(void (^)(ARTPresenceMessage *message))callback {
    return [_internal subscribe:callback];
}

- (ARTEventListener *_Nullable)subscribeWithAttachCallback:(nullable void (^)(ARTErrorInfo *_Nullable))onAttach callback:(void (^)(ARTPresenceMessage *message))cb {
    return [_internal subscribeWithAttachCallback:onAttach callback:cb];
}

- (ARTEventListener *_Nullable)subscribe:(ARTPresenceAction)action callback:(void (^)(ARTPresenceMessage *message))cb {
    return [_internal subscribe:action callback:cb];
}

- (ARTEventListener *_Nullable)subscribe:(ARTPresenceAction)action onAttach:(nullable void (^)(ARTErrorInfo *_Nullable))onAttach callback:(void (^)(ARTPresenceMessage *message))cb {
    return [_internal subscribe:action onAttach:onAttach callback:cb];
}

- (void)unsubscribe {
    [_internal unsubscribe];
}

- (void)unsubscribe:(ARTEventListener *)listener {
    [_internal unsubscribe:listener];
}

- (void)unsubscribe:(ARTPresenceAction)action listener:(ARTEventListener *)listener {
    [_internal unsubscribe:action listener:listener];
}

- (void)history:(void(^)(ARTPaginatedResult<ARTPresenceMessage *> *_Nullable result, ARTErrorInfo *_Nullable error))callback {
    [_internal history:callback];
}

- (BOOL)history:(ARTRealtimeHistoryQuery *_Nullable)query callback:(void(^)(ARTPaginatedResult<ARTPresenceMessage *> *_Nullable result, ARTErrorInfo *_Nullable error))callback error:(NSError *_Nullable *_Nullable)errorPtr {
    return [_internal history:query callback:callback error:errorPtr];
}

@end

#pragma mark - ARTRealtimePresenceInternal

@implementation ARTRealtimePresenceInternal {
    __weak ARTRealtimeChannelInternal *_channel; // weak because channel owns self
    dispatch_queue_t _userQueue;
    NSMutableArray<ARTQueuedMessage *> *_pendingPresence;
}

- (instancetype)initWithChannel:(ARTRealtimeChannelInternal *)channel {
    if (self = [super init]) {
        _channel = channel;
        _userQueue = channel.realtime.rest.userQueue;
        _queue = channel.realtime.rest.queue;
        _pendingPresence = [NSMutableArray array];
        _lastPresenceAction = ARTPresenceAbsent;
    }
    return self;
}

- (void)get:(void (^)(NSArray<ARTPresenceMessage *> *, ARTErrorInfo *))callback {
    [self get:[[ARTRealtimePresenceQuery alloc] init] callback:callback];
}

- (void)get:(ARTRealtimePresenceQuery *)query callback:(void (^)(NSArray<ARTPresenceMessage *> *, ARTErrorInfo *))callback {
    if (callback) {
        void (^userCallback)(NSArray<ARTPresenceMessage *> *, ARTErrorInfo *) = callback;
        callback = ^(NSArray<ARTPresenceMessage *> *m, ARTErrorInfo *e) {
            dispatch_async(self->_userQueue, ^{
                userCallback(m, e);
            });
        };
    }

dispatch_async(_queue, ^{
    switch (self->_channel.state_nosync) {
        case ARTRealtimeChannelDetached:
        case ARTRealtimeChannelFailed:
            if (callback) callback(nil, [ARTErrorInfo createWithCode:90001 message:[NSString stringWithFormat:@"unable to return the list of current members (incompatible channel state: %@)", ARTRealtimeChannelStateToStr(self->_channel.state_nosync)]]);
            return;
        case ARTRealtimeChannelSuspended:
            if (query && !query.waitForSync) {
                if (callback) callback(self->_channel.presenceMap.members.allValues, nil);
                return;
            }
            if (callback) callback(nil, [ARTErrorInfo createWithCode:91005 message:@"presence state is out of sync due to the channel being SUSPENDED"]);
            return;
        default:
            break;
    }

    BOOL (^filterMemberBlock)(ARTPresenceMessage *message) = ^BOOL(ARTPresenceMessage *message) {
        return (query.clientId == nil || [message.clientId isEqualToString:query.clientId]) &&
            (query.connectionId == nil || [message.connectionId isEqualToString:query.connectionId]);
    };

    [self->_channel _attach:^(ARTErrorInfo *error) {
        if (error) {
            callback(nil, error);
            return;
        }
        const BOOL syncInProgress = self->_channel.presenceMap.syncInProgress;
        if (syncInProgress && query.waitForSync) {
            [self->_channel.logger debug:__FILE__ line:__LINE__ message:@"R:%p C:%p (%@) sync is in progress, waiting until the presence members is synchronized", self->_channel.realtime, self->_channel, self->_channel.name];
            [self->_channel.presenceMap onceSyncEnds:^(NSArray<ARTPresenceMessage *> *members) {
                NSArray<ARTPresenceMessage *> *filteredMembers = [members artFilter:filterMemberBlock];
                callback(filteredMembers, nil);
            }];
            [self->_channel.presenceMap onceSyncFails:^(ARTErrorInfo *error) {
                callback(nil, error);
            }];
        } else {
            [self->_channel.logger debug:__FILE__ line:__LINE__ message:@"R:%p C:%p (%@) returning presence members (syncInProgress=%d)", self->_channel.realtime, self->_channel, self->_channel.name, syncInProgress];
            NSArray<ARTPresenceMessage *> *members = self->_channel.presenceMap.members.allValues;
            NSArray<ARTPresenceMessage *> *filteredMembers = [members artFilter:filterMemberBlock];
            callback(filteredMembers, nil);
        }
    }];
});
}

- (void)history:(void (^)(ARTPaginatedResult<ARTPresenceMessage *> *, ARTErrorInfo *))callback {
    [self history:[[ARTRealtimeHistoryQuery alloc] init] callback:callback error:nil];
}

- (BOOL)history:(ARTRealtimeHistoryQuery *)query callback:(void (^)(ARTPaginatedResult<ARTPresenceMessage *> *, ARTErrorInfo *))callback error:(NSError **)errorPtr {
    query.realtimeChannel = _channel;
    @try {
        return [_channel.restChannel.presence history:query callback:callback error:errorPtr];
    }
    @catch (NSError *error) {
        if (errorPtr) {
            *errorPtr = error;
        }
        return false;
    }
}

- (void)enter:(id)data {
    [self enter:data callback:nil];
}

- (void)enter:(id)data callback:(void (^)(ARTErrorInfo *))cb {
    if (cb) {
        void (^userCallback)(ARTErrorInfo *_Nullable error) = cb;
        cb = ^(ARTErrorInfo *_Nullable error) {
            dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }

dispatch_async(_queue, ^{
    [self enterOrUpdateAfterChecks:ARTPresenceEnter clientId:nil data:data callback:cb];
});
}

- (void)enterClient:(NSString *)clientId data:(id)data {
    [self enterClient:clientId data:data callback:nil];
}

- (void)enterClient:(NSString *)clientId data:(id)data callback:(void (^)(ARTErrorInfo *))cb {
    if (cb) {
        void (^userCallback)(ARTErrorInfo *_Nullable error) = cb;
        cb = ^(ARTErrorInfo *_Nullable error) {
            dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }

dispatch_async(_queue, ^{
    [self enterOrUpdateAfterChecks:ARTPresenceEnter clientId:clientId data:data callback:cb];
});
}

- (void)update:(id)data {
    [self update:data callback:nil];
}

- (void)update:(id)data callback:(void (^)(ARTErrorInfo * _Nullable))cb {
    if (cb) {
        void (^userCallback)(ARTErrorInfo *_Nullable error) = cb;
        cb = ^(ARTErrorInfo *_Nullable error) {
            dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }

dispatch_async(_queue, ^{
    [self enterOrUpdateAfterChecks:ARTPresenceUpdate clientId:nil data:data callback:cb];
});
}

- (void)updateClient:(NSString *)clientId data:(id)data {
    [self updateClient:clientId data:data callback:nil];
}

- (void)updateClient:(NSString *)clientId data:(id)data callback:(void (^)(ARTErrorInfo * _Nullable))cb {
    if (cb) {
        void (^userCallback)(ARTErrorInfo *_Nullable error) = cb;
        cb = ^(ARTErrorInfo *_Nullable error) {
            dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }

dispatch_async(_queue, ^{
    [self enterOrUpdateAfterChecks:ARTPresenceUpdate clientId:clientId data:data callback:cb];
});
}

- (void)enterOrUpdateAfterChecks:(ARTPresenceAction)action clientId:(NSString *_Nullable)clientId data:(id)data callback:(void (^)(ARTErrorInfo *))cb {
    switch (_channel.state_nosync) {
        case ARTRealtimeChannelDetached:
        case ARTRealtimeChannelFailed: {
            if (cb) {
                ARTErrorInfo *channelError = [ARTErrorInfo createWithCode:90001 message:[NSString stringWithFormat:@"unable to enter presence channel (incompatible channel state: %@)", ARTRealtimeChannelStateToStr(_channel.state_nosync)]];
                cb(channelError);
            }
            return;
        }
        default:
            break;
    }

    ARTPresenceMessage *msg = [[ARTPresenceMessage alloc] init];
    msg.action = action;
    msg.clientId = clientId;
    msg.data = data;
    msg.connectionId = _channel.realtime.connection.id_nosync;

    [self publishPresence:msg callback:cb];
}

- (void)leave:(id)data {
    [self leave:data callback:nil];
}

- (void)leave:(id)data callback:(void (^)(ARTErrorInfo * _Nullable))cb {
    if (cb) {
        void (^userCallback)(ARTErrorInfo *_Nullable error) = cb;
        cb = ^(ARTErrorInfo *_Nullable error) {
            dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }

    __block ARTException *exception = nil;
dispatch_sync(_queue, ^{
@try {
    [self leaveAfterChecks:nil data:data callback:cb];
} @catch (ARTException *e) {
    exception = e;
}
});
    if (exception) {
        @throw exception;
    }
}

- (void)leaveClient:(NSString *)clientId data:(id)data {
    [self leaveClient:clientId data:data callback:nil];
}

- (void)leaveClient:(NSString *)clientId data:(id)data callback:(void (^)(ARTErrorInfo * _Nullable))cb {
    if (cb) {
        void (^userCallback)(ARTErrorInfo *_Nullable error) = cb;
        cb = ^(ARTErrorInfo *_Nullable error) {
            dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }

dispatch_sync(_queue, ^{
    [self leaveAfterChecks:clientId data:data callback:cb];
});
}

- (void)leaveAfterChecks:(NSString *_Nullable)clientId data:(id)data callback:(void (^)(ARTErrorInfo *))cb {
    ARTPresenceMessage *msg = [[ARTPresenceMessage alloc] init];
    msg.action = ARTPresenceLeave;
    msg.data = data;
    msg.clientId = clientId;
    msg.connectionId = _channel.realtime.connection.id_nosync;
    [self publishPresence:msg callback:cb];
}

- (BOOL)syncComplete {
    __block BOOL ret;
dispatch_sync(_queue, ^{
    ret = [self syncComplete_nosync];
});
    return ret;
}

- (BOOL)syncComplete_nosync {
    return _channel.presenceMap.syncComplete;
}

- (ARTEventListener *)subscribe:(void (^)(ARTPresenceMessage * _Nonnull))callback {
    return [self subscribeWithAttachCallback:nil callback:callback];
}

- (ARTEventListener *)subscribeWithAttachCallback:(void (^)(ARTErrorInfo * _Nullable))onAttach callback:(void (^)(ARTPresenceMessage * _Nonnull))cb {
    if (cb) {
        void (^userCallback)(ARTPresenceMessage *_Nullable m) = cb;
        cb = ^(ARTPresenceMessage *_Nullable m) {
            dispatch_async(self->_userQueue, ^{
                userCallback(m);
            });
        };
    }
    if (onAttach) {
        void (^userOnAttach)(ARTErrorInfo *_Nullable m) = onAttach;
        onAttach = ^(ARTErrorInfo *_Nullable m) {
            dispatch_async(self->_userQueue, ^{
                userOnAttach(m);
            });
        };
    }

    __block ARTEventListener *listener = nil;
dispatch_sync(_queue, ^{
    if (self->_channel.state_nosync == ARTRealtimeChannelFailed) {
        if (onAttach) onAttach([ARTErrorInfo createWithCode:90001 message:@"attempted to subscribe while channel is in Failed state."]);
        return;
    }
    [self->_channel _attach:onAttach];
    listener = [self->_channel.presenceEventEmitter on:cb];
    [self->_channel.logger verbose:@"R:%p C:%p (%@) presence subscribe to all actions", self->_channel.realtime, self->_channel, self->_channel.name];
});
    return listener;
}

- (ARTEventListener *)subscribe:(ARTPresenceAction)action callback:(void (^)(ARTPresenceMessage * _Nonnull))cb {
    return [self subscribe:action onAttach:nil callback:cb];
}

- (ARTEventListener *)subscribe:(ARTPresenceAction)action onAttach:(void (^)(ARTErrorInfo * _Nullable))onAttach callback:(void (^)(ARTPresenceMessage * _Nonnull))cb {
    if (cb) {
        void (^userCallback)(ARTPresenceMessage *_Nullable m) = cb;
        cb = ^(ARTPresenceMessage *_Nullable m) {
            dispatch_async(self->_userQueue, ^{
                userCallback(m);
            });
        };
    }
    if (onAttach) {
        void (^userOnAttach)(ARTErrorInfo *_Nullable m) = onAttach;
        onAttach = ^(ARTErrorInfo *_Nullable m) {
            dispatch_async(self->_userQueue, ^{
                userOnAttach(m);
            });
        };
    }

    __block ARTEventListener *listener = nil;
dispatch_sync(_queue, ^{
    if (self->_channel.state_nosync == ARTRealtimeChannelFailed) {
        if (onAttach) onAttach([ARTErrorInfo createWithCode:90001 message:@"attempted to subscribe while channel is in Failed state."]);
        return;
    }
    [self->_channel _attach:onAttach];
    listener = [self->_channel.presenceEventEmitter on:[ARTEvent newWithPresenceAction:action] callback:cb];
    [self->_channel.logger verbose:@"R:%p C:%p (%@) presence subscribe to action %@", self->_channel.realtime, self->_channel, self->_channel.name, ARTPresenceActionToStr(action)];
});
    return listener;
}

- (void)unsubscribe {
dispatch_sync(_queue, ^{
    [self _unsubscribe];
    [self->_channel.logger verbose:@"R:%p C:%p (%@) presence unsubscribe to all actions", self->_channel.realtime, self->_channel, self->_channel.name];
});
}

- (void)_unsubscribe {
    [_channel.presenceEventEmitter off];
}

- (void)unsubscribe:(ARTEventListener *)listener {
dispatch_sync(_queue, ^{
    [self->_channel.presenceEventEmitter off:listener];
    [self->_channel.logger verbose:@"R:%p C:%p (%@) presence unsubscribe to all actions", self->_channel.realtime, self->_channel, self->_channel.name];
});
}

- (void)unsubscribe:(ARTPresenceAction)action listener:(ARTEventListener *)listener {
dispatch_sync(_queue, ^{
    [self->_channel.presenceEventEmitter off:[ARTEvent newWithPresenceAction:action] listener:listener];
    [self->_channel.logger verbose:@"R:%p C:%p (%@) presence unsubscribe to action %@", self->_channel.realtime, self->_channel, self->_channel.name, ARTPresenceActionToStr(action)];
});
}

- (void)addPendingPresence:(ARTProtocolMessage *)msg callback:(void (^)(ARTStatus *))cb {
    ARTQueuedMessage *qm = [[ARTQueuedMessage alloc] initWithProtocolMessage:msg sentCallback:nil ackCallback:cb];
    [_pendingPresence addObject:qm];
}

- (void)publishPresence:(ARTPresenceMessage *)msg callback:(void (^)(ARTErrorInfo *))callback {
    if (!msg.clientId && !_channel.realtime.auth.clientId_nosync) {
        if (callback) callback([ARTErrorInfo createWithCode:ARTStateNoClientId message:@"attempted to publish presence message without clientId"]);
        return;
    }

    if (!_channel.realtime.connection.isActive_nosync) {
        if (callback) callback([_channel.realtime.connection error_nosync]);
        return;
    }

    if ([_channel exceedMaxSize:@[msg]]) {
        if (callback) {
            ARTErrorInfo *sizeError = [ARTErrorInfo createWithCode:40009
                                                           message:@"maximum message length exceeded"];
            callback(sizeError);
        }
        return;
    }

    _lastPresenceAction = msg.action;

    if (msg.data && _channel.dataEncoder) {
        ARTDataEncoderOutput *encoded = [_channel.dataEncoder encode:msg.data];
        if (encoded.errorInfo) {
            [_channel.logger warn:@"RT:%p C:%p (%@) error encoding presence message: %@", _channel.realtime, self, _channel.name, encoded.errorInfo];
        }
        msg.data = encoded.data;
        msg.encoding = encoded.encoding;
    }

    ARTProtocolMessage *pm = [[ARTProtocolMessage alloc] init];
    pm.action = ARTProtocolMessagePresence;
    pm.channel = _channel.name;
    pm.presence = @[msg];

    ARTRealtimeChannelState channelState = _channel.state_nosync;
    switch (channelState) {
        case ARTRealtimeChannelInitialized:
        case ARTRealtimeChannelDetached:
            [_channel _attach:nil];
        case ARTRealtimeChannelAttaching: {
            [self addPendingPresence:pm callback:^(ARTStatus *status) {
                if (callback) {
                    callback(status.errorInfo);
                }
            }];
            break;
        }
        case ARTRealtimeChannelAttached: {
            [_channel.realtime send:pm sentCallback:nil ackCallback:^(ARTStatus *status) {
                if (callback) callback(status.errorInfo);
            }];
            break;
        }
        case ARTRealtimeChannelSuspended:
        case ARTRealtimeChannelDetaching:
        case ARTRealtimeChannelFailed: {
            if (callback) {
                ARTErrorInfo *invalidChannelError = [ARTErrorInfo createWithCode:90001 message:[NSString stringWithFormat:@"channel operation failed (invalid channel state: %@)", ARTRealtimeChannelStateToStr(channelState)]];
                callback(invalidChannelError);
            }
            break;
        }
    }
}

- (NSMutableArray<ARTQueuedMessage *> *)pendingPresence {
    __block NSMutableArray<ARTQueuedMessage *> *ret;
dispatch_sync(_queue, ^{
    ret = _pendingPresence;
});
    return ret;
}

- (void)sendPendingPresence {
    NSArray *pendingPresence = _pendingPresence;
    ARTRealtimeChannelState channelState = _channel.state_nosync;
    _pendingPresence = [NSMutableArray array];
    for (ARTQueuedMessage *qm in pendingPresence) {
        if (qm.msg.action == ARTProtocolMessagePresence &&
            channelState != ARTRealtimeChannelAttached) {
            // Presence messages should only be sent when the channel is attached.
            [_pendingPresence addObject:qm];
            continue;
        }
        [_channel.realtime send:qm.msg sentCallback:nil ackCallback:qm.ackCallback];
    }
}

- (void)failPendingPresence:(ARTStatus *)status {
    NSArray *pendingPresence = _pendingPresence;
    _pendingPresence = [NSMutableArray array];
    for (ARTQueuedMessage *qm in pendingPresence) {
        qm.ackCallback(status);
    }
}

@end
