//
//  ARTWebSocket.h
//  Ably
//
//  Copyright © 2019 Ably. All rights reserved.
//

#ifndef ARTWebSocket_h
#define ARTWebSocket_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ARTWebSocketDelegate;

/**
 This protocol has the subset of ARTSRWebSocket we actually use.
 */
@protocol ARTWebSocket <NSObject>

@property (nonatomic, weak) id <ARTWebSocketDelegate> _Nullable delegate;
@property (nullable, nonatomic, strong) dispatch_queue_t delegateDispatchQueue;
@property (atomic, assign, readonly) ARTSRReadyState readyState;

- (instancetype)initWithURLRequest:(NSURLRequest *)request;

- (void)setDelegateDispatchQueue:(dispatch_queue_t)queue;

- (void)open;
- (void)closeWithCode:(NSInteger)code reason:(nullable NSString *)reason;
- (void)send:(nullable id)message;

@end

@protocol ARTWebSocketDelegate <NSObject>

- (void)webSocketDidOpen:(id<ARTWebSocket>)websocket;
- (void)webSocket:(id<ARTWebSocket>)webSocket didCloseWithCode:(NSInteger)code reason:(NSString * _Nullable)reason wasClean:(BOOL)wasClean;
- (void)webSocket:(id<ARTWebSocket>)webSocket didFailWithError:(NSError *)error;
- (void)webSocket:(id<ARTWebSocket>)webSocket didReceiveMessage:(id)message;

@end

NS_ASSUME_NONNULL_END

#endif /* ARTWebSocket_h */
