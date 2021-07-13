//
//  ARTAuth.m
//
//  Created by Jason Choy on 08/12/2014.
//  Copyright (c) 2014 Ably. All rights reserved.
//

#import "ARTAuth+Private.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#import "ARTRest+Private.h"
#import "ARTHttp.h"
#import "ARTClientOptions.h"
#import "ARTAuthOptions.h"
#import "ARTTokenDetails.h"
#import "ARTTokenParams+Private.h"
#import "ARTTokenRequest.h"
#import "ARTEncoder.h"
#import "ARTStatus.h"
#import "ARTJsonEncoder.h"
#import "ARTGCD.h"
#import "ARTEventEmitter+Private.h"
#import "ARTPushActivationStateMachine+Private.h"
#import "ARTPushActivationEvent.h"
#import "ARTPushActivationState.h"
#import "ARTFormEncode.h"

@implementation ARTAuth {
    ARTQueuedDealloc *_dealloc;
}

- (instancetype)initWithInternal:(ARTAuthInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc {
    self = [super init];
    if (self) {
        _internal = internal;
        _dealloc = dealloc;
    }
    return self;
}

- (void)internalAsync:(void (^)(ARTAuthInternal * _Nonnull))use {
    dispatch_async(_internal.queue, ^{
        use(self->_internal);
    });
}

- (NSString *)clientId {
    return _internal.clientId;
}

- (ARTTokenDetails *)tokenDetails {
    return _internal.tokenDetails;
}

- (void)requestToken:(nullable ARTTokenParams *)tokenParams withOptions:(nullable ARTAuthOptions *)authOptions
            callback:(void (^)(ARTTokenDetails *_Nullable, NSError *_Nullable))callback {
    [_internal requestToken:tokenParams withOptions:authOptions callback:callback];
}

- (void)requestToken:(void (^)(ARTTokenDetails *_Nullable, NSError *_Nullable))callback {
    [_internal requestToken:callback];
}

- (void)authorize:(nullable ARTTokenParams *)tokenParams options:(nullable ARTAuthOptions *)authOptions
         callback:(void (^)(ARTTokenDetails *_Nullable, NSError *_Nullable))callback {
    [_internal authorize:tokenParams options:authOptions callback:callback];
}

- (void)authorize:(void (^)(ARTTokenDetails *_Nullable, NSError *_Nullable))callback {
    [_internal authorize:callback];
}

- (void)createTokenRequest:(nullable ARTTokenParams *)tokenParams options:(nullable ARTAuthOptions *)options
                  callback:(void (^)(ARTTokenRequest *_Nullable tokenRequest, NSError *_Nullable error))callback {
    [_internal createTokenRequest:tokenParams options:options callback:callback];
}

- (void)createTokenRequest:(void (^)(ARTTokenRequest *_Nullable tokenRequest, NSError *_Nullable error))callback {
    [_internal createTokenRequest:callback];
}

@end

@implementation ARTAuthInternal {
    __weak ARTRestInternal *_rest; // weak because rest owns auth
    dispatch_queue_t _userQueue;
    ARTTokenParams *_tokenParams;
    // Dedicated to Protocol Message
    NSString *_protocolClientId;
    NSInteger _authorizationsCount;
    ARTEventEmitter<ARTEvent *, ARTErrorInfo *> *_cancelationEventEmitter;
}

- (instancetype)init:(ARTRestInternal *)rest withOptions:(ARTClientOptions *)options {
    if (self = [super init]) {
        _rest = rest;
        _userQueue = rest.userQueue;
        _queue = rest.queue;
        _tokenDetails = options.tokenDetails;
        _options = options;
        _logger = rest.logger;
        _protocolClientId = nil;
        _cancelationEventEmitter = [[ARTInternalEventEmitter alloc] initWithQueue:_rest.queue];
        _tokenParams = options.defaultTokenParams ? : [[ARTTokenParams alloc] initWithOptions:self.options];
        _authorizationsCount = 0;
        [self validate:options];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveCurrentLocaleDidChangeNotification:)
                                                     name:NSCurrentLocaleDidChangeNotification
                                                   object:nil];

        #if TARGET_OS_IPHONE
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveApplicationSignificantTimeChangeNotification:)
                                                     name:UIApplicationSignificantTimeChangeNotification
                                                   object:nil];
        #else
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveApplicationSignificantTimeChangeNotification:)
                                                     name:NSSystemClockDidChangeNotification
                                                   object:nil];
        #endif
    }
    return self;
}

