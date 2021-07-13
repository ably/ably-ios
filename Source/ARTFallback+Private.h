//
//  ARTFallback+Private.h
//  Ably
//
//  Created by Ricardo Pereira on 13/10/16.
//  Copyright © 2016 Ably. All rights reserved.
//

#include <Ably/ARTFallback.h>

NS_ASSUME_NONNULL_BEGIN

extern void (^ARTFallback_shuffleArray)(NSMutableArray *);

@interface ARTFallback ()

@property (readwrite, strong, nonatomic) NSMutableArray<NSString *> *hosts;

@end

NS_ASSUME_NONNULL_END
