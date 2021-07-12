//
//  ARTTime.m
//  Ably
//
//  Created by Łukasz Szyszkowski on 12/07/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

#import "ARTTime.h"
#include <sys/types.h>
#include <sys/sysctl.h>

@implementation ARTTime

struct timeval bootTime;
struct timeval currentTime;
struct timezone timeZone;

+ (double) timeSinceBoot {
    
    int mib[2];
    size_t size;
    
    /**
     https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/sysctl.3.html
     */
    mib[0] = CTL_KERN;
    mib[1] = KERN_BOOTTIME;
    
    double timeSinceBoot = 0.0;
    
    gettimeofday(&currentTime, &timeZone);
    
    if (sysctl(mib, 2, &bootTime, &size, NULL, 0) != -1 && bootTime.tv_sec != 0) {
        /**
         @tv_sec - The number of whole seconds elapsed since the epoch (for a simple calendar time) or since some other starting point (for an elapsed time).
         */
        timeSinceBoot = currentTime.tv_sec - bootTime.tv_sec;
        /**
         @tv_usec - The number of microseconds elapsed since the time given by the tv_sec member.
         */
        timeSinceBoot += (currentTime.tv_usec - bootTime.tv_usec) / 1000000.0;
    }
    
    return timeSinceBoot;
}

@end
