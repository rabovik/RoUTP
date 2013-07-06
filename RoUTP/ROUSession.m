//
//  ROUSession.m
//  RoUTPTests
//
//  Created by Yan Rabovik on 27.06.13.
//  Copyright (c) 2013 Yan Rabovik. All rights reserved.
//

#import "ROUSession.h"
#import "ROUSession_Private.h"

#if !__has_feature(objc_arc)
#error This code needs ARC. Use compiler option -fobjc-arc
#endif

@implementation ROUSession{
}

#pragma mark Init
-(id)init{
    self = [super init];
    if (nil == self) return nil;
    
	_sndNextTSN = 1;
    _rcvNextTSN = 1;
    _rcvDataChunks = [NSMutableDictionary dictionaryWithCapacity:50];
    _rcvDataChunkIndexSet = [NSMutableIndexSet indexSet];
    _sndDataChunks = [NSMutableDictionary dictionaryWithCapacity:50];
    _sndDataChunkIndexSet = [NSMutableIndexSet indexSet];
    
    _queue = dispatch_queue_create("com.rabovik.routp.session",NULL);
    
    _rcvAckTimerInterval = ROU_RCV_ACK_TIMER_INTERVAL;
    _rcvAckTimerDelayOnMissed = ROU_RCV_ACK_TIMER_DELAY_ON_MISSED;
    _sndResendTimeout = ROU_SND_RESEND_TIMEOUT;
    
	return self;
}

-(void)dealloc{
    rou_dispatch_release(_queue);
    if (nil != _delegateQueue) {
        rou_dispatch_release(_delegateQueue);
    }
}

#pragma mark Main API
-(void)start{
    dispatch_async(self.queue, ^{
        [self scheduleAckTimer];
    });
}

#pragma mark └ Input data
-(void)sendData:(NSData *)data{
    dispatch_async(self.queue, ^{
        [self scheduleAckTimer];
        [self input_sendData:data];
    });
}

-(void)receiveData:(NSData *)data{
    dispatch_async(self.queue, ^{
        [self input_receiveData:data];
    });
}

#pragma mark └ Delegate
-(void)setDelegate:(id<ROUSessionDelegate>)delegate{
    [self setDelegate:delegate queue:nil];
}

-(void)setDelegate:(id<ROUSessionDelegate>)delegate queue:(dispatch_queue_t)queue{
    dispatch_async(self.queue, ^{
        dispatch_queue_t delegateQueue = queue;
        if (nil == queue) {
            delegateQueue = dispatch_get_main_queue();
        }
        rou_dispatch_retain(delegateQueue);
        if (nil != _delegateQueue) {
            rou_dispatch_release(_delegateQueue);
        }
        _delegateQueue = delegateQueue;
        _delegate = delegate;
    });
}

-(void)sendChunkToTransport:(ROUChunk *)chunk{
    if (self.delegate) {
        dispatch_async(self.delegateQueue, ^{
            [self.delegate session:self preparedDataForSending:chunk.encodedChunk];
        });
    }
}

-(void)informDelegateOnReceivedChunk:(ROUDataChunk *)chunk{
    if (self.delegate) {
        dispatch_async(self.delegateQueue, ^{
            [self.delegate session:self receivedData:chunk.data];
        });
    }
}

#pragma mark Sending
-(void)input_sendData:(NSData *)data{
    if (UINT32_MAX == _sndNextTSN) {
        ROUThrow(@"RoUTP currently supports only sessions no longer than %lu packets.",
                 NSUIntegerMax);
    }
    uint32_t tsn = _sndNextTSN++;
    ROUSndDataChunk *chunk = [ROUSndDataChunk chunkWithData:data TSN:tsn];

    [self addSndDataChunk:chunk];
    chunk.lastSendDate = [NSDate date];
    [self sendChunkToTransport:chunk];
}

