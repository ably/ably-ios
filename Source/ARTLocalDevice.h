//
//  ARTLocalDevice.h
//  Ably
//
//  Created by Ricardo Pereira on 28/02/2017.
//  Copyright © 2017 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Ably/ARTDeviceDetails.h>

@class ARTDeviceIdentityTokenDetails;

NS_ASSUME_NONNULL_BEGIN

@interface ARTLocalDevice : ARTDeviceDetails

@property (nullable, nonatomic, readonly) ARTDeviceIdentityTokenDetails *identityTokenDetails;

/**
 Device secret generated using random data with sufficient entropy. It's a sha256 digest encoded with base64.
 */
@property (nullable, nonatomic) ARTDeviceSecret *secret;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
