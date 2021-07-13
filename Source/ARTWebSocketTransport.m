//
//  ARTWebSocketTransport.m
//
//  Created by Jason Choy on 10/12/2014.
//  Copyright (c) 2014 Ably. All rights reserved.
//

#import "ARTWebSocketTransport+Private.h"

#import "ARTRest.h"
#import "ARTRest+Private.h"
#import "ARTProtocolMessage.h"
#import "ARTClientOptions.h"
#import "ARTTokenParams.h"
#import "ARTTokenDetails.h"
#import "ARTStatus.h"
#import "ARTEncoder.h"
#import "ARTDefault.h"
#import "ARTRealtimeTransport.h"
#import "ARTGCD.h"
#import "ARTLog+Private.h"
#import "ARTEventEmitter+Private.h"

enum {
    ARTWsNeverConnected = -1,
    ARTWsBuggyClose = -2,
    ARTWsCloseNormal = 1000,
    ARTWsGoingAway = 1001,
    ARTWsCloseProtocolError = 1002,
    ARTWsRefuse = 1003,
    ARTWsNoUtf8 = 1007,
    ARTWsPolicyValidation = 1008,
    ARTWsTooBig = 1009,
    ARTWsExtension = 1010,
    ARTWsUnexpectedCondition = 1011,
    ARTWsTlsError = 1015
};

NSString *WebSocketStateToStr(ARTSRReadyState state);

@interface ARTSRWebSocket () <ARTWebSocket>
@end

Class configuredWebsocketClass = nil;

@implementation ARTWebSocketTransport {
    id<ARTRealtimeTransportDelegate> _delegate;
    ARTRealtimeTransportState _state;
    /**
      The dispatch queue for firing the events. Must be the same for the whole library.
     */
    _Nonnull dispatch_queue_t _workQueue;
}

@synthesize delegate = _delegate;
@synthesize stateEmitter = _stateEmitter;

+ (void)setWebSocketClass:(const Class)webSocketClass {
    configuredWebsocketClass = webSocketClass;
}

- (instancetype)initWithRest:(ARTRestInternal *)rest options:(ARTClientOptions *)options resumeKey:(NSString *)resumeKey connectionSerial:(NSNumber *)connectionSerial {
    self = [super init];
    if (self) {
        _workQueue = rest.queue;
        _websocket = nil;
        _state = ARTRealtimeTransportStateClosed;
        _encoder = rest.defaultEncoder;
        _logger = rest.logger;
        _protocolMessagesLogger = [[ARTLog alloc] initCapturingOutput:false historyLines:50];
        _options = [options copy];
        _resumeKey = resumeKey;
        _connectionSerial = connectionSerial;
        _stateEmitter = [[ARTInternalEventEmitter alloc] initWithQueue:_workQueue];

        [self.logger verbose:__FILE__ line:__LINE__ message:@"R:%p WS:%p alloc", _delegate, self];
    }
    return self;
}

- (void)dealloc {
    [self.logger verbose:__FILE__ line:__LINE__ message:@"R:%p WS:%p dealloc", _delegate, self];
    self.websocket.delegate = nil;
    self.websocket = nil;
    self.delegate = nil;
}

- (BOOL)send:(NSData *)data withSource:(id)decodedObject {
    if (self.websocket.readyState == ARTSR_OPEN) {
        if ([decodedObject isKindOfClass:[ARTProtocolMessage class]]) {
            [_protocolMessagesLogger info:@"send %@", [decodedObject description]];
        }
        [self.websocket send:data];
        return true;
    }
    else {
        NSString *extraInformation = @"";
        if ([decodedObject isKindOfClass:[ARTProtocolMessage class]]) {
            ARTProtocolMessage *msg = (ARTProtocolMessage *)decodedObject;
            extraInformation = [NSString stringWithFormat:@"with action \"%tu - %@\" ", msg.action, ARTProtocolMessageActionToStr(msg.action)];
        }
        [self.logger debug:__FILE__ line:__LINE__ message:@"R:%p WS:%p sending message %@was ignored because websocket isn't ready", _delegate, self, extraInformation];
        return false;
    }
}

- (void)internalSend:(ARTProtocolMessage *)msg {
    [self.logger debug:__FILE__ line:__LINE__ message:@"R:%p WS:%p websocket sending action %tu - %@", _delegate, self, msg.action, ARTProtocolMessageActionToStr(msg.action)];
    [_protocolMessagesLogger info:@"send %@", [msg description]];
    NSData *data = [self.encoder encodeProtocolMessage:msg error:nil];
    [self send:data withSource:msg];
}

- (void)receive:(ARTProtocolMessage *)msg {
    [_protocolMessagesLogger info:@"recv %@", [msg description]];
    [self.delegate realtimeTransport:self didReceiveMessage:msg];
}