-(void)processAckChunk:(ROUAckChunk *)ackChunk{
    [self removeSndDataChunksUpTo:ackChunk.tsn];
    [self removeSndDataChunksAtIndexes:ackChunk.segmentsIndexSet];
    
    NSMutableArray *chunksToResend = [NSMutableArray array];
    NSDate *nowDate = [NSDate date];
    [self.sndDataChunkIndexSet enumerateIndexesUsingBlock:^(NSUInteger tsn, BOOL *stop){
        ROUSndDataChunk *sndChunk = self.sndDataChunks[@(tsn)];
        // resend all missed which were net present earlier
        if ([ackChunk.missedIndexSet containsIndex:tsn] && 0 == sndChunk.resendCount) {
            [chunksToResend addObject:sndChunk];
            return;
        }
        // resend all older than sndResendTimeout
        if ([nowDate timeIntervalSinceDate:sndChunk.lastSendDate]
            > self.sndResendTimeout)
        {
            [chunksToResend addObject:sndChunk];
            return;
        }
    }];
    
    for (ROUSndDataChunk *chunk in chunksToResend) {
        chunk.resendCount = chunk.resendCount + 1;
        chunk.lastSendDate = [NSDate date];
        // todo: send a group of chunks in one packet?
        [self sendChunkToTransport:chunk];
    }
}

-(void)addSndDataChunk:(ROUSndDataChunk *)chunk{
    self.sndDataChunks[@(chunk.tsn)] = chunk;
    [self.sndDataChunkIndexSet addIndex:chunk.tsn];
}

-(void)removeSndDataChunksUpTo:(uint32_t)beforeTSN{
    if (self.sndDataChunkIndexSet.count == 0) {
        return;
    }
    uint32_t firstIndex = self.sndDataChunkIndexSet.firstIndex;
    if (beforeTSN < firstIndex) return;
    NSRange range = NSMakeRange(firstIndex, beforeTSN - firstIndex + 1);
    [self.sndDataChunkIndexSet
     enumerateIndexesInRange:range
     options:0
     usingBlock:^(NSUInteger idx, BOOL *stop) {
         [self.sndDataChunks removeObjectForKey:@(idx)];
     }];
    [self.sndDataChunkIndexSet removeIndexesInRange:range];
}

-(void)removeSndDataChunksAtIndexes:(NSIndexSet *)indexes{
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [self.sndDataChunks removeObjectForKey:@(idx)];
    }];
    [self.sndDataChunkIndexSet removeIndexes:indexes];
}

#pragma mark Receiving
-(void)input_receiveData:(NSData *)data{
    NSUInteger packetLength = data.length;
    NSUInteger currentPosition = 0;
    while (currentPosition + 4 <= packetLength) {
        NSAssert(4 == sizeof(ROUChunkHeader), @"ROUChunkHeader size should be 4");
        ROUChunkHeader header;
        [data getBytes:&header range:NSMakeRange(currentPosition, 4)];
        if (currentPosition + header.length > packetLength) {
            ROUThrow(@"Incorrect chunk length");
        }
        NSData *encodedChunk =
            [data subdataWithRange:NSMakeRange(currentPosition, header.length)];
        switch (header.type) {
            case ROUChunkTypeData:
                [self processDataChunk:[ROUDataChunk chunkWithEncodedChunk:encodedChunk]];
                break;
            case ROUCHunkTypeAck:
                [self processAckChunk:[ROUAckChunk chunkWithEncodedChunk:encodedChunk]];
                break;
            default:
                break;
        }
        currentPosition += header.length;
    }
}

