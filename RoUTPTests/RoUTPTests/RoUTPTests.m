//
//  RoUTPTests.m
//  RoUTPTests
//
//  Created by Yan Rabovik on 27.06.13.
//  Copyright (c) 2013 Yan Rabovik. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import "ROUSession.h"
#import "ROUSession_Private.h"

#ifndef RSNSMutableIndexSetMake
#ifndef RSNSIndexSetMake
#define RSNSMutableIndexSetMake(INDEXES...)                                              \
    ({                                                                                   \
        NSUInteger indexes[] = {INDEXES};                                                \
        NSUInteger count = sizeof(indexes)/sizeof(NSUInteger);                           \
        NSMutableIndexSet *mutableIndexSet = [NSMutableIndexSet indexSet];               \
        for (int i = 0; i < count; ++i){                                                 \
            [mutableIndexSet addIndex:indexes[i]];                                       \
        }                                                                                \
        mutableIndexSet;                                                                 \
    })                                                                                   
#define RSNSIndexSetMake(INDEXES...)                                                     \
    ({                                                                                   \
        [[NSIndexSet alloc] initWithIndexSet:RSNSMutableIndexSetMake(INDEXES)];          \
    })
#endif
#endif


@interface RoUTPTests : SenTestCase
@property (nonatomic,strong) NSMutableArray *testData;
@end

@implementation RoUTPTests{
}

#pragma mark - Setup
-(void)setUp{
    [super setUp];
    self.testData = [NSMutableArray arrayWithCapacity:10];
    for (int i = 0; i<= 9; ++i) {
        self.testData[i] = [[NSString stringWithFormat:@"%d",i]
                            dataUsingEncoding:NSUTF8StringEncoding];
    }
}

-(void)tearDown{
    self.testData = nil;
    [super tearDown];
}

#pragma mark - Encoding
-(void)testChunkEnum{
    STAssertTrue(ROUChunkTypeData == 0, @"");
    STAssertTrue(ROUCHunkTypeAck == 1, @"");
}

-(void)testDataChunkEncoding{
    NSData *testData = [@"123" dataUsingEncoding:NSUTF8StringEncoding];
    STAssertTrue(3 == testData.length, @"%u",testData.length);
    
    ROUDataChunk *chunk = [ROUDataChunk chunkWithData:testData TSN:169];
    STAssertTrue(8+3 == chunk.header.length, @"");
    
    STAssertTrue(ROUChunkTypeData == chunk.header.type, @"");
    STAssertTrue(0 == chunk.header.flags, @"");
    STAssertTrue(11 == chunk.header.length, @"");
    STAssertTrue(169 == chunk.tsn, @"");
    
    NSData *decodedData = chunk.data;
    STAssertTrue([decodedData isEqualToData:testData], @"");
}

-(void)testDataChunkLength{
    STAssertNoThrow([ROUDataChunk
                     chunkWithData:[NSMutableData dataWithLength:UINT16_MAX-8]
                     TSN:1],
                    @"");
    STAssertThrows([ROUDataChunk
                    chunkWithData:[NSMutableData dataWithLength:UINT16_MAX-7]
                    TSN:1],
                   @"");
}

-(void)testAckChunkEncoding{
    
    uint32_t testTSN = UINT16_MAX + UINT8_MAX + 169; // some big random number
    ROUAckSegmentShift
        testSeg1 = ROUAckSegmentShiftMake(2, 5), // 1 missing
        testSeg2 = ROUAckSegmentShiftMake(7, 10), // 6 missing
        testSeg3 = ROUAckSegmentShiftMake(12, 15); // 11 missing
    
    ROUAckChunk *chunk = [ROUAckChunk chunkWithTSN:testTSN];
    [chunk addSegmentFrom:testTSN+2 to:testTSN+5];
    [chunk addSegmentFrom:testTSN+7 to:testTSN+10];
    [chunk addSegmentFrom:testTSN+12 to:testTSN+15];
        
    ROUChunkHeader header;
    uint32_t tsn;
    ROUAckSegmentShift seg1, seg2 ,seg3;
    [chunk.encodedChunk getBytes:&header length:4];
    [chunk.encodedChunk getBytes:&tsn range:NSMakeRange(4, 4)];
    [chunk.encodedChunk getBytes:&seg1 range:NSMakeRange(8, 4)];
    [chunk.encodedChunk getBytes:&seg2 range:NSMakeRange(12, 4)];
    [chunk.encodedChunk getBytes:&seg3 range:NSMakeRange(16, 4)];
    
    STAssertTrue(header.type == ROUCHunkTypeAck, @"");
    STAssertTrue(header.flags == ROUAckFlagsHasSegments, @"");
    STAssertTrue(header.length == 20, @"");
    STAssertTrue(testTSN == tsn, @"");
    STAssertTrue(ROUAckSegmentShiftsEqual(testSeg1, seg1), @"");
    STAssertTrue(ROUAckSegmentShiftsEqual(testSeg2, seg2), @"");
    STAssertTrue(ROUAckSegmentShiftsEqual(testSeg3, seg3), @"");
    
    STAssertTrue(testTSN == chunk.tsn, @"");
    NSMutableIndexSet *testIndexSet = [NSMutableIndexSet indexSet];
    [testIndexSet addIndexesInRange:NSMakeRange(testTSN+2, 5 -2 +1)];
    [testIndexSet addIndexesInRange:NSMakeRange(testTSN+7, 10-7 +1)];
    [testIndexSet addIndexesInRange:NSMakeRange(testTSN+12,15-12+1)];
    STAssertTrue([testIndexSet isEqualToIndexSet:chunk.segmentsIndexSet],
                 @"\n%@\n%@",
                 testIndexSet,
                 chunk.segmentsIndexSet);
}

