//
//  ARTPushActivationEvent.h
//  Ably
//
//  Created by Ricardo Pereira on 22/02/2017.
//  Copyright © 2017 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ARTErrorInfo;
@class ARTPushActivationState;

NS_ASSUME_NONNULL_BEGIN

@interface ARTPushActivationEvent : NSObject <NSCoding>

- (NSData *)archive;
+ (nullable ARTPushActivationState *)unarchive:(NSData *)data;

@end

/// Event with Error info
@interface ARTPushActivationErrorEvent : ARTPushActivationEvent

@property (nonatomic, readonly) ARTErrorInfo *error;

- (instancetype)initWithError:(ARTErrorInfo *)error;
+ (instancetype)newWithError:(ARTErrorInfo *)error;

@end

#pragma mark - Events

@interface ARTPushActivationEventCalledActivate : ARTPushActivationEvent
@end

@interface ARTPushActivationEventCalledDeactivate : ARTPushActivationEvent
@end

@interface ARTPushActivationEventGotPushDeviceDetails : ARTPushActivationEvent
@end

@interface ARTPushActivationEventGotDeviceRegistration : ARTPushActivationEvent
@end

@interface ARTPushActivationEventGettingDeviceRegistrationFailed : ARTPushActivationErrorEvent
@end

@interface ARTPushActivationEventRegistrationUpdated : ARTPushActivationEvent
@end

@interface ARTPushActivationEventUpdatingRegistrationFailed : ARTPushActivationErrorEvent
@end

@interface ARTPushActivationEventDeregistered : ARTPushActivationEvent
@end

@interface ARTPushActivationEventDeregistrationFailed : ARTPushActivationErrorEvent
@end

NS_ASSUME_NONNULL_END
