#import <SenTestingKit/SenTestingKit.h>
#import "CCWeakMockProxy.h"
#import "ROUSession.h"
#import "ROUSession_Private.h"

#define K_SESSION_BOOST 30.

@interface ROUTestFastSession : ROUSession
@end

@implementation ROUTestFastSession
#pragma mark - Init
-(id)init{
    self = [super init];
    if (nil == self) return nil;
    
	self.rcvAckTimerInterval = self.rcvAckTimerInterval / K_SESSION_BOOST;
    self.rcvAckTimerDelayOnMissed = self.rcvAckTimerDelayOnMissed / K_SESSION_BOOST;
    self.sndResendTimeout = self.sndResendTimeout / K_SESSION_BOOST;
    
	return self;
}
@end

@interface RoUTPAsyncTests : SenTestCase
@end

@implementation RoUTPAsyncTests{
}

#pragma mark - Setup
-(void)setUp{
    [super setUp];
}

-(void)tearDown{
    [super tearDown];
}

#pragma mark - Async test
static BOOL done = NO;
static dispatch_block_t doneHandler = ^{
    if ([NSThread isMainThread]){
        done = YES;
    }else{
        dispatch_async(dispatch_get_main_queue(), ^{
            done = YES;
        });
    }
};

- (void)waitForCompletion:(NSTimeInterval)timeoutSecs{
    done = NO;
    NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:timeoutSecs];
    do{
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:timeoutDate];
        if ([timeoutDate timeIntervalSinceNow] < 0.0){
            STFail(@"TimeOut");
            break;
        }
    }
    while (!done);
}

-(void)testAsync{
    __block int flag = 0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.001 * NSEC_PER_SEC),
                   dispatch_get_main_queue(),
                   ^(void){
                       flag = 1;
                       doneHandler();
                   });
    [self waitForCompletion:0.02];
    STAssertTrue(1 == flag, @"Async test failed");
    
    flag = 0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.001 * NSEC_PER_SEC),
                   dispatch_queue_create(NULL, NULL),
                   ^(void){
                       flag = 1;
                       doneHandler();
                   });
    [self waitForCompletion:0.02];
    STAssertTrue(1 == flag, @"Async test failed");
}

#pragma mark - Queue test
-(void)testDelegateCalledOnMainQueueOnSending{
    ROUSession *session = [ROUSession new];
    id delegate = [CCWeakMockProxy mockForProtocol:@protocol(ROUSessionDelegate)];
    session.delegate = delegate;
    
    BOOL(^checkBlock)(id) = ^BOOL(NSData *data){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.001 * NSEC_PER_SEC),
                       dispatch_get_main_queue(),
                       doneHandler);
        if (![NSThread isMainThread]) {
            STFail(@"Delegate must be called on main thread.");
        }
        return YES;
    };
    
    [[delegate expect] session:session
        preparedDataForSending:OCMOCK_ANY]; // start Ack
    [[delegate expect] session:session
        preparedDataForSending:[OCMArg checkWithBlock:checkBlock]];
    
    [session sendData:[@"123" dataUsingEncoding:NSUTF8StringEncoding]];
    
    [self waitForCompletion:0.02];
    
    [delegate verify];
}

-(void)testDelegateCalledOnSpecificQueueOnSending{
    ROUSession *session = [ROUSession new];
    dispatch_queue_t specificQueue =
        dispatch_queue_create("com.rabovik.routp.testQueue", NULL);
    static int queueNameKey;
    NSString *queueName = @"com.rabovik.routp.testQueue";
    dispatch_queue_set_specific(specificQueue,
                                &queueNameKey,
                                (__bridge void *)queueName,
                                NULL);
    
    id delegate = [CCWeakMockProxy mockForProtocol:@protocol(ROUSessionDelegate)];
    [session setDelegate:delegate queue:specificQueue];
    
    BOOL(^checkBlock)(id) = ^BOOL(NSData *data){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.001 * NSEC_PER_SEC),
                       dispatch_get_main_queue(),
                       doneHandler);
        NSString *name = (__bridge NSString *)(dispatch_get_specific(&queueNameKey));
        if (![queueName isEqualToString:name]) {
            STFail(@"Delegate must be called on specified queue.");
        }
        return YES;
    };
    
    [[delegate expect] session:session
        preparedDataForSending:OCMOCK_ANY]; // start Ack
    [[delegate expect] session:session
        preparedDataForSending:[OCMArg checkWithBlock:checkBlock]];
    
    [session sendData:[@"123" dataUsingEncoding:NSUTF8StringEncoding]];
    
    [self waitForCompletion:0.02];
    
    [delegate verify];
    rou_dispatch_release(specificQueue);
}

#pragma mark - Timer tests
-(void)testStartSetsRepeatingTimer{
    ROUTestFastSession *session = [ROUTestFastSession new];
    
    id delegate = [CCWeakMockProxy mockForProtocol:@protocol(ROUSessionDelegate)];
    [session setDelegate:delegate];
    
    __block NSDate *lastFireDate = nil;
    __block int fireCount = 0;
    BOOL(^checkBlock)(id) = ^BOOL(NSData *data){
        ++fireCount;
        NSDate *currentDate = [NSDate date];
        if (fireCount >1) {
            NSTimeInterval interval = [currentDate timeIntervalSinceDate:lastFireDate];
            STAssertEqualsWithAccuracy(interval,
                                       session.rcvAckTimerInterval,
                                       session.rcvAckTimerInterval*0.15,
                                       @"");
        }
        if (fireCount == 3) {
            doneHandler();
        }
        lastFireDate = currentDate;
        return YES;
    };
    
    [[delegate expect] session:session
        preparedDataForSending:[OCMArg checkWithBlock:checkBlock]];
    [[delegate expect] session:session
        preparedDataForSending:[OCMArg checkWithBlock:checkBlock]];
    [[delegate expect] session:session
        preparedDataForSending:[OCMArg checkWithBlock:checkBlock]];

    [session start];
    
    [self waitForCompletion:session.rcvAckTimerInterval *2.1];
    
    [delegate verify];
}

#pragma mark - Test Memory Leak

-(void)testSessionIsFinallyDeallocatedAfterRelease{
    @autoreleasepool {
        ROUSession *session = [ROUSession new];
        __weak ROUSession *weakSession = session;
        [session start];
        // session schedules some work on its private queue, ...
        dispatch_queue_t queue = session.queue;
        dispatch_async(queue, ^{
            // ... which should be done here, ...
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(0.001 * NSEC_PER_SEC)),
                           queue, ^{
                               // ... so here session should be finally deallocated.
                               STAssertNil(weakSession, @"");
                               doneHandler();
            });
        });
    }
    [self waitForCompletion:0.02];
}

@end