-(void)testAckChunkFlagsEncoding{
    ROUAckChunk *chunk = [ROUAckChunk chunkWithTSN:1];
    STAssertFalse(chunk.header.flags & ROUAckFlagsHasSegments, @"");
    [chunk addSegmentFrom:3 to:4];
    STAssertTrue(chunk.header.flags & ROUAckFlagsHasSegments, @"");    
}

-(void)testAckChunkDecoding{
    uint32_t testTSN = 169;
    ROUAckChunk *chunk = [ROUAckChunk chunkWithTSN:testTSN];
    [chunk addSegmentFrom:testTSN+2 to:testTSN+5];
    
    ROUAckChunk *decodedChunk = [ROUAckChunk chunkWithEncodedChunk:chunk.encodedChunk];
    STAssertTrue(decodedChunk.tsn == chunk.tsn, @"");
    STAssertTrue(decodedChunk.header.type == chunk.header.type, @"");
    STAssertTrue(decodedChunk.header.flags == chunk.header.flags, @"");
    STAssertTrue(decodedChunk.header.length == chunk.header.length, @"");
    STAssertTrue([decodedChunk.segmentsIndexSet
                  isEqualToIndexSet:chunk.segmentsIndexSet],
                 @"\n%@\n%@",
                 decodedChunk.segmentsIndexSet,
                 chunk.segmentsIndexSet);
}

-(void)testAckChunkMissedIndexSet{
    ROUAckChunk *chunk = [ROUAckChunk chunkWithTSN:10];
    [chunk addSegmentFrom:12 to:13];
    [chunk addSegmentFrom:15 to:19];
    [chunk addSegmentFrom:25 to:25];
    [chunk addSegmentFrom:27 to:30];
    NSMutableIndexSet *testIndexSet = RSNSMutableIndexSetMake(11,14,26);
    [testIndexSet addIndexesInRange:NSMakeRange(20, 5)];
    STAssertTrue([testIndexSet isEqualToIndexSet:chunk.missedIndexSet], @"");
}

#pragma mark - Sender
-(void)testDelegateCalledOnSending{
    ROUSession *session = [OCMockObject partialMockForObject:[ROUSession new]];
    
    [[(id)session expect] 
     sendChunkToTransport:[OCMArg checkWithBlock:^BOOL(ROUDataChunk *chunk) {
        STAssertTrue([chunk.data isEqualToData:self.testData[1]], @"");
        return YES;
    }]];
    
    [session input_sendData:self.testData[1]];
    
    [(id)session verify];
}

