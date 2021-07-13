//
//  ARTGCD.m
//  Ably
//
//  Created by Ricardo Pereira on 17/11/2016.
//  Copyright © 2016 Ably. All rights reserved.
//

#import "ARTGCD.h"

@implementation ARTScheduledBlockHandle {
    dispatch_semaphore_t _semaphore;
    dispatch_block_t _block;
    dispatch_block_t _scheduledBlock;
}

- (instancetype)initWithDelay:(NSTimeInterval)delay queue:(dispatch_queue_t)queue block:(dispatch_block_t)block {
    self = [super init];
    if (self == nil)
        return nil;

    // Use a sempaphore to coorindate state. We use a reference here to decouple it when creating a block we'll schedule.
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(1);

    __weak ARTScheduledBlockHandle *weakSelf = self;
    _scheduledBlock = dispatch_block_create(0, ^{
        dispatch_block_t copiedBlock = nil;
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        {
            // Get a strong reference to self within our semaphore to avoid potential race conditions
            ARTScheduledBlockHandle *strongSelf = weakSelf;
            if (strongSelf != nil) {
                copiedBlock = strongSelf->_block; // copied below
            }
        }
        dispatch_semaphore_signal(semaphore);

        // If our block is non-nil, our scheduled block was still valid by the time this was invoked
        if (copiedBlock != nil) {
            copiedBlock();
        }
    });

    _block = [block copy];
    _semaphore = semaphore;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC * delay)), queue, _scheduledBlock);

    return self;
}

- (void)cancel {
    // Cancel within our semaphore for predictable behavior if our block is invoked while we're cancelling
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    {
        dispatch_block_cancel(_scheduledBlock);
        _block = nil;
    }
    dispatch_semaphore_signal(_semaphore);
}

- (void)dealloc {
    // Explicitly cancel when we deallocate. This happens implicitly since our scheduled block keeps a weak
    // reference to self, but we want to make sure that the weak reference can be safely accessed, even if
    // we're in the midst of deallocating.
    [self cancel];
}

@end

ARTScheduledBlockHandle *artDispatchScheduled(NSTimeInterval seconds, dispatch_queue_t queue, dispatch_block_t block) {
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