-(void)processDataChunk:(ROUDataChunk *)chunk{
    if (chunk.tsn == _rcvNextTSN) {
        ++_rcvNextTSN;
        [self informDelegateOnReceivedChunk:chunk];
        // check if stored chunks are now ready
        if (self.rcvDataChunkIndexSet.count > 0 &&
            self.rcvDataChunkIndexSet.firstIndex == _rcvNextTSN)
        {
            __block NSRange readyChunksRange;
            [self.rcvDataChunkIndexSet
             enumerateRangesUsingBlock:^(NSRange range, BOOL *stop)
            {
                *stop = YES;
                readyChunksRange = range;
            }];
            _rcvNextTSN += readyChunksRange.length;
            for (uint32_t tsn = readyChunksRange.location;
                 tsn<_rcvNextTSN;
                 ++tsn)
            {
                ROUDataChunk *chunk = self.rcvDataChunks[@(tsn)];
                [self informDelegateOnReceivedChunk:chunk];
            }
            [self removeRcvDataChunksInRange:readyChunksRange];
        }
    }else if (chunk.tsn > _rcvNextTSN){
        [self addRcvDataChunk:chunk];
        if (self.rcvHasMissedDataChunks) {
            if (!self.rcvMissedPacketsFoundAfterLastPacket) {
                self.rcvAckTimer.fireDate =
                    [NSDate
                     dateWithTimeIntervalSinceNow:ROU_RCV_ACK_TIMER_DELAY_ON_MISSED];
            }
            self.rcvMissedPacketsFoundAfterLastPacket = YES;
        }else{
            if (self.rcvMissedPacketsFoundAfterLastPacket) {
                NSTimeInterval interval = ROU_RCV_ACK_TIMER_INTERVAL;
                if (self.rcvAckTimer.lastFireDate != nil) {
                    interval -= [[NSDate date]
                                 timeIntervalSinceDate:self.rcvAckTimer.lastFireDate];
                    if (interval < 0) interval = 0;
                }
                self.rcvAckTimer.fireDate = [NSDate
                                             dateWithTimeIntervalSinceNow:interval];
            }
            self.rcvMissedPacketsFoundAfterLastPacket = NO;
        }
    }
}

-(void)addRcvDataChunk:(ROUDataChunk *)chunk{
    self.rcvDataChunks[@(chunk.tsn)] = chunk;
    [self.rcvDataChunkIndexSet addIndex:chunk.tsn];
}

-(void)removeRcvDataChunksInRange:(NSRange)range{
    for (uint32_t tsn = range.location; tsn < range.location + range.length; ++tsn){
        [self.rcvDataChunks removeObjectForKey:@(tsn)];
    }
    [self.rcvDataChunkIndexSet removeIndexesInRange:range];
}

-(BOOL)rcvHasMissedDataChunks{
    NSUInteger count = self.rcvDataChunkIndexSet.count;
    if (0 == count) {
        return NO;
    }
    if (self.rcvDataChunkIndexSet.lastIndex - self.rcvDataChunkIndexSet.firstIndex
        == count - 1)
    {
        return NO;
    }
    return YES;
}

-(void)sendAck{
    ROUAckChunk *chunk = [ROUAckChunk chunkWithTSN:_rcvNextTSN-1];
    [self.rcvDataChunkIndexSet
     enumerateRangesInRange:
        NSMakeRange(_rcvNextTSN,
                    self.rcvDataChunkIndexSet.lastIndex-_rcvNextTSN+1)
     options:0
     usingBlock:^(NSRange range, BOOL *stop) {
         [chunk addSegmentWithRange:range];
     }];
    [self sendChunkToTransport:chunk];
}

#pragma mark └ Ack timer
-(void)scheduleAckTimer{
    if (nil != self.rcvAckTimer) {
        return;
    }
    self.rcvAckTimer = [ROUSerialQueueTimer
                        scheduledTimerWithQueue:self.queue
                        target:self
                        selector:@selector(ackTimerFired:)
                        timeInterval:self.rcvAckTimerInterval
                        leeway:self.rcvAckTimerInterval*0.005];
    [self.rcvAckTimer fire];
}

-(void)ackTimerFired:(ROUSerialQueueTimer *)timer{
    [self sendAck];
}

@end
