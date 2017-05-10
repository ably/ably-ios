//
//  ARTSentry.h
//  Ably
//
//  Created by Toni Cárdenas on 04/05/2017.
//  Copyright © 2017 Ably. All rights reserved.
//

#ifndef ARTSentry_h
#define ARTSentry_h

#import <Foundation/Foundation.h>
#import "CompatibilityMacros.h"

ART_ASSUME_NONNULL_BEGIN

@protocol ARTSentryBreadcrumb <NSCoding>

- (NSDictionary *)toBreadcrumb;

@end

@interface ARTSentry : NSObject

+ (void)setTags:(NSDictionary *)value;
+ (void)setExtras:(NSString *)key value:(id)value;
+ (NSArray<NSDictionary *> *)breadcrumbs;
+ (void)setBreadcrumbs:(NSString *)key value:(NSArray<id<ARTSentryBreadcrumb>> *)value;
+ (void)setUserInfo:(NSString *)key value:(id)value;
+ (void)setUserInfo:(NSString *)key key:(NSString *)innerKey value:(id)value;
+ (BOOL)setCrashHandler:(NSString *_Nullable)dns;
+ (void)report:(NSString *)message to:(NSString *)dns extra:(NSDictionary *_Nullable)extra breadcrumbs:(NSArray<NSDictionary *> *_Nullable)breadcrumbs tags:(NSDictionary *)tags exception:(NSException *_Nullable)exception;
+ (void)report:(NSString *)message to:(NSString *)dns extra:(NSDictionary *_Nullable)extra breadcrumbs:(NSArray<NSDictionary *> *_Nullable)breadcrumbs tags:(NSDictionary *)tags exception:(NSException *_Nullable)exception callback:(void (^_Nullable)(NSError *_Nullable))callback;
+ (void)report:(NSMutableDictionary *)body to:(NSString *)dns callback:(void (^_Nullable)(NSError *_Nullable))callback;

@end

id ART_orNull(id _Nullable obj);

ART_ASSUME_NONNULL_END

#endif /* ARTSentry_h */
