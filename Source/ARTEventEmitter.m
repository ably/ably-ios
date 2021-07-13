//
//  ARTEventEmitter.m
//  ably
//
//  Created by Ricardo Pereira on 30/09/2015.
//  Copyright (c) 2015 Ably. All rights reserved.
//

#import "ARTEventEmitter+Private.h"

#import "ARTRealtime.h"
#import "ARTRealtime+Private.h"
#import "ARTRealtimeChannel.h"
#import "ARTGCD.h"

@implementation NSMutableArray (AsSet)

- (void)artRemoveWhere:(BOOL (^)(id))cond {
    NSUInteger l = [self count];
    for (NSInteger i = 0; i < l; i++) {
        if (cond([self objectAtIndex:i])) {
            [self removeObjectAtIndex:i];
            i--;
            l--;
        }
    }
}

@end

#pragma mark - ARTEvent

@implementation ARTEvent {
    NSString *_value;
}

- (instancetype)initWithString:(NSString *)value {
    if (self = [super init]) {
        _value = value;
    }
    return self;
}

+ (instancetype)newWithString:(NSString *)value {
    return [[self alloc] initWithString:value];
}

- (NSString *)identification {
    return _value;
}

@end

#pragma mark - ARTEventListener

@interface ARTEventListener ()
@property (readonly) BOOL invalidated;
@property (readonly) BOOL timerIsRunning;
@property (readonly) BOOL hasTimer;
@end

@implementation ARTEventListener {
    NSNotificationCenter *_center;
    __weak ARTEventEmitter *_eventHandler; // weak because eventEmitter owns self
    NSTimeInterval _timeoutDeadline;
    void (^_timeoutBlock)(void);
    ARTScheduledBlockHandle *_work;
}

- (instancetype)initWithId:(NSString *)eventId token:(id<NSObject>)token handler:(ARTEventEmitter *)eventHandler center:(NSNotificationCenter *)center {
    if (self = [super init]) {
        _eventId = eventId;
        _token = token;
        _center = center;
        _eventHandler = eventHandler;
        _timeoutDeadline = 0;
        _timeoutBlock = nil;
        _timerIsRunning = false;
        _invalidated = false;
    }
    return self;
}

- (void)dealloc {
    [self invalidate];
    [_center removeObserver:_token];
}

- (void)removeObserver {
    if (!_token) {
        return;
    }
    [self invalidate];
    if (_eventHandler && _eventHandler.userQueue) {
        dispatch_async(_eventHandler.userQueue, ^{
            [self->_center removeObserver:self->_token];
            self->_token = nil;
        });
    }
    else {
        [_center removeObserver:_token];
        _token = nil;
    }
}

- (BOOL)handled {
    return _count++ > 0;
}

- (void)invalidate {
    _invalidated = true;
    [self stopTimer];
}

- (ARTEventListener *)setTimer:(NSTimeInterval)timeoutDeadline onTimeout:(void (^)(void))timeoutBlock {
    if (_timeoutBlock) {
        NSAssert(false, @"timer is already set");
    }
    _timeoutBlock = timeoutBlock;
    _timeoutDeadline = timeoutDeadline;
    return self;
}

- (void)timeout {
    dispatch_block_t timeoutBlock = _timeoutBlock;
    [_eventHandler off:self]; // removes self as a listener, which clears _timeoutBlock.
    if (timeoutBlock) {
        timeoutBlock();
    }
}

- (BOOL)hasTimer {
    return _timeoutBlock != nil;
}

- (void)startTimer {
    if (_timerIsRunning) {
        NSAssert(false, @"timer is already running");
    }
    _timerIsRunning = true;
    
    __weak ARTEventListener *weakSelf = self;
    _work = artDispatchScheduled(_timeoutDeadline, [_eventHandler queue], ^{
        [weakSelf timeout];
    });
}

- (void)stopTimer {
    artDispatchCancel(_work);
    _timerIsRunning = false;
    _timeoutBlock = nil;
    _work = nil;
}

- (void)restartTimer {
    artDispatchCancel(_work);
    _timerIsRunning = false;
    [self startTimer];
}

@end

#pragma mark - ARTEventEmitter

@implementation ARTEventEmitter

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [self initWithQueues:queue userQueue:nil];
    return self;
}

- (instancetype)initWithQueues:(dispatch_queue_t)queue userQueue:(dispatch_queue_t)userQueue {
    self = [super init];
    if (self) {
        _notificationCenter = [[NSNotificationCenter alloc] init];
        _queue = queue;
        _userQueue = userQueue;
        [self resetListeners];
    }
    return self;
}

