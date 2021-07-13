//
//  ARTDefault.h
//  ably
//
//  Created by vic on 01/06/2015.
//  Copyright (c) 2015 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ARTDefault : NSObject

+ (NSArray<NSString *> *)fallbackHosts;
+ (NSArray<NSString *> *)fallbackHostsWithEnvironment:(NSString *)environment;
+ (NSString*)restHost;
+ (NSString*)realtimeHost;
+ (int)port;
+ (int)tlsPort;

/**
 Default in seconds of requested time to live for the token.
 */
+ (NSTimeInterval)ttl;

/**
 When the client is in the DISCONNECTED state, once this TTL has passed, the client should change the state to the SUSPENDED state signifying that the state is now lost i.e. channels need to be reattached manually.
 
 Note that this default is override by any connectionStateTtl specified in the ConnectionDetails of the CONNECTED ProtocolMessage.
 */
+ (NSTimeInterval)connectionStateTtl;

/**
 When a realtime client library is establishing a connection with Ably, or sending a HEARTBEAT, CONNECT, ATTACH, DETACH or CLOSE ProtocolMessage to Ably, this is the amount of time that the client library will wait before considering that request as failed and triggering a suitable failure condition.
 */
+ (NSTimeInterval)realtimeRequestTimeout;

+ (NSString *)version;

+ (NSString *)libraryVersion;

+ (NSInteger)maxMessageSize;

@end
