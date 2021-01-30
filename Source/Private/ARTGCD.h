//
//  ARTGCD.h
//  Ably
//
//  Created by Ricardo Pereira on 17/11/2016.
//  Copyright © 2016 Ably. All rights reserved.
//

#import <Foundation/Foundation.h>

/// ARTScheduledBlockHandle wraps a block for delayed invocation within a queue. If/when the handle deallocates, the scheduled invocation will be cancelled if it has not already been executed.
@interface ARTScheduledBlockHandle : NSObject
- (instancetype)initWithDelay:(NSTimeInterval)delay queue:(dispatch_queue_t)queue block:(dispatch_block_t)block;
- (void)cancel;
@end


static inline ARTScheduledBlockHandle *artDispatchScheduled(NSTimeInterval seconds, dispatch_queue_t queue, dispatch_block_t block) {
    // We don't pass the block directly; instead, we put it in a property, and
    // read it back from the property once the timer fires. This gives us the
    // chance to set the property to nil when cancelling the timer, thus
    // releasing our retain on the block early. dispatch_block_cancel doesn't do
    // this, it retains the block even if you cancel the dispatch until the
    // dispatch time passes. (How this is a good idea escapes me.)
    //
    // From Apple's documentation [1]:
    //
    // > Release of any resources associated with the block object is delayed
    // > until execution of the block object is next attempted (or any execution
    // > already in progress completes).
    //
    // https://developer.apple.com/documentation/dispatch/1431058-dispatch_block_cancel

    return [[ARTScheduledBlockHandle alloc] initWithDelay:seconds queue:queue block:block];
}

static inline void artDispatchCancel(ARTScheduledBlockHandle *handle) {
    if (handle) {
        [handle cancel];
    }
}