- (ARTEventListener *)on:(id<ARTEventIdentification>)event callback:(void (^)(id __art_nonnull))cb {
    NSString *eventId = [NSString stringWithFormat:@"%p-%@", self, [event identification]];
    __block ARTEventListener *listener;
    id<NSObject> observerToken = [_notificationCenter addObserverForName:eventId object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        if (listener == nil || [listener invalidated]) return;
        if ([listener hasTimer] && ![listener timerIsRunning]) return;
        [listener stopTimer];
        cb(note.object);
    }];
    listener = [[ARTEventListener alloc] initWithId:eventId token:observerToken handler:self center:_notificationCenter];
    [self addObject:listener toArrayWithKey:listener.eventId inDictionary:self.listeners];
    return listener;
}

- (ARTEventListener *)once:(id<ARTEventIdentification>)event callback:(void (^)(id __art_nonnull))cb {
    NSString *eventId = [NSString stringWithFormat:@"%p-%@", self, [event identification]];
    __block ARTEventListener *listener;
    __weak typeof(self) weakSelf = self; // weak to avoid a warning, but strong should be safe too since the cycle is broken when the notification fires or the token is cancelled
    id<NSObject> observerToken = [_notificationCenter addObserverForName:eventId object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        if (listener == nil || [listener invalidated]) return;
        if ([listener hasTimer] && ![listener timerIsRunning]) return;
        if ([listener handled]) return;
        [listener removeObserver];
        [weakSelf removeObject:listener fromArrayWithKey:[listener eventId] inDictionary:[weakSelf listeners]];
        cb(note.object);
    }];
    listener = [[ARTEventListener alloc] initWithId:eventId token:observerToken handler:self center:_notificationCenter];
    [self addObject:listener toArrayWithKey:listener.eventId inDictionary:self.listeners];
    return listener;
}

- (ARTEventListener *)on:(void (^)(id __art_nonnull))cb {
    NSString *eventId = [NSString stringWithFormat:@"%p", self];
    __block ARTEventListener *listener;
    id<NSObject> observerToken = [_notificationCenter addObserverForName:eventId object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        if (listener == nil || [listener invalidated]) return;
        if ([listener hasTimer] && ![listener timerIsRunning]) return;
        [listener stopTimer];
        cb(note.object);
    }];
    listener = [[ARTEventListener alloc] initWithId:eventId token:observerToken handler:self center:_notificationCenter];
    [self.anyListeners addObject:listener];
    return listener;
}

- (ARTEventListener *)once:(void (^)(id __art_nonnull))cb {
    NSString *eventId = [NSString stringWithFormat:@"%p", self];
    __block ARTEventListener *listener;
    __weak typeof(self) weakSelf = self; // weak to avoid a warning, but strong should be safe too since the cycle is broken when the notification fires or the token is cancelled
    id<NSObject> observerToken = [_notificationCenter addObserverForName:eventId object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        if (listener == nil || [listener invalidated]) return;
        if ([listener hasTimer] && ![listener timerIsRunning]) return;
        if ([listener handled]) return;
        [listener removeObserver];
        [[weakSelf anyListeners] removeObject:listener];
        cb(note.object);
    }];
    listener = [[ARTEventListener alloc] initWithId:eventId token:observerToken handler:self center:_notificationCenter];
    [self.anyListeners addObject:listener];
    return listener;
}

- (void)off:(id<ARTEventIdentification>)event listener:(ARTEventListener *)listener {
    NSString *eventId = [NSString stringWithFormat:@"%p-%@", self, [event identification]];
    if (![eventId isEqualToString:listener.eventId]) return;
    [listener removeObserver];
    [self.listeners[listener.eventId] removeObject:listener];
    if ([self.listeners[listener.eventId] firstObject] == nil) {
        [self.listeners removeObjectForKey:listener.eventId];
    }
}

- (void)off:(ARTEventListener *)listener {
    [listener removeObserver];
    [self.listeners[listener.eventId] removeObject:listener];
    [self.anyListeners removeObject:listener];
}

- (void)off {
    [self resetListeners];
}

- (void)resetListeners {
    for (NSArray<ARTEventListener *> *items in [_listeners allValues]) {
        for (ARTEventListener *item in items) {
            [item removeObserver];
        }
    }
    [_listeners removeAllObjects];
    _listeners = [[NSMutableDictionary alloc] init];

    for (ARTEventListener *item in _anyListeners) {
        [item removeObserver];
    }
    [_anyListeners removeAllObjects];
    _anyListeners = [[NSMutableArray alloc] init];
}

- (void)emit:(id<ARTEventIdentification>)event with:(id)data {
    if (event) {
        [self.notificationCenter postNotificationName:[NSString stringWithFormat:@"%p-%@", self, [event identification]] object:data];
    }
    [self.notificationCenter postNotificationName:[NSString stringWithFormat:@"%p", self] object:data];
}

