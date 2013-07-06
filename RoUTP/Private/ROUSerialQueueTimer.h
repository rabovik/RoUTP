//
//  ROUSerialQueueTimer.h
//  RoUTPTests
//
//  Created by Yan Rabovik on 02.07.13.
//  Copyright (c) 2013 Yan Rabovik. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ROUSerialQueueTimer : NSObject
/**
 @param queue The queue where the target selector will be performed.
 It MUST be a serial queue. The queue is retained.
 @param leeway The amount of time, in seconds, that the system can defer the timer for improved system performance or power consumption
 @note Timer is intentionally not thread-safe and its methods should be called only from
 the queue it is created with.
 */
+(id)scheduledTimerWithQueue:(dispatch_queue_t)queue
                      target:(id)target
                    selector:(SEL)selector
                timeInterval:(NSTimeInterval)timeInterval
                      leeway:(NSTimeInterval)leeway;
-(void)fire;
/**
 @discussion You typically use this method to adjust the firing time of a repeating timer. For example, you could use it in situations where you want to repeat an action multiple times in the future, but at irregular time intervals. Adjusting the firing time of a single timer would likely incur less expense than creating multiple timer objects and then destroying them.
 @param fireDate The new date at which to fire the receiver. If the new date is in the past, this method sets the fire time to the current time.
 */
-(void)setFireDate:(NSDate *)fireDate;
-(void)invalidate;
-(NSDate *)lastFireDate;

@end