- (ARTProtocolMessage *)receiveWithData:(NSData *)data {
    ARTProtocolMessage *pm = [self.encoder decodeProtocolMessage:data error:nil];
    [self receive:pm];
    return pm;
}

- (void)connectWithKey:(NSString *)key {
    _state = ARTRealtimeTransportStateOpening;
    [self.logger debug:__FILE__ line:__LINE__ message:@"R:%p WS:%p websocket connect with key", _delegate, self];
    NSURLQueryItem *keyParam = [NSURLQueryItem queryItemWithName:@"key" value:key];
    [self setupWebSocket:@[keyParam] withOptions:self.options resumeKey:self.resumeKey connectionSerial:self.connectionSerial];
    // Connect
    [self.websocket open];
}

- (void)connectWithToken:(NSString *)token {
    _state = ARTRealtimeTransportStateOpening;
    [self.logger debug:__FILE__ line:__LINE__ message:@"R:%p WS:%p websocket connect with token", _delegate, self];
    NSURLQueryItem *accessTokenParam = [NSURLQueryItem queryItemWithName:@"accessToken" value:token];
    [self setupWebSocket:@[accessTokenParam] withOptions:self.options resumeKey:self.resumeKey connectionSerial:self.connectionSerial];
    // Connect
    [self.websocket open];
}

- (NSURL *)setupWebSocket:(__GENERIC(NSArray, NSURLQueryItem *) *)params withOptions:(ARTClientOptions *)options resumeKey:(NSString *)resumeKey connectionSerial:(NSNumber *)connectionSerial {
    NSArray *queryItems = params;

    // ClientID
    if (options.clientId) {
        NSURLQueryItem *clientIdParam = [NSURLQueryItem queryItemWithName:@"clientId" value:options.clientId];
        queryItems = [queryItems arrayByAddingObject:clientIdParam];
    }

    // Echo
    NSURLQueryItem *echoParam = [NSURLQueryItem queryItemWithName:@"echo" value:options.echoMessages ? @"true" : @"false"];
    queryItems = [queryItems arrayByAddingObject:echoParam];

    // Format: MsgPack, JSON
    NSURLQueryItem *formatParam = [NSURLQueryItem queryItemWithName:@"format" value:[_encoder formatAsString]];
    queryItems = [queryItems arrayByAddingObject:formatParam];

    if (options.recover) {
        NSArray *recoverParts = [options.recover componentsSeparatedByString:@":"];
        if (recoverParts.count > 1 && recoverParts.count <= 3) {
            NSString *key = [recoverParts objectAtIndex:0];
            NSString *serial = [recoverParts objectAtIndex:1];
            [self.logger info:@"R:%p WS:%p ARTWebSocketTransport: attempting recovery of connection %@", _delegate, self, key];

            NSURLQueryItem *recoverParam = [NSURLQueryItem queryItemWithName:@"recover" value:key];
            queryItems = [queryItems arrayByAddingObject:recoverParam];

            NSURLQueryItem *connectionSerialParam = [NSURLQueryItem queryItemWithName:@"connectionSerial" value:serial];
            queryItems = [queryItems arrayByAddingObject:connectionSerialParam];

            int64_t msgSerial = [[recoverParts lastObject] longLongValue];
            if (msgSerial) {
                [_delegate realtimeTransportSetMsgSerial:self msgSerial:msgSerial];
            }
        }
        else {
            [self.logger error:@"R:%p WS:%p ARTWebSocketTransport: recovery string is malformed, ignoring: '%@'", _delegate, self, options.recover];
        }
    }
    else if (resumeKey != nil && connectionSerial != nil) {
        NSURLQueryItem *resumeKeyParam = [NSURLQueryItem queryItemWithName:@"resume" value:resumeKey];
        queryItems = [queryItems arrayByAddingObject:resumeKeyParam];

        NSURLQueryItem *connectionSerialParam = [NSURLQueryItem queryItemWithName:@"connectionSerial" value:[NSString stringWithFormat:@"%lld", (long long)[connectionSerial integerValue]]];
        queryItems = [queryItems arrayByAddingObject:connectionSerialParam];
    }

    NSURLQueryItem *versionParam = [NSURLQueryItem queryItemWithName:@"v" value:[ARTDefault version]];
    queryItems = [queryItems arrayByAddingObject:versionParam];
    
    // Lib
    NSURLQueryItem *libParam = [NSURLQueryItem queryItemWithName:@"lib" value:[ARTDefault agent]];
    queryItems = [queryItems arrayByAddingObject:libParam];

    // URL
    NSURLComponents *urlComponents = [NSURLComponents componentsWithString:@"/"];
    urlComponents.queryItems = queryItems;
    NSURL *url = [urlComponents URLRelativeToURL:[options realtimeUrl]];

    [_logger debug:__FILE__ line:__LINE__ message:@"R:%p WS:%p url %@", _delegate, self, url];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    const Class websocketClass = configuredWebsocketClass ? configuredWebsocketClass : [ARTSRWebSocket class];
    self.websocket = [[websocketClass alloc] initWithURLRequest:request];
    [self.websocket setDelegateDispatchQueue:_workQueue];
    self.websocket.delegate = self;
    self.websocketURL = url;
    return url;
}