-(void)testSenderSavesSentMessagesAndResendsLost{
#define SEND_DATA_CHUNK(N)                                                               \
    [session input_sendData:self.testData[N]];

#define ASSERT_SND_DATA_CHUNK(N)                                                         \
    do{                                                                                  \
        ROUSndDataChunk *sndChunk = session.sndDataChunks[@(N)];                         \
        STAssertTrue([self.testData[N] isEqualToData:sndChunk.data],                     \
                     @"Chunk №%u failed.\n%@\n%@",                                       \
                     N,                                                                  \
                     self.testData[N],                                                   \
                     sndChunk);                                                          \
        STAssertTrue(N == sndChunk.tsn,@"TSNs not equal: %u != %u",N,sndChunk.tsn);      \
    } while (0)
    
#define ASSERT_SND_DATA_CHUNKS(NUMBERS...)                                               \
    do {                                                                                 \
        NSUInteger numbers[]= {NUMBERS};                                                 \
        NSUInteger count = sizeof(numbers)/sizeof(NSUInteger);                           \
        STAssertTrue(count == session.sndDataChunks.count,                               \
                     @"Chunks count failed. %u != %u",                                   \
                     count,                                                              \
                     session.sndDataChunks.count);                                       \
        for (NSUInteger i = 0; i < count; ++i) {                                         \
            NSUInteger tsn = numbers[i];                                                 \
            ASSERT_SND_DATA_CHUNK(tsn);                                                  \
        }                                                                                \
    } while (0)  
    
#define ASSERT_SND_DATA_CHUNK_INDEX_SET(INDEXES...)                                      \
    STAssertTrue([RSNSIndexSetMake(INDEXES)                                              \
                  isEqualToIndexSet:session.sndDataChunkIndexSet],                       \
                 @"\n%@\n%@",                                                            \
                 RSNSIndexSetMake(INDEXES),                                              \
                 session.sndDataChunkIndexSet)
    
#define ASSERT_SND_DATA(NUMBERS...)                                                      \
    ASSERT_SND_DATA_CHUNKS(NUMBERS);                                                     \
    ASSERT_SND_DATA_CHUNK_INDEX_SET(NUMBERS)
    
#define EXPECT_DATA_IN_TRANSPORT(NUMBERS...)                                             \
    do {                                                                                 \
        NSUInteger numbers[]= {NUMBERS};                                                 \
        NSUInteger count = sizeof(numbers)/sizeof(NSUInteger);                           \
        for (NSUInteger i = 0; i < count; ++i) {                                         \
            NSUInteger num = numbers[i];                                                 \
            ROUDataChunk *chunk= [ROUDataChunk chunkWithData:self.testData[num] TSN:num];\
            [[(id)session expect]                                                        \
             sendChunkToTransport:[OCMArg checkWithBlock:^BOOL(ROUDataChunk *arg){       \
                 return [arg.encodedChunk isEqualToData:chunk.encodedChunk];             \
             }]];                                                                        \
        }                                                                                \
    } while (0)
    
#define RECEIVE_ACK(N)                                                                   \
    [session input_receiveData:[[ROUAckChunk chunkWithTSN:N] encodedChunk]];
    
#define RECEIVE_SACK(N,SEGMENTS...)                                                      \
    do {                                                                                 \
        uint32_t segments[][2] = {SEGMENTS};                                             \
        NSUInteger count = sizeof(segments)/sizeof(uint32_t[2]);                         \
        ROUAckChunk *chunk = [ROUAckChunk chunkWithTSN:N];                               \
        for (NSUInteger i = 0; i< count; ++i) {                                          \
            [chunk addSegmentFrom:segments[i][0] to:segments[i][1]];                     \
        }                                                                                \
        [session input_receiveData:chunk.encodedChunk];                                  \
    } while (0);

    ROUSession *session = [OCMockObject partialMockForObject:[ROUSession new]];
    
    EXPECT_DATA_IN_TRANSPORT(1,2,3);
    
    STAssertTrue(session.sndNextTSN == 1, @"");
    ASSERT_SND_DATA();
    
    SEND_DATA_CHUNK(1);
    STAssertTrue(session.sndNextTSN == 2, @"");
    ASSERT_SND_DATA(1);
        
    SEND_DATA_CHUNK(2);
    STAssertTrue(session.sndNextTSN == 3, @"");
    ASSERT_SND_DATA(1,2);
    
    SEND_DATA_CHUNK(3);
    STAssertTrue(session.sndNextTSN == 4, @"");
    ASSERT_SND_DATA(1,2,3);
    
    [(id)session verify];
    
    RECEIVE_ACK(1);
    ASSERT_SND_DATA(2,3);
    SEND_DATA_CHUNK(4);
    SEND_DATA_CHUNK(5);
    SEND_DATA_CHUNK(6);
    ASSERT_SND_DATA(2,3,4,5,6);
    
    EXPECT_DATA_IN_TRANSPORT(2,4);
    RECEIVE_SACK(1,{3,3},{5,6});
    ASSERT_SND_DATA(2,4);
    [(id)session verify];
    
    RECEIVE_SACK(3,{5,6});
    ASSERT_SND_DATA(4);
    // do not resend again until now-lastSendDate > sndResendTimeout
    [(id)session verify];
    
    ROUSndDataChunk *sndChunk4 =  session.sndDataChunks[@(4)];
    sndChunk4.lastSendDate =
        [NSDate dateWithTimeIntervalSinceNow:-session.sndResendTimeout*1.05];
    EXPECT_DATA_IN_TRANSPORT(4); // timeout; must resend now
    RECEIVE_ACK(3);
    ASSERT_SND_DATA(4);
    [(id)session verify];
    
    RECEIVE_ACK(6);
    ASSERT_SND_DATA();
    [(id)session verify];

    
#undef SEND_DATA_CHUNK
#undef ASSERT_SND_DATA_CHUNK
#undef ASSERT_SND_DATA_CHUNKS
#undef ASSERT_SND_DATA_CHUNK_INDEX_SET
#undef ASSERT_SND_DATA
#undef EXPECT_DATA_IN_TRANSPORT
#undef RECEIVE_ACK
#undef RECEIVE_SACK
}