- (void)addObject:(id)obj toArrayWithKey:(id)key inDictionary:(NSMutableDictionary *)dict {
    NSMutableArray *array = [dict objectForKey:key];
    if (array == nil) {
        array = [[NSMutableArray alloc] init];
        [dict setObject:array forKey:key];
    }
    if ([array indexOfObject:obj] == NSNotFound) {
        [array addObject:obj];
    }
}

- (void)removeObject:(id)obj fromArrayWithKey:(id)key inDictionary:(NSMutableDictionary *)dict {
    NSMutableArray *array = [dict objectForKey:key];
    if (array == nil) {
        return;
    }
    [array removeObject:obj];
    if ([array count] == 0) {
        [dict removeObjectForKey:key];
    }
}

- (void)removeObject:(id)obj fromArrayWithKey:(id)key inDictionary:(NSMutableDictionary *)dict where:(BOOL(^)(id))cond {
    NSMutableArray *array = [dict objectForKey:key];
    if (array == nil) {
        return;
    }
    [array artRemoveWhere:cond];
    if ([array count] == 0) {
        [dict removeObjectForKey:key];
    }
}

@end

@implementation ARTPublicEventEmitter {
    __weak ARTRestInternal *_rest; // weak because rest owns self
    dispatch_queue_t _queue;
    dispatch_queue_t _userQueue;
}

- (instancetype)initWithRest:(ARTRestInternal *)rest {
    if (self = [super initWithQueue:rest.queue]) {
        _rest = rest;
        _queue = rest.queue;
        _userQueue = rest.userQueue;

        if (rest.logger.logLevel == ARTLogLevelVerbose) {
            [self.notificationCenter addObserverForName:nil
                                                 object:nil
                                                  queue:nil
                                             usingBlock:^(NSNotification *notification) {
                                                 NSLog(@"VERBOSE: PublicEventEmitter Notification emitted %@", notification.name);
                                             }];
        }
    }
    return self;
}

- (void)dealloc {
    [self.notificationCenter removeObserver:self];
}

- (ARTEventListener *)on:(id)event callback:(void (^)(id _Nullable))cb {
    if (cb) {
        void (^userCallback)(id _Nullable) = cb;
        cb = ^(id _Nullable v) {
            dispatch_async(self->_userQueue, ^{
                userCallback(v);
            });
        };
    }
    
    __block ARTEventListener *listener;
dispatch_sync(_queue, ^{
    listener = [super on:event callback:cb];
});
    return listener;
}

- (ARTEventListener *)on:(void (^)(id _Nullable))cb {
    if (cb) {
        void (^userCallback)(id _Nullable) = cb;
        cb = ^(id _Nullable v) {
            dispatch_async(self->_userQueue, ^{
                userCallback(v);
            });
        };
    }
    
    __block ARTEventListener *listener;
dispatch_sync(_queue, ^{
    listener = [super on:cb];
});
    return listener;
}

- (ARTEventListener *)once:(id)event callback:(void (^)(id _Nullable))cb {
    if (cb) {
        void (^userCallback)(id _Nullable) = cb;
        cb = ^(id _Nullable v) {
            dispatch_async(self->_userQueue, ^{
                userCallback(v);
            });
        };
    }

    __block ARTEventListener *listener;
dispatch_sync(_queue, ^{
    listener = [super once:event callback:cb];
});
    return listener;
}

- (ARTEventListener *)once:(void (^)(id _Nullable))cb {
    if (cb) {
        void (^userCallback)(id _Nullable) = cb;
        cb = ^(id _Nullable v) {
            dispatch_async(self->_userQueue, ^{
                userCallback(v);
            });
        };
    }

    __block ARTEventListener *listener;
dispatch_sync(_queue, ^{
    listener = [super once:cb];
});
    return listener;
}

- (void)off:(id<ARTEventIdentification>)event listener:(ARTEventListener *)listener {
dispatch_sync(_queue, ^{
    [super off:event listener:listener];
});
}

- (void)off:(ARTEventListener *)listener {
dispatch_sync(_queue, ^{
    [super off:listener];
});
}

- (void)off {
dispatch_sync(_queue, ^{
    [super off];
});
}

- (void)off_nosync {
    [super off];
}

@end

@implementation ARTInternalEventEmitter

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
   return [super initWithQueue:queue];
}

- (instancetype)initWithQueues:(dispatch_queue_t)queue userQueue:(dispatch_queue_t)userQueue {
    return [super initWithQueues:queue userQueue:userQueue];
}

@end
