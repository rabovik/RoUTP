//
//  ROUSerialQueueTimer.m
//  RoUTPTests
//
//  Created by Yan Rabovik on 02.07.13.
//  Copyright (c) 2013 Yan Rabovik. All rights reserved.
//

#import "ROUSerialQueueTimer.h"
#import "ROUPrivate.h"

#if !__has_feature(objc_arc)
#error This code needs ARC. Use compiler option -fobjc-arc
#endif

@interface ROUSerialQueueTimer ()
@property (nonatomic,rou_dispatch_property_qualifier) dispatch_queue_t queue;
@property (nonatomic,weak) id target;
@property (nonatomic) SEL selector;
@property (nonatomic) NSTimeInterval timeInterval;
@property (nonatomic) NSTimeInterval leeway;
@property (nonatomic,rou_dispatch_property_qualifier) dispatch_source_t timer;
@property (nonatomic) NSDate *lastFireDate;
@end

@implementation ROUSerialQueueTimer

+(id)scheduledTimerWithQueue:(dispatch_queue_t)queue
                      target:(id)target
                    selector:(SEL)selector
                timeInterval:(NSTimeInterval)timeInterval
                      leeway:(NSTimeInterval)leeway
{
    NSParameterAssert(queue);
    NSParameterAssert(target);
    NSParameterAssert(selector);
    
    ROUSerialQueueTimer *timer = [ROUSerialQueueTimer new];
    
    rou_dispatch_retain(queue);
    timer.queue = queue;
    timer.target = target;
    timer.selector = selector;
    timer.timeInterval = timeInterval;
    timer.leeway = leeway;
    
    timer.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                         0,
                                         0,
                                         queue);
    
    ROUSerialQueueTimer *__weak weakTimer = timer;
    dispatch_source_set_event_handler(timer.timer, ^{
        [weakTimer timerFired];
    });
    
    [timer scheduleWithInterval:timeInterval leeway:leeway start:timeInterval];
    
    dispatch_resume(timer.timer);
    
    return timer;
}

-(void)dealloc{
    [self invalidate];
    rou_dispatch_release(_queue);
}

-(void)scheduleWithInterval:(NSTimeInterval)interval
                     leeway:(NSTimeInterval)leeway
                      start:(NSTimeInterval)start
{
    uint64_t intervalInNanoseconds = (uint64_t)(interval * NSEC_PER_SEC);
    uint64_t leewayInNanoseconds = (uint64_t)(leeway * NSEC_PER_SEC);
    uint64_t startInNanoSeconds = (uint64_t)(start * NSEC_PER_SEC);
    dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW,startInNanoSeconds);
    dispatch_source_set_timer(self.timer,
                              startTime,
                              (uint64_t)intervalInNanoseconds,
                              leewayInNanoseconds);
}

-(void)timerFired{
    self.lastFireDate = [NSDate date];
    id target = self.target;
    if (target){
        NSMethodSignature *signature = [target
                                        methodSignatureForSelector:self.selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:target];
        [invocation setSelector:self.selector];
        [invocation setArgument:(void *)(&self) atIndex:2];
        [invocation invoke];
    }else{
        [self invalidate];
    }
}

-(void)fire{
    [self timerFired];
}

-(void)setFireDate:(NSDate *)fireDate{
    [self scheduleWithInterval:self.timeInterval
                        leeway:self.leeway
                         start:[fireDate timeIntervalSinceNow]];
}

-(void)invalidate{
    if (self.timer){
        dispatch_source_cancel(self.timer);
        rou_dispatch_release(self.timer);
        self.timer = nil;
    }
}

@end