#pragma mark - Receiver

-(void)testDelegateCalledOnReceiving{
    ROUSession *session = [OCMockObject partialMockForObject:[ROUSession new]];
    
    NSData *testData = [@"123" dataUsingEncoding:NSUTF8StringEncoding];
    
    [[(id)session expect]
     informDelegateOnReceivedChunk:[OCMArg checkWithBlock:^BOOL(ROUDataChunk *chunk){
        STAssertTrue([chunk.data isEqualToData:testData], @"");
        return YES;
    }]];
    
    [session input_receiveData:((ROUDataChunk *)[ROUDataChunk
                                                 chunkWithData:testData
                                                 TSN:1]).encodedChunk];

    [(id)session verify];
}


-(void)testDelegateCalledMultipleTimesOnReceivingSeveralChunks{
    ROUSession *session = [OCMockObject partialMockForObject:[ROUSession new]];
        
    for (NSUInteger i = 1; i <= 3; ++i) {
        [[(id)session expect]
         informDelegateOnReceivedChunk:[OCMArg checkWithBlock:^BOOL(ROUDataChunk *chunk){
            STAssertTrue([chunk.data isEqualToData:self.testData[i]], @"");
            return YES;
        }]];
    }
    
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 1; i <= 3; ++i) {
        [data appendData:((ROUDataChunk *)[ROUDataChunk chunkWithData:self.testData[i]
                                                                  TSN:i]).encodedChunk];
    }
    
    [session input_receiveData:data];
    [(id)session verify];
}


