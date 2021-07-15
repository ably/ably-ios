//
//  ARTRestChannel.m
//
//  Created by Ricardo Pereira on 05/10/2015.
//  Copyright (c) 2015 Ably. All rights reserved.
//

#import "ARTRestChannel+Private.h"

#import "ARTRest+Private.h"
#import "ARTRestPresence+Private.h"
#import "ARTChannel+Private.h"
#import "ARTChannelOptions.h"
#import "ARTMessage.h"
#import "ARTBaseMessage+Private.h"
#import "ARTPaginatedResult+Private.h"
#import "ARTDataQuery+Private.h"
#import "ARTJsonEncoder.h"
#import "ARTAuth+Private.h"
#import "ARTTokenDetails.h"
#import "ARTNSArray+ARTFunctional.h"
#import "ARTPushChannel+Private.h"
#import "ARTCrypto+Private.h"
#import "ARTClientOptions.h"
#import "ARTNSError+ARTUtils.h"

@implementation ARTRestChannel {
    ARTQueuedDealloc *_dealloc;
}

- (instancetype)initWithInternal:(ARTRestChannelInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc {
    self = [super init];
    if (self) {
        _internal = internal;
        _dealloc = dealloc;
    }
    return self;
}

- (ARTRestPresence*) presence {
    return [[ARTRestPresence alloc] initWithInternal:_internal.presence queuedDealloc:_dealloc];
}

- (ARTPushChannel *)push {
    return [[ARTPushChannel alloc] initWithInternal:_internal.push queuedDealloc:_dealloc];
}

- (NSString *)name {
    return _internal.name;
}

- (BOOL)history:(nullable ARTDataQuery *)query callback:(void(^)(ARTPaginatedResult<ARTMessage *> *_Nullable result, ARTErrorInfo *_Nullable error))callback error:(NSError *_Nullable *_Nullable)errorPtr {
    return [_internal history:query callback:callback error:errorPtr];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data {
    [_internal publish:name data:data];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data callback:(nullable void (^)(ARTErrorInfo *_Nullable error))callback {
    [_internal publish:name data:data callback:callback];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data clientId:(NSString *)clientId {
    [_internal publish:name data:data clientId:clientId];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data clientId:(NSString *)clientId callback:(nullable void (^)(ARTErrorInfo *_Nullable error))callback {
    [_internal publish:name data:data clientId:clientId callback:callback];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data extras:(nullable id<ARTJsonCompatible>)extras {
    [_internal publish:name data:data extras:extras];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data extras:(nullable id<ARTJsonCompatible>)extras callback:(nullable void (^)(ARTErrorInfo *_Nullable error))callback {
    [_internal publish:name data:data extras:extras callback:callback];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data clientId:(NSString *)clientId extras:(nullable id<ARTJsonCompatible>)extras {
    [_internal publish:name data:data clientId:clientId extras:extras];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data clientId:(NSString *)clientId extras:(nullable id<ARTJsonCompatible>)extras callback:(nullable void (^)(ARTErrorInfo *_Nullable error))callback {
    [_internal publish:name data:data clientId:clientId extras:extras callback:callback];
}

- (void)publish:(NSArray<ARTMessage *> *)messages {
    [_internal publish:messages];
}

- (void)publish:(NSArray<ARTMessage *> *)messages callback:(nullable void (^)(ARTErrorInfo *_Nullable error))callback {
    [_internal publish:messages callback:callback];
}

- (void)history:(void(^)(ARTPaginatedResult<ARTMessage *> *_Nullable result, ARTErrorInfo *_Nullable error))callback {
    [_internal history:callback];
}

- (ARTChannelOptions *)options {
    return [_internal options];
}

- (void)setOptions:(ARTChannelOptions *_Nullable)options {
    [_internal setOptions:options];
}

@end

static const NSUInteger kIdempotentLibraryGeneratedIdLength = 9; //bytes

@implementation ARTRestChannelInternal {
@private
    dispatch_queue_t _userQueue;
    ARTRestPresenceInternal *_presence;
    ARTPushChannelInternal *_pushChannel;
@public
    NSString *_basePath;
}

@dynamic options;

- (instancetype)initWithName:(NSString *)name withOptions:(ARTChannelOptions *)options andRest:(ARTRestInternal *)rest {
    if (self = [super initWithName:name andOptions:options rest:rest]) {
        _rest = rest;
        _queue = rest.queue;
        _userQueue = rest.userQueue;
        _basePath = [NSString stringWithFormat:@"/channels/%@", [name stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]];
        [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p instantiating under '%@'", self, name];
    }
    return self;
}

- (ARTLog *)getLogger {
    return _rest.logger;
}

- (NSString *)getBasePath {
    return _basePath;
}

- (ARTRestPresenceInternal *)presence {
    if (!_presence) {
        _presence = [[ARTRestPresenceInternal alloc] initWithChannel:self];
    }
    return _presence;
}

- (ARTPushChannelInternal *)push {
    if (!_pushChannel) {
        _pushChannel = [[ARTPushChannelInternal alloc] init:self.rest withChannel:self];
    }
    return _pushChannel;
}

- (void)history:(void (^)(__GENERIC(ARTPaginatedResult, ARTMessage *) *, ARTErrorInfo *))callback {
    [self history:[[ARTDataQuery alloc] init] callback:callback error:nil];
}

- (BOOL)history:(ARTDataQuery *)query callback:(void(^)(__GENERIC(ARTPaginatedResult, ARTMessage *) *result, ARTErrorInfo *error))callback error:(NSError * __autoreleasing *)errorPtr {
    if (callback) {
        void (^userCallback)(__GENERIC(ARTPaginatedResult, ARTMessage *) *result, ARTErrorInfo *error) = callback;
        callback = ^(__GENERIC(ARTPaginatedResult, ARTMessage *) *result, ARTErrorInfo *error) {
            dispatch_async(self->_userQueue, ^{
                userCallback(result, error);
            });
        };
    }

    __block BOOL ret;
dispatch_sync(_queue, ^{
    if (query.limit > 1000) {
        if (errorPtr) {
            *errorPtr = [NSError errorWithDomain:ARTAblyErrorDomain
                                            code:ARTDataQueryErrorLimit
                                        userInfo:@{NSLocalizedDescriptionKey:@"Limit supports up to 1000 results only"}];
        }
        ret = NO;
        return;
    }
    if ([query.start compare:query.end] == NSOrderedDescending) {
        if (errorPtr) {
            *errorPtr = [NSError errorWithDomain:ARTAblyErrorDomain
                                            code:ARTDataQueryErrorTimestampRange
                                        userInfo:@{NSLocalizedDescriptionKey:@"Start must be equal to or less than end"}];
        }
        ret = NO;
        return;
    }

    NSURLComponents *componentsUrl = [NSURLComponents componentsWithString:[self->_basePath stringByAppendingPathComponent:@"messages"]];
    NSError *error = nil;
    componentsUrl.queryItems = [query asQueryItems:&error];
    if (error) {
        if (errorPtr) {
            *errorPtr = error;
        }
        ret = NO;
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:componentsUrl.URL];

    ARTPaginatedResultResponseProcessor responseProcessor = ^NSArray<ARTMessage *> *(NSHTTPURLResponse *response, NSData *data, NSError **errorPtr) {
        id<ARTEncoder> encoder = [self->_rest.encoders objectForKey:response.MIMEType];
        return [[encoder decodeMessages:data error:errorPtr] artMap:^(ARTMessage *message) {
            NSError *decodeError = nil;
            message = [message decodeWithEncoder:self.dataEncoder error:&decodeError];
            if (decodeError != nil) {
                ARTErrorInfo *errorInfo = [ARTErrorInfo wrap:[ARTErrorInfo createWithCode:40018 message:decodeError.localizedFailureReason] prepend:@"Failed to decode data: "];
                [self.logger error:@"RS:%p C:%p (%@) %@", self->_rest, self, self.name, errorInfo.message];
            }
            return message;
        }];
    };

    [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p C:%p (%@) stats request %@", self->_rest, self, self.name, request];
    [ARTPaginatedResult executePaginated:self->_rest withRequest:request andResponseProcessor:responseProcessor callback:callback];
    ret = YES;
});
    return ret;
}

- (void)internalPostMessages:(id)data callback:(void (^)(ARTErrorInfo *__art_nullable error))callback {
    if (callback) {
        void (^userCallback)(ARTErrorInfo *__art_nullable error) = callback;
        callback = ^(ARTErrorInfo *__art_nullable error) {
            dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }
    
    dispatch_async(_queue, ^{
        NSData *encodedMessage = nil;
        
        if ([data isKindOfClass:[ARTMessage class]]) {
            ARTMessage *message = (ARTMessage *)data;
            
            NSString *baseId = nil;
            if (self.rest.options.idempotentRestPublishing && message.isIdEmpty) {
                NSData *baseIdData = [ARTCrypto generateSecureRandomData:kIdempotentLibraryGeneratedIdLength];
                baseId = [baseIdData base64EncodedStringWithOptions:0];
                message.id = [NSString stringWithFormat:@"%@:0", baseId];
            }
            
            if (message.clientId && self.rest.auth.clientId_nosync && ![message.clientId isEqualToString:self.rest.auth.clientId_nosync]) {
                callback([ARTErrorInfo createWithCode:ARTStateMismatchedClientId message:@"attempted to publish message with an invalid clientId"]);
                return;
            }
            
            NSError *encodeError = nil;
            encodedMessage = [self.rest.defaultEncoder encodeMessage:message error:&encodeError];
            if (encodeError) {
                callback([ARTErrorInfo createFromNSError:encodeError]);
                return;
            }
        }
        else if ([data isKindOfClass:[NSArray class]]) {
            NSArray<ARTMessage *> *messages = (NSArray *)data;
            
            NSString *baseId = nil;
            if (self.rest.options.idempotentRestPublishing) {
                BOOL messagesHaveEmptyId = [messages artFilter:^BOOL(ARTMessage *m) { return !m.isIdEmpty; }].count <= 0;
                if (messagesHaveEmptyId) {
                    NSData *baseIdData = [ARTCrypto generateSecureRandomData:kIdempotentLibraryGeneratedIdLength];
                    baseId = [baseIdData base64EncodedStringWithOptions:0];
                }
            }
            
            NSInteger serial = 0;
            for (ARTMessage *message in messages) {
                if (message.clientId && self.rest.auth.clientId_nosync && ![message.clientId isEqualToString:self.rest.auth.clientId_nosync]) {
                    callback([ARTErrorInfo createWithCode:ARTStateMismatchedClientId message:@"attempted to publish message with an invalid clientId"]);
                    return;
                }
                if (baseId) {
                    message.id = [NSString stringWithFormat:@"%@:%ld", baseId, (long)serial];
                }
                serial += 1;
            }
            
            NSError *encodeError = nil;
            encodedMessage = [self.rest.defaultEncoder encodeMessages:data error:&encodeError];
            if (encodeError) {
                callback([ARTErrorInfo createFromNSError:encodeError]);
                return;
            }
        }
        
        NSURLComponents *components = [[NSURLComponents alloc] initWithURL:[NSURL URLWithString:[self->_basePath stringByAppendingPathComponent:@"messages"]] resolvingAgainstBaseURL:YES];
        NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray new];
        
        if (queryItems.count > 0) {
            components.queryItems = queryItems;
        }
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[components URL]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = encodedMessage;
        
        if (self.rest.defaultEncoding) {
            [request setValue:self.rest.defaultEncoding forHTTPHeaderField:@"Content-Type"];
        }
        
        [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p C:%p (%@) post message %@", self->_rest, self, self.name, [[NSString alloc] initWithData:encodedMessage encoding:NSUTF8StringEncoding]];
        
        [self->_rest executeRequest:request withAuthOption:ARTAuthenticationOn completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
            if (callback) {
                ARTErrorInfo *errorInfo;
                if (self->_rest.options.addRequestIds) {
                    errorInfo = error ? [ARTErrorInfo wrap:[ARTErrorInfo createFromNSError:error] prepend:[NSString stringWithFormat:@"Request '%@' failed with ", request.URL]] : nil;
                } else {
                    errorInfo = error ? [ARTErrorInfo createFromNSError:error] : nil;
                }
                
                callback(errorInfo);
            }
        }];
    });
}

@end
