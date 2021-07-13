//
//  ARTStatus.h
//
//  Created by Jason Choy on 08/12/2014.
//  Copyright (c) 2014 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, ARTState) {
    ARTStateOk = 0,
    ARTStateConnectionClosedByClient,
    ARTStateConnectionDisconnected,
    ARTStateConnectionSuspended,
    ARTStateConnectionFailed,
    ARTStateAccessRefused,
    ARTStateNeverConnected,
    ARTStateConnectionTimedOut,
    ARTStateAttachTimedOut,
    ARTStateDetachTimedOut,
    ARTStateNotAttached,
    ARTStateInvalidArgs,
    ARTStateCryptoBadPadding,
    ARTStateNoClientId,
    ARTStateMismatchedClientId,
    ARTStateRequestTokenFailed,
    ARTStateAuthorizationFailed,
    ARTStateAuthUrlIncompatibleContent,
    ARTStateBadConnectionState,
    ARTStateError = 99999
};

/**
 The list of all public error codes returned under the error domain ARTAblyErrorDomain
 */
typedef CF_ENUM(NSUInteger, ARTCodeError) {
    // FIXME: check hard coded errors
    ARTCodeErrorAPIKeyMissing = 80001,
    ARTCodeErrorAPIInconsistency = 80002,
    ARTCodeErrorConnectionTimedOut = 80014,
    ARTCodeErrorAuthConfiguredProviderFailure = 80019,
};

/**
 The list of all client error codes returned under the error domain ARTAblyErrorDomain
 */
typedef CF_ENUM(NSUInteger, ARTClientCodeError) {
    ARTClientCodeErrorInvalidType,
    ARTClientCodeErrorTransport,
};

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const ARTAblyErrorDomain;

/**
 Ably client exception names
 */
FOUNDATION_EXPORT NSString *const ARTFallbackIncompatibleOptionsException;

/**
 Ably client error messages
 */
FOUNDATION_EXPORT NSString *const ARTAblyMessageNoMeansToRenewToken;

/**
 Ably client error class
 */
@interface ARTErrorInfo : NSError

@property (readonly) NSString *message;
@property (nullable, readonly) NSString *reason;
@property (readonly) NSInteger statusCode;

+ (ARTErrorInfo *)createWithCode:(NSInteger)code message:(NSString *)message;
+ (ARTErrorInfo *)createWithCode:(NSInteger)code status:(NSInteger)status message:(NSString *)message;
+ (ARTErrorInfo *)createFromNSError:(NSError *)error;
+ (ARTErrorInfo *)createFromNSException:(NSException *)error;
+ (ARTErrorInfo *)createUnknownError;
+ (ARTErrorInfo *)wrap:(ARTErrorInfo *)error prepend:(NSString *)prepend;

- (NSString *)description;

@end

/**
 Ably client status class
 */
@interface ARTStatus : NSObject

@property (nullable, readonly, strong, nonatomic) ARTErrorInfo *errorInfo;
@property (nonatomic, assign) BOOL storeErrorInfo;
@property (nonatomic, assign) ARTState state;

+ (ARTStatus *)state:(ARTState) state;
+ (ARTStatus *)state:(ARTState) state info:(nullable ARTErrorInfo *) info;

- (NSString *)description;

@end

@interface ARTException : NSException
@end

/**
 Support of ARTErrorInfo's properties for NSError
 */
@interface NSError (ARTErrorInfo)

- (NSInteger)artStatusCode;

@end

NS_ASSUME_NONNULL_END