-(void)testReceiverDataChunksQueue{
#define RECEIVE_DATA_CHUNK(N)                                                            \
    [session input_receiveData:((ROUDataChunk *)[ROUDataChunk                            \
                                                 chunkWithData:self.testData[N]          \
                                                 TSN:N]).encodedChunk]
    
#define ASSERT_RCV_DATA_CHUNK(N)                                                         \
    do {                                                                                 \
        ROUDataChunk *chunk = session.rcvDataChunks[@(N)];                               \
        STAssertTrue([self.testData[N] isEqualToData:chunk.data],                        \
                     @"Chunk №%u failed.\n%@\n%@",                                       \
                     N,                                                                  \
                     self.testData[N],                                                   \
                     chunk);                                                             \
        STAssertTrue(N == chunk.tsn,@"TSNs not equal: %u != %u",N,chunk.tsn);            \
    } while (0)

#define ASSERT_RCV_DATA_CHUNKS(NUMBERS...)                                               \
    do {                                                                                 \
        NSUInteger numbers[]= {NUMBERS};                                                 \
        NSUInteger count = sizeof(numbers)/sizeof(NSUInteger);                           \
        STAssertTrue(count == session.rcvDataChunks.count,                               \
                     @"Chunks count failed. %u != %u",                                   \
                     count,                                                              \
                     session.rcvDataChunks.count);                                       \
        for (NSUInteger i = 0; i < count; ++i) {                                         \
            NSUInteger tsn = numbers[i];                                                 \
            ASSERT_RCV_DATA_CHUNK(tsn);                                                  \
        }                                                                                \
    } while (0)                                                                            

#define ASSERT_RCV_DATA_CHUNK_INDEX_SET(INDEXES...)                                      \
    STAssertTrue([RSNSIndexSetMake(INDEXES)                                              \
                  isEqualToIndexSet:session.rcvDataChunkIndexSet],                       \
                 @"\n%@\n%@",                                                            \
                 RSNSIndexSetMake(INDEXES),                                              \
                 session.rcvDataChunkIndexSet)
    
#define ASSERT_RCV_DATA(NUMBERS...)                                                      \
    ASSERT_RCV_DATA_CHUNKS(NUMBERS);                                                     \
    ASSERT_RCV_DATA_CHUNK_INDEX_SET(NUMBERS)
    
    ROUSession *session = [OCMockObject partialMockForObject:[ROUSession new]];
        
    for (int i = 1; i<= 9; ++i) {
        [[(id)session expect]
         informDelegateOnReceivedChunk:[OCMArg checkWithBlock:^BOOL(ROUDataChunk *chunk) {
            STAssertTrue([chunk.data isEqualToData:self.testData[i]], @"");
            return YES;
        }]];
    }
    
    // Receiving chunks with gaps and incorrect order
    STAssertTrue(1 == session.rcvNextTSN, @"");
    ASSERT_RCV_DATA();
    
    RECEIVE_DATA_CHUNK(1);
    STAssertTrue(2 == session.rcvNextTSN, @"");
    ASSERT_RCV_DATA();
    STAssertFalse(session.rcvHasMissedDataChunks, @"");
    
    RECEIVE_DATA_CHUNK(3);
    STAssertTrue(2 == session.rcvNextTSN, @"");
    ASSERT_RCV_DATA(3);
    STAssertFalse(session.rcvHasMissedDataChunks, @"");
    
    RECEIVE_DATA_CHUNK(8);
    STAssertTrue(session.rcvHasMissedDataChunks, @"");
    ASSERT_RCV_DATA(3,8);
    
    RECEIVE_DATA_CHUNK(4);
    STAssertTrue(2 == session.rcvNextTSN, @"");
    ASSERT_RCV_DATA(3,4,8);
    STAssertTrue(session.rcvHasMissedDataChunks, @"");
    
    RECEIVE_DATA_CHUNK(6);
    RECEIVE_DATA_CHUNK(9);
    STAssertTrue(2 == session.rcvNextTSN, @"");
    ASSERT_RCV_DATA(3,4,6,8,9);        
    
    // filling gaps
    RECEIVE_DATA_CHUNK(2);
    STAssertTrue(5 == session.rcvNextTSN, @"");
    ASSERT_RCV_DATA(6,8,9);
    
    RECEIVE_DATA_CHUNK(7);
    STAssertTrue(5 == session.rcvNextTSN, @"");
    ASSERT_RCV_DATA(6,7,8,9);
    
    RECEIVE_DATA_CHUNK(5);
    STAssertTrue(10 == session.rcvNextTSN, @"");
    ASSERT_RCV_DATA();
    
    [(id)session verify];
    
#undef RECEIVE_DATA_CHUNK
#undef ASSERT_RCV_DATA_CHUNK
#undef ASSERT_RCV_DATA_CHUNKS
#undef ASSERT_RCV_DATA_CHUNK_INDEX_SET
#undef ASSERT_RCV_DATA
}

-(void)testSendAck{
#define RECEIVE_DATA_CHUNK(N)                                                            \
    [session input_receiveData:((ROUDataChunk *)[ROUDataChunk                            \
                                           chunkWithData:self.testData[N]                \
                                           TSN:N]).encodedChunk]

#define EXPECT_SACK_IN_TRANSPORT(N,SEGMENTS...)                                          \
    do {                                                                                 \
        uint32_t segments[][2] = {SEGMENTS};                                             \
        NSUInteger count = sizeof(segments)/sizeof(uint32_t[2]);                         \
        ROUAckChunk *chunk = [ROUAckChunk chunkWithTSN:N];                               \
        for (NSUInteger i = 0; i< count; ++i) {                                          \
            [chunk addSegmentFrom:segments[i][0] to:segments[i][1]];                     \
        }                                                                                \
        [[(id)session expect]                                                            \
        sendChunkToTransport:[OCMArg checkWithBlock:^BOOL(ROUChunk *arg){                \
            STAssertTrue([arg.encodedChunk isEqualToData:chunk.encodedChunk],@"");       \
            return YES;                                                                  \
        }]];                                                                             \
    } while (0)

    ROUSession *session = [OCMockObject partialMockForObject:[ROUSession new]];
    
    RECEIVE_DATA_CHUNK(1);
    RECEIVE_DATA_CHUNK(3);
    RECEIVE_DATA_CHUNK(4);
    RECEIVE_DATA_CHUNK(7);
    
    EXPECT_SACK_IN_TRANSPORT(1,{3,4},{7,7});

    [session sendAck];
    
    [(id)session verify];

#undef RECEIVE_DATA_CHUNK
}

@end