- (void)sendClose {
    _state = ARTRealtimeTransportStateClosing;
    ARTProtocolMessage *closeMessage = [[ARTProtocolMessage alloc] init];
    closeMessage.action = ARTProtocolMessageClose;
    [self internalSend:closeMessage];
}

- (void)sendPing {
    ARTProtocolMessage *heartbeatMessage = [[ARTProtocolMessage alloc] init];
    heartbeatMessage.action = ARTProtocolMessageHeartbeat;
    [self internalSend:heartbeatMessage];
}

- (void)close {
    self.delegate = nil;
    if (!_websocket) return;
    self.websocket.delegate = nil;
    [self.websocket closeWithCode:ARTWsCloseNormal reason:@"Normal Closure"];
    self.websocket = nil;
}

- (void)abort:(ARTStatus *)reason {
    self.delegate = nil;
    if (!_websocket) return;
    self.websocket.delegate = nil;
    if (reason.errorInfo) {
        [self.websocket closeWithCode:ARTWsCloseNormal reason:reason.errorInfo.description];
    }
    else {
        [self.websocket closeWithCode:ARTWsCloseNormal reason:@"Abnormal Closure"];
    }
    self.websocket = nil;
}

- (void)setHost:(NSString *)host {
    self.options.realtimeHost = host;
}

- (NSString *)host {
    return self.options.realtimeHost;
}

- (ARTRealtimeTransportState)state {
    if (self.websocket.readyState == ARTSR_OPEN) {
        return ARTRealtimeTransportStateOpened;
    }
    return _state;
}

- (void)setState:(ARTRealtimeTransportState)state {
    _state = state;
}

#pragma mark - ARTSRWebSocketDelegate

// All delegate methods from SocketRocket are called from rest's serial queue,
// since we pass it as delegate queue on setupWebSocket. So we can safely
// call all our delegate's methods.

- (void)webSocketDidOpen:(id<ARTWebSocket>)websocket {
    [self.logger debug:__FILE__ line:__LINE__ message:@"R:%p WS:%p websocket did open", _delegate, self];
    [_stateEmitter emit:[ARTEvent newWithTransportState:ARTRealtimeTransportStateOpened] with:nil];
    [_delegate realtimeTransportAvailable:self];
}

- (void)webSocket:(id<ARTWebSocket>)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
    [self.logger debug:__FILE__ line:__LINE__ message:@"R:%p WS:%p websocket did disconnect (code %ld) %@", _delegate, self, (long)code, reason];

    switch (code) {
    case ARTWsCloseNormal:
        [_delegate realtimeTransportClosed:self];
        break;
    case ARTWsNeverConnected:
        [_delegate realtimeTransportNeverConnected:self];
        break;
    case ARTWsBuggyClose:
    case ARTWsGoingAway:
        // Connectivity issue
        [_delegate realtimeTransportDisconnected:self withError:nil];
        break;
    case ARTWsRefuse:
    case ARTWsPolicyValidation:
        [_delegate realtimeTransportRefused:self withError:[[ARTRealtimeTransportError alloc] initWithError:[ARTErrorInfo createWithCode:code message:reason] type:ARTRealtimeTransportErrorTypeRefused url:self.websocketURL]];
        break;
    case ARTWsTooBig:
        [_delegate realtimeTransportTooBig:self];
        break;
    case ARTWsNoUtf8:
    case ARTWsCloseProtocolError:
    case ARTWsUnexpectedCondition:
    case ARTWsExtension:
    case ARTWsTlsError:
        // Failed
        [_delegate realtimeTransportFailed:self withError:[[ARTRealtimeTransportError alloc] initWithError:[ARTErrorInfo createWithCode:code message:reason] type:ARTRealtimeTransportErrorTypeOther url:self.websocketURL]];
        break;
    default:
        NSAssert(true, @"WebSocket close: unknown code");
        break;
    }

    _state = ARTRealtimeTransportStateClosed;
    [_stateEmitter emit:[ARTEvent newWithTransportState:ARTRealtimeTransportStateClosed] with:nil];
}