- (void)dealloc {
    [self removeTimeOffsetObserver];
}

- (void)removeTimeOffsetObserver {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSCurrentLocaleDidChangeNotification object:nil];
    #if TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationSignificantTimeChangeNotification object:nil];
    #else
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSSystemClockDidChangeNotification object:nil];
    #endif
}

- (void)didReceiveCurrentLocaleDidChangeNotification:(NSNotification *)notification {
    [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p NSCurrentLocaleDidChangeNotification received", _rest];
    [self discardTimeOffset];
}

- (void)didReceiveApplicationSignificantTimeChangeNotification:(NSNotification *)notification {
    [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p UIApplicationSignificantTimeChangeNotification received", _rest];
    [self discardTimeOffset];
}

- (void)validate:(ARTClientOptions *)options {
    // Only called from constructor, no need to synchronize.
    [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p validating %@", _rest, options];
    if ([options isBasicAuth]) {
        if (!options.tls) {
            [ARTException raise:@"ARTAuthException" format:@"Basic authentication only connects over HTTPS (tls)."];
        }
        // Basic
        [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p setting up auth method Basic (anonymous)", _rest];
        _method = ARTAuthMethodBasic;
    } else if (options.tokenDetails) {
        // TokenDetails
        [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p setting up auth method Token with token details", _rest];
        _method = ARTAuthMethodToken;
    } else if (options.token) {
        // Token
        [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p setting up auth method Token with supplied token only", _rest];
        _method = ARTAuthMethodToken;
        options.tokenDetails = [[ARTTokenDetails alloc] initWithToken:options.token];
    } else if (options.authUrl && options.authCallback) {
        [ARTException raise:@"ARTAuthException" format:@"Incompatible authentication configuration: please specify either authCallback and authUrl."];
    } else if (options.authUrl) {
        // Authentication url
        [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p setting up auth method Token with authUrl", _rest];
        _method = ARTAuthMethodToken;
    } else if (options.authCallback) {
        // Authentication callback
        [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p setting up auth method Token with authCallback", _rest];
        _method = ARTAuthMethodToken;
    } else if (options.key) {
        // Token
        [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p setting up auth method Token with key", _rest];
        _method = ARTAuthMethodToken;
    } else {
        [ARTException raise:@"ARTAuthException" format:@"Could not setup authentication method with given options."];
    }
    
    if ([options.clientId isEqual:@"*"]) {
        [ARTException raise:@"ARTAuthException" format:@"Invalid clientId: cannot contain only a wilcard \"*\"."];
    }
}

- (ARTAuthOptions *)mergeOptions:(ARTAuthOptions *)customOptions {
    return customOptions ? [self.options mergeWith:customOptions] : self.options;
}

- (void)storeOptions:(ARTAuthOptions *)customOptions {
    self.options.key = customOptions.key;
    self.options.tokenDetails = [customOptions.tokenDetails copy];
    self.options.authCallback = [customOptions.authCallback copy];
    self.options.authUrl = [customOptions.authUrl copy];
    self.options.authHeaders = [customOptions.authHeaders copy];
    self.options.authMethod = customOptions.authMethod;
    self.options.authParams = [customOptions.authParams copy];
    self.options.useTokenAuth = customOptions.useTokenAuth;
    self.options.queryTime = NO;
}

- (ARTTokenParams *)mergeParams:(ARTTokenParams *)customParams {
    return customParams ? customParams : [[ARTTokenParams alloc] initWithOptions:self.options];
}

- (void)storeParams:(ARTTokenParams *)customOptions {
    _options.clientId = customOptions.clientId;
    _options.defaultTokenParams = customOptions;
}

- (NSURL *)buildURL:(ARTAuthOptions *)options withParams:(ARTTokenParams *)params {
    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:options.authUrl resolvingAgainstBaseURL:YES];

    if ([options isMethodGET]) {
        // TokenParams take precedence over any configured authParams when a name conflict occurs
        NSArray *unitedParams = [params toArrayWithUnion:options.authParams];
        // When GET, use query string params
        if (!urlComponents.queryItems) {
            urlComponents.queryItems = @[];
        }
        urlComponents.queryItems = [urlComponents.queryItems arrayByAddingObjectsFromArray:unitedParams];
    }

    urlComponents.queryItems = [urlComponents.queryItems arrayByAddingObjectsFromArray:@[[NSURLQueryItem queryItemWithName:@"format" value:[_rest.defaultEncoder formatAsString]]]];

    // (Known '+' sign pitfall https://developer.apple.com/documentation/foundation/nsurlcomponents/1407752-queryitems?language=objc)
    // Apple's Response:
    // The '+' character is legal in the query component so it does not need to be percent-encoded.
    // Some systems use the '+' as a space and require '+' the plus character to be percent-encoded. However, that kind of two stage encoding (converting plus sign to %2B and then converting space to plus sign) is prone to errors because it easily leads to encoding problems. It also breaks if the URL is normalized (syntax normalization of URLs includes the removal of all unnecessary percent-encoding -- see rfc3986 section 6.2.2.2).
    // So, if you need that behavior because of the server your code is talking to, you'll handle that extra transformation(s) yourself.
    // Reference: "NSURLComponents does not correctly handle "+" usage in query parameters." http://www.openradar.me/24076063
    [urlComponents setPercentEncodedQuery:[[urlComponents percentEncodedQuery]
                                            // manually encode '+' into percent encoding
                                            stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"]];

    return urlComponents.URL;
}

- (NSMutableURLRequest *)buildRequest:(ARTAuthOptions *)options withParams:(ARTTokenParams *)params {
    NSURL *url = [self buildURL:options withParams:params];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = options.authMethod;

    // HTTP Header Fields
    if ([options isMethodPOST]) {
        // TokenParams take precedence over any configured authParams when a name conflict occurs
        NSDictionary<NSString *, NSString *> *const unitedParams =
            [params toDictionaryWithUnion:options.authParams];
        NSString *const encodedParametersString = ARTFormEncode(unitedParams);
        NSData *const formData = [encodedParametersString dataUsingEncoding:NSUTF8StringEncoding];
        [request setHTTPBody:formData];
        [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)formData.length] forHTTPHeaderField:@"Content-Length"];
    }
    else {
        [request setValue:[_rest.defaultEncoder mimeType] forHTTPHeaderField:@"Accept"];
    }

    for (NSString *key in options.authHeaders) {
        [request setValue:options.authHeaders[key] forHTTPHeaderField:key];
    }

    return request;
}

- (BOOL)isTokenAuth {
    return self.tokenDetails != nil || self.authorizing_nosync;
}

- (BOOL)tokenIsRenewable {
    return [self canRenewTokenAutomatically:self.options];
}

- (BOOL)canRenewTokenAutomatically:(ARTAuthOptions *)options {
    return options.authCallback || options.authUrl || options.key;
}

- (BOOL)tokenRemainsValid {
    if (self.tokenDetails && self.tokenDetails.token) {
        if (self.tokenDetails.expires == nil) {
            return YES;
        }
        
        // RSA4b1: Only check expiry client-side if local clock has been adjusted.
        // If it hasn't, assume the token remains valid.
        if (![self hasTimeOffset]) {
            return YES;
        }
        if ([self.tokenDetails.expires timeIntervalSinceDate:[self currentDate]] > 0) {
            return YES;
        }
    }
    return NO;
}

- (void)requestToken:(void (^)(ARTTokenDetails *, NSError *))callback {
    // If the object arguments are omitted, the client library configured defaults are used
    [self requestToken:_tokenParams withOptions:_options callback:callback];
}

- (void)requestToken:(ARTTokenParams *)tokenParams withOptions:(ARTAuthOptions *)authOptions callback:(void (^)(ARTTokenDetails *, NSError *))callback {
    if (callback) {
        void (^const userCallback)(ARTTokenDetails *, NSError *) = callback;
        callback = ^(ARTTokenDetails *t, NSError *e) {
            dispatch_async(self->_userQueue, ^{
                userCallback(t, e);
            });
        };
    }

dispatch_async(_queue, ^{
    [self _requestToken:tokenParams withOptions:authOptions callback:callback];
});
}

- (NSObject<ARTCancellable> *)_requestToken:(ARTTokenParams *)tokenParams withOptions:(ARTAuthOptions *)authOptions callback:(void (^)(ARTTokenDetails *, NSError *))callback {
    // If options, params passed in, they're used instead of stored, don't merge them
    ARTAuthOptions *replacedOptions = authOptions ? authOptions : self.options;
    ARTTokenParams *currentTokenParams = [tokenParams ? tokenParams : _tokenParams copy];
    __block NSObject<ARTCancellable> *task;

    if (![self canRenewTokenAutomatically:replacedOptions]) {
        callback(nil, [ARTErrorInfo createWithCode:ARTStateRequestTokenFailed message:ARTAblyMessageNoMeansToRenewToken]);
        return nil;
    }

    void (^const checkerCallback)(ARTTokenDetails *_Nullable, NSError *_Nullable) = ^(ARTTokenDetails *tokenDetails, NSError *error) {
        if (error) {
            if (error.code == NSURLErrorTimedOut) {
                ARTErrorInfo *ablyError = [ARTErrorInfo createWithCode:40170 message:@"Error in requesting auth token"];
                callback(nil, ablyError);
                return;
            }
            callback(nil, error);
            return;
        }
        if (self.clientId_nosync && tokenDetails.clientId && ![tokenDetails.clientId isEqualToString:@"*"] && ![self.clientId_nosync isEqual:tokenDetails.clientId]) {
            if (callback) callback(nil, [ARTErrorInfo createWithCode:40102 message:@"incompatible credentials"]);
            return;
        }
        callback(tokenDetails, nil);
    };

    if (replacedOptions.authUrl) {
        NSMutableURLRequest *request = [self buildRequest:replacedOptions withParams:currentTokenParams];

        [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p using authUrl (%@ %@)", _rest, request.HTTPMethod, request.URL];

        task = [_rest executeRequest:request withAuthOption:ARTAuthenticationOff completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
            if (error) {
                checkerCallback(nil, error);
            } else {
                [self.logger debug:@"RS:%p ARTAuth: authUrl response %@", self->_rest, response];
                [self handleAuthUrlResponse:response withData:data completion:checkerCallback];
            }
        }];
    } else {
        void (^tokenDetailsFactory)(ARTTokenParams *, void(^)(ARTTokenDetails *_Nullable, NSError *_Nullable));
        if (replacedOptions.authCallback) {
            // We're giving this callback to the user, and we don't control their code. If they were to hold on to
            // this callback, they could introduce a leak, since the callback may hold strong references
            // to Rest/Realtime.
            //
            // So we're going to apply the Fundamental Theorem of Software Engineering here and wrap the
            // callback in another reference. Then, we pass a callback that calls this reference,
            // and not the original callback. Then, we return a task that, if cancelled, sets that
            // intermediate reference to nil, so that we lose our reference to the original callback
            // and release any references it may hold to Rest/Realtime. Even if the user holds on to
            // the callback we give to them, they would be then holding to a now-nil reference to the
            // original callback.
            __weak void (^safeCallback)(id<ARTTokenDetailsCompatible> tokenDetailsCompat, NSError * error);
            task = artCancellableFromCallback(^(const id<ARTTokenDetailsCompatible> tokenDetailsCompat, NSError *const error) {
                if (error) {
                    callback(nil, error);
                } else {
                    [tokenDetailsCompat toTokenDetails:[self toAuth] callback:callback];
                }
            }, &safeCallback);

            void (^const userCallback)(ARTTokenParams *, void(^)(id<ARTTokenDetailsCompatible>, NSError *)) = ^(ARTTokenParams *tokenParams, void(^callback)(id<ARTTokenDetailsCompatible>, NSError *)){
                dispatch_async(self->_userQueue, ^{
                    replacedOptions.authCallback(tokenParams, callback);
                });
            };

            tokenDetailsFactory = ^(ARTTokenParams *tokenParams, void(^callback)(ARTTokenDetails *_Nullable, NSError *_Nullable)) {
                userCallback(tokenParams, ^(id<ARTTokenDetailsCompatible> tokenDetailsCompat, NSError *error) {
                    dispatch_async(self->_queue, ^{
                        // safeCallback is declared weak above so could be nil at this point.
                        void (^const callback)(id<ARTTokenDetailsCompatible> tokenDetailsCompat, NSError * error) = safeCallback;
                        if (callback) {
                            callback(tokenDetailsCompat, error);
                        }
                        [task cancel];
                    });
                });
            };
            [self.logger debug:@"RS:%p ARTAuth: using authCallback", _rest];
        } else {
            tokenDetailsFactory = ^(ARTTokenParams *tokenParams, void(^callback)(ARTTokenDetails *_Nullable, NSError *_Nullable)) {
                // Create a TokenRequest and execute it
                NSObject<ARTCancellable> *timeTask;
                timeTask = [self _createTokenRequest:currentTokenParams options:replacedOptions callback:^(ARTTokenRequest *tokenRequest, NSError *error) {
                    if (error) {
                        callback(nil, error);
                    } else {
                        task = [self executeTokenRequest:tokenRequest callback:callback];
                    }
                }];
                if (timeTask) {
                    task = timeTask;
                }
            };
        };

        tokenDetailsFactory(currentTokenParams, checkerCallback);
    }

    return task;
}

- (ARTAuth *)toAuth {
    // This feels hackish, but the alternative would be to change
    // ARTTokenDetailsCompatible to take a ARTAuthProtocol so we can just
    // pass self, but that would
    // break backwards-compatibility for users that have their own
    // ARTTokenDetailsCompatible implementations.
    ARTQueuedDealloc *dealloc = [[ARTQueuedDealloc alloc] init:self->_rest queue: self->_queue];
    return [[ARTAuth alloc] initWithInternal:self queuedDealloc:dealloc];
}

- (void)handleAuthUrlResponse:(NSHTTPURLResponse *)response withData:(NSData *)data completion:(void (^)(ARTTokenDetails *, NSError *))callback {
    // The token retrieved is assumed by the library to be a token string if the response has Content-Type "text/plain", or taken to be a TokenRequest or TokenDetails object if the response has Content-Type "application/json"
    if ([response.MIMEType isEqualToString:@"application/json"]) {
        NSError *decodeError = nil;
        ARTTokenDetails *tokenDetails = [_rest.encoders[@"application/json"] decodeTokenDetails:data error:&decodeError];
        if (decodeError) {
            callback(nil, decodeError);
        } else if (tokenDetails.token == nil) {
            ARTTokenRequest *tokenRequest = [_rest.encoders[@"application/json"] decodeTokenRequest:data error:&decodeError];
            if (decodeError) {
                callback(nil, decodeError);
            } else if (tokenRequest) {
                [tokenRequest toTokenDetails:[self toAuth] callback:callback];
            } else {
                callback(nil, [ARTErrorInfo createWithCode:ARTStateAuthUrlIncompatibleContent message:@"content response cannot be used for token request"]);
            }
        } else {
            callback(tokenDetails, nil);
        }
    }
    else if ([response.MIMEType isEqualToString:@"text/plain"] || [response.MIMEType isEqualToString:@"application/jwt"]) {
        NSString *token = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([token isEqualToString:@""]) {
            callback(nil, [NSError errorWithDomain:ARTAblyErrorDomain code:NSURLErrorCancelled userInfo:@{NSLocalizedDescriptionKey:@"authUrl: token is empty"}]);
            return;
        }
        ARTTokenDetails *tokenDetails = [[ARTTokenDetails alloc] initWithToken:token];
        callback(tokenDetails, nil);
    }
    else {
        callback(nil, [NSError errorWithDomain:ARTAblyErrorDomain code:NSURLErrorCancelled userInfo:@{NSLocalizedDescriptionKey:@"authUrl: invalid MIME type"}]);
    }
}

- (NSObject<ARTCancellable> *)executeTokenRequest:(ARTTokenRequest *)tokenRequest callback:(void (^)(ARTTokenDetails *, NSError *))callback {
    id<ARTEncoder> encoder = _rest.defaultEncoder;

    NSURL *requestUrl = [NSURL URLWithString:[NSString stringWithFormat:@"/keys/%@/requestToken?format=%@", tokenRequest.keyName, [encoder formatAsString]]
                               relativeToURL:_rest.baseUrl];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestUrl];
    request.HTTPMethod = @"POST";

    NSError *encodeError = nil;
    request.HTTPBody = [encoder encodeTokenRequest:tokenRequest error:&encodeError];
    if (encodeError) {
        callback(nil, encodeError);
        return nil;
    }
    [request setValue:[encoder mimeType] forHTTPHeaderField:@"Accept"];
    [request setValue:[encoder mimeType] forHTTPHeaderField:@"Content-Type"];

    return [_rest executeRequest:request withAuthOption:ARTAuthenticationOff completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (error) {
            callback(nil, error);
        } else {
            NSError *decodeError = nil;
            ARTTokenDetails *tokenDetails = [encoder decodeTokenDetails:data error:&decodeError];
            if (decodeError) {
                callback(nil, decodeError);
            } else {
                callback(tokenDetails, nil);
            }
        }
    }];
}

- (BOOL)authorizing {
    __block NSInteger count;
    dispatch_sync(_queue, ^{
        count = self->_authorizationsCount;
    });
    return count > 0;
}

- (BOOL)authorizing_nosync {
    return _authorizationsCount > 0;
}

- (void)authorize:(void (^)(ARTTokenDetails *, NSError *))callback {
    [self authorize:_options.defaultTokenParams options:_options callback:callback];
}

- (void)authorize:(ARTTokenParams *)tokenParams options:(ARTAuthOptions *)authOptions callback:(void (^)(ARTTokenDetails *, NSError *))callback {
    if (callback) {
        void (^userCallback)(ARTTokenDetails *, NSError *) = callback;
        callback = ^(ARTTokenDetails *t, NSError *e) {
            dispatch_async(self->_userQueue, ^{
                userCallback(t, e);
            });
        };
    }

dispatch_async(_queue, ^{
    [self _authorize:tokenParams options:authOptions callback:callback];
});
}

- (nullable NSObject<ARTCancellable> *)_authorize:(ARTTokenParams *)tokenParams options:(ARTAuthOptions *)authOptions callback:(void (^)(ARTTokenDetails *, NSError *))callback {
    ARTAuthOptions *replacedOptions = [authOptions copy] ? : [self.options copy];
    [self storeOptions:replacedOptions];

    ARTTokenParams *currentTokenParams = [self mergeParams:tokenParams];
    [self storeParams:currentTokenParams];

    __weak id<ARTAuthDelegate> lastDelegate = self.delegate;

    NSString *authorizeId = [[NSUUID new] UUIDString];
    __block BOOL hasBeenExplicitlyCanceled = NO;
    // Request always a new token
    [self.logger verbose:@"RS:%p ARTAuthInternal [authorize.%@, delegate=%@]: requesting new token", _rest, authorizeId, lastDelegate ? @"YES" : @"NO"];
    NSObject<ARTCancellable> *task;
    self->_authorizationsCount += 1;
    task = [self _requestToken:currentTokenParams withOptions:replacedOptions callback:^(ARTTokenDetails *tokenDetails, NSError *error) {
        self->_authorizationsCount -= 1;

        void (^const successCallbackBlock)(void) = ^{
            [self.logger verbose:@"RS:%p ARTAuthInternal [authorize.%@]: success callback: %@", self->_rest, authorizeId, tokenDetails];
            if (callback) {
                callback(tokenDetails, nil);
            }
        };
        
        void (^const failureCallbackBlock)(NSError *) = ^(NSError *error) {
            [self.logger verbose:@"RS:%p ARTAuthInternal [authorize.%@]: failure callback: %@ with token details %@", self->_rest, authorizeId, error, tokenDetails];
            if (callback) {
                callback(tokenDetails, error);
            }
        };

        void (^const canceledCallbackBlock)(void) = ^{
            [self.logger verbose:@"RS:%p ARTAuthInternal [authorize.%@]: canceled callback", self->_rest, authorizeId];
            if (callback) {
                callback(nil, [ARTErrorInfo createWithCode:kCFURLErrorCancelled message:@"Authorization has been canceled"]);
            }
        };

        if (error) {
            [self.logger debug:@"RS:%p ARTAuthInternal [authorize.%@]: token request failed: %@", self->_rest, authorizeId, error];
            failureCallbackBlock(error);
            return;
        }

        if (hasBeenExplicitlyCanceled) {
            canceledCallbackBlock();
            return;
        }

        [self.logger debug:@"RS:%p ARTAuthInternal [authorize.%@]: token request succeeded: %@", self->_rest, authorizeId, tokenDetails];

        [self setTokenDetails:tokenDetails];
        self->_method = ARTAuthMethodToken;

        if (!tokenDetails) {
            failureCallbackBlock([ARTErrorInfo createWithCode:0 message:@"Token details are empty"]);
        }
        else if (lastDelegate) {
            [lastDelegate auth:self didAuthorize:tokenDetails completion:^(ARTAuthorizationState state, ARTErrorInfo *error) {
                switch (state) {
                    case ARTAuthorizationSucceeded:
                        if (hasBeenExplicitlyCanceled) {
                            canceledCallbackBlock();
                            return;
                        }
                        successCallbackBlock();
                        [self setTokenDetails:tokenDetails];
                        break;
                    case ARTAuthorizationFailed:
                        [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p authorization failed with \"%@\" but the request token has already completed", self->_rest, error];
                        failureCallbackBlock(error);
                        [self setTokenDetails:nil];
                        break;
                    case ARTAuthorizationCancelled: {
                        [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p authorization cancelled but the request token has already completed", self->_rest];
                        canceledCallbackBlock();
                        break;
                    }
                }
            }];
        }
        else {
            successCallbackBlock();
        }
    }];

    [_cancelationEventEmitter once:^(ARTErrorInfo * _Nullable error) {
        hasBeenExplicitlyCanceled = YES;
        [task cancel];
    }];

    return task;
}

- (void)cancelAuthorization:(nullable ARTErrorInfo *)error {
    [self.logger debug:__FILE__ line:__LINE__ message:@"RS:%p authorization cancelled with %@", self->_rest, error];
    [_cancelationEventEmitter emit:nil with:error];
}

- (void)createTokenRequest:(void (^)(ARTTokenRequest *, NSError *))callback {
    [self createTokenRequest:_tokenParams options:_options callback:callback];
}

- (void)createTokenRequest:(ARTTokenParams *)tokenParams options:(ARTAuthOptions *)options callback:(void (^)(ARTTokenRequest *, NSError *))callback {
    if (callback) {
        void (^userCallback)(ARTTokenRequest *, NSError *) = callback;
        callback = ^(ARTTokenRequest *t, NSError *e) {
            dispatch_async(self->_userQueue, ^{
                userCallback(t, e);
            });
        };
    }

dispatch_async(_queue, ^{
    [self _createTokenRequest:tokenParams options:options callback:callback];
});
}

- (NSObject<ARTCancellable> *)_createTokenRequest:(ARTTokenParams *)tokenParams options:(ARTAuthOptions *)options callback:(void (^)(ARTTokenRequest *, NSError *))callback {
    ARTAuthOptions *replacedOptions = options ? : self.options;
    ARTTokenParams *currentTokenParams = tokenParams ? : [_tokenParams copy]; // copy since _tokenParams should be read-only
    currentTokenParams.timestamp = [self currentDate];

    if (currentTokenParams.capability) {
        // Validate: Capability JSON text
        NSError *errorCapability = nil;
        
        [NSJSONSerialization JSONObjectWithData:[currentTokenParams.capability dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&errorCapability];

        if (errorCapability) {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Capability: %@", errorCapability.localizedDescription] };
            callback(nil, [NSError errorWithDomain:ARTAblyErrorDomain code:errorCapability.code userInfo:userInfo]);
            return nil;
        }
    }

    if (replacedOptions.key == nil) {
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : @"no key provided for signing token requests" };
        callback(nil, [NSError errorWithDomain:ARTAblyErrorDomain code:0 userInfo:userInfo]);
        return nil;
    }

    if ([self hasTimeOffsetWithValue] && !replacedOptions.queryTime) {
        currentTokenParams.timestamp = [self currentDate];
        callback([currentTokenParams sign:replacedOptions.key], nil);
        return nil;
    }
    else {
        if (replacedOptions.queryTime) {
            return [_rest _time:^(NSDate *time, NSError *error) {
                if (error) {
                    callback(nil, error);
                } else {
                    NSDate *serverTime = [self handleServerTime:time];
                    self->_timeOffset = @([serverTime timeIntervalSinceNow]);
                    currentTokenParams.timestamp = serverTime;
                    callback([currentTokenParams sign:replacedOptions.key], nil);
                }
            }];
        } else {
            callback([currentTokenParams sign:replacedOptions.key], nil);
            return nil;
        }
    }
}

// For mocking when testing.
- (NSDate *)handleServerTime:(NSDate *)time {
    return time;
}

- (void)setProtocolClientId:(NSString *)clientId {
    _protocolClientId = clientId;
    #if TARGET_OS_IOS
    [self setLocalDeviceClientId_nosync:_protocolClientId];
    #endif
}

- (NSString *)clientId {
    __block NSString *clientId;
dispatch_sync(_queue, ^{
    clientId = self.clientId_nosync;
});
    return clientId;
}

- (NSString *)clientId_nosync {
    if (_protocolClientId) {
        return _protocolClientId;
    }
    else if (self.tokenDetails && self.tokenDetails.clientId) {
        return self.tokenDetails.clientId;
    }
    else {
        return self.options.clientId;
    }
}

- (NSDate *)currentDate {
    return [[NSDate date] dateByAddingTimeInterval:_timeOffset.doubleValue];
}

- (BOOL)hasTimeOffset {
    return _timeOffset != nil;
}

- (BOOL)hasTimeOffsetWithValue {
    return _timeOffset != nil && _timeOffset.doubleValue > 0;
}

- (void)discardTimeOffset {
    // This may run after dealloc has been called in _rest. I've seen this
    // happen when rest.auth is put in a variable, even if (apparently) that
    // variable doesn't outlive rest! See commit 5a354524 for a reproducible
    // example, by running the Auth.swift tests. Instruments reports a memory
    // leak, but I wasn't able to get to why it happens after a full day. So
    // I'm just adding this check.
    if (!_rest) {
        [self removeTimeOffsetObserver];
        return;
    }

// Called from NSNotificationCenter, so must put change in the queue.
dispatch_sync(_queue, ^{
    [self clearTimeOffset];
});
}

- (void)setTokenDetails:(ARTTokenDetails *)tokenDetails {
    _tokenDetails = tokenDetails;
    #if TARGET_OS_IOS
    [self setLocalDeviceClientId_nosync:tokenDetails.clientId];
    #endif
}

- (void)setTimeOffset:(NSTimeInterval)offset {
    _timeOffset = @(offset);
}

- (void)clearTimeOffset; {
    _timeOffset = nil;
}

- (NSString *_Nullable)appId {
    NSString *s = nil;
    if (_options.key) {
        s = _options.key;
    } else if (_options.token) {
        s = _options.token;
    } else if (_tokenDetails) {
        s = _tokenDetails.token;
    }
    if (!s) {
        return nil;
    }
    NSArray<NSString *> *parts = [s componentsSeparatedByString:@"."];
    if (parts.count < 2) {
        return nil;
    }
    return parts[0];
}

#if TARGET_OS_IOS
- (void)setLocalDeviceClientId_nosync:(NSString *)clientId {
    if (clientId == nil || [clientId isEqualToString:@"*"] || [clientId isEqualToString:_rest.device_nosync.clientId]) {
        return;
    }
    [_rest.device_nosync setClientId:clientId];
    [_rest.push getActivationMachine:^(ARTPushActivationStateMachine *stateMachine) {
        if (![stateMachine.current_nosync isKindOfClass:[ARTPushActivationStateNotActivated class]]) {
            [stateMachine sendEvent:[[ARTPushActivationEventGotPushDeviceDetails alloc] init]];
        }
    }];
}
#endif

@end

@implementation NSString (ARTTokenDetailsCompatible)

- (void)toTokenDetails:(ARTAuth *)auth callback:(void (^)(ARTTokenDetails * _Nullable, NSError * _Nullable))callback {
    callback([[ARTTokenDetails alloc] initWithToken:self], nil);
}

@end

NSString *ARTAuthorizationStateToStr(ARTAuthorizationState state) {
    switch (state) {
        case ARTAuthorizationSucceeded:
            return @"Succeeded"; //0
        case ARTAuthorizationFailed:
            return @"Failed"; //1
        case ARTAuthorizationCancelled:
            return @"Cancelled"; //2
    }
}

#pragma mark - ARTEvent

@implementation ARTEvent (AuthorizationState)

- (instancetype)initWithAuthorizationState:(ARTAuthorizationState)value {
    return [self initWithString:[NSString stringWithFormat:@"ARTAuthorizationState%@", ARTAuthorizationStateToStr(value)]];
}

+ (instancetype)newWithAuthorizationState:(ARTAuthorizationState)value {
    return [[self alloc] initWithAuthorizationState:value];
}

@end