- (void)webSocket:(id<ARTWebSocket>)webSocket didFailWithError:(NSError *)error {
    [self.logger debug:__FILE__ line:__LINE__ message:@"R:%p WS:%p websocket did receive error %@", _delegate, self, error];

    [_delegate realtimeTransportFailed:self withError:[self classifyError:error]];
    _state = ARTRealtimeTransportStateClosed;
}

- (ARTRealtimeTransportError *)classifyError:(NSError *)error {
    ARTRealtimeTransportErrorType type = ARTRealtimeTransportErrorTypeOther;

    if ([error.domain isEqualToString:@"com.squareup.SocketRocket"] && error.code == 504) {
        type = ARTRealtimeTransportErrorTypeTimeout;
    } else if ([error.domain isEqualToString:(NSString *)kCFErrorDomainCFNetwork]) {
        type = ARTRealtimeTransportErrorTypeHostUnreachable;
    } else if ([error.domain isEqualToString:@"NSPOSIXErrorDomain"] && (error.code == 57 || error.code == 50)) {
        type = ARTRealtimeTransportErrorTypeNoInternet;
    } else if ([error.domain isEqualToString:ARTSRWebSocketErrorDomain] && error.code == 2132) {
        id status = error.userInfo[ARTSRHTTPResponseErrorKey];
        if (status) {
            return [[ARTRealtimeTransportError alloc] initWithError:error
                                                    badResponseCode:[(NSNumber *)status integerValue]
                                                                url:self.websocketURL];
        }
    }

    return [[ARTRealtimeTransportError alloc] initWithError:error type:type url:self.websocketURL];
}

- (void)webSocket:(id<ARTWebSocket>)webSocket didReceiveMessage:(id)message {
    [self.logger verbose:__FILE__ line:__LINE__ message:@"R:%p WS:%p websocket did receive message", _delegate, self];

    if (self.websocket.readyState == ARTSR_CLOSED) {
        [self.logger debug:__FILE__ line:__LINE__ message:@"R:%p WS:%p websocket is closed, message has been ignored", _delegate, self];
        return;
    }

    if ([message isKindOfClass:[NSString class]]) {
        [self webSocketMessageText:(NSString *)message];
    } else if ([message isKindOfClass:[NSData class]]) {
        [self webSocketMessageData:(NSData *)message];
    } else if ([message isKindOfClass:[ARTProtocolMessage class]]) {
        [self webSocketMessageProtocol:(ARTProtocolMessage *)message];
    }
}

- (void)webSocketMessageText:(NSString *)text {
    [self.logger debug:__FILE__ line:__LINE__ message:@"R:%p WS:%p websocket in %@ state did receive message %@", _delegate, self, WebSocketStateToStr(self.websocket.readyState), text];

    NSData *data = nil;
    data = [((NSString *)text) dataUsingEncoding:NSUTF8StringEncoding];

    [self receiveWithData:data];
}

- (void)webSocketMessageData:(NSData *)data {
    [self.logger verbose:__FILE__ line:__LINE__ message:@"R:%p WS:%p websocket in %@ state did receive data %@", _delegate, self, WebSocketStateToStr(self.websocket.readyState), data];

    [self receiveWithData:data];
}

- (void)webSocketMessageProtocol:(ARTProtocolMessage *)message {
    [self.logger debug:__FILE__ line:__LINE__ message:@"R:%p WS:%p websocket in %@ state did receive protocol message %@", _delegate, self, WebSocketStateToStr(self.websocket.readyState), message];

    [self receive:message];
}

@end

NSString *WebSocketStateToStr(ARTSRReadyState state) {
    switch (state) {
        case ARTSR_CONNECTING:
            return @"Connecting"; //0
        case ARTSR_OPEN:
            return @"Open"; //1
        case ARTSR_CLOSING:
            return @"Closing"; //2
        case ARTSR_CLOSED:
            return @"Closed"; //3
    }
}

NSString *ARTRealtimeTransportStateToStr(ARTRealtimeTransportState state) {
    switch (state) {
        case ARTRealtimeTransportStateOpening:
            return @"Connecting"; //0
        case ARTRealtimeTransportStateOpened:
            return @"Open"; //1
        case ARTRealtimeTransportStateClosing:
            return @"Closing"; //2
        case ARTRealtimeTransportStateClosed:
            return @"Closed"; //3
    }
}

#pragma mark - ARTEvent

@implementation ARTEvent (TransportState)

- (instancetype)initWithTransportState:(ARTRealtimeTransportState)value {
    return [self initWithString:[NSString stringWithFormat:@"ARTRealtimeTransportState%@", ARTRealtimeTransportStateToStr(value)]];
}

+ (instancetype)newWithTransportState:(ARTRealtimeTransportState)value {
    return [[self alloc] initWithTransportState:value];
}

@end
