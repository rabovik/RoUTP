//
//  ROUDataTypes.m
//  RoUTPTests
//
//  Created by Yan Rabovik on 30.06.13.
//  Copyright (c) 2013 Yan Rabovik. All rights reserved.
//

#import "ROUDataTypes.h"
#import "ROUPrivate.h"

#if !__has_feature(objc_arc)
#error This code needs ARC. Use compiler option -fobjc-arc
#endif

#pragma mark - Structures -
ROUChunkHeader ROUChunkHeaderMake(ROUChunkType type, uint8_t flags, uint16_t length){
    ROUChunkHeader header;
    header.type = type;
    header.flags = flags;
    header.length = length;
    return header;
}

ROUChunkHeader ROUChunkHeaderAddFlag(ROUChunkHeader header, uint8_t flag){
    ROUChunkHeader newHeader = header;
    newHeader.flags = header.flags | flag;
    return newHeader;
}

ROUAckSegmentShift ROUAckSegmentShiftMake(uint16_t start, uint16_t end){
    ROUAckSegmentShift segment;
    segment.start = start;
    segment.end = end;
    return segment;
}

bool ROUAckSegmentShiftsEqual(ROUAckSegmentShift segmentShift1,
                              ROUAckSegmentShift segmentShift2)
{
    return  segmentShift1.start == segmentShift2.start &&
            segmentShift1.end   == segmentShift2.end;
}

#pragma mark - Classes -
#pragma mark Common chunks
@interface ROUChunk (){
    @protected
    NSData *_encodedChunk;
}
@property (nonatomic,strong) NSData *encodedChunk;
@property (nonatomic,readwrite) ROUChunkHeader header;
@end

@implementation ROUChunk
+(id)chunkWithEncodedChunk:(NSData *)encodedChunk{
    ROUThrow(@"+[%@ %@] not implemented",
             NSStringFromClass(self),
             NSStringFromSelector(_cmd));
    return nil;
}
-(NSData *)encodedChunk{
    ROUThrow(@"-[%@ %@] not implemented",
             NSStringFromClass([self class]),
             NSStringFromSelector(_cmd));
    return nil;
}
@end

#pragma mark Data chunk
@interface ROUDataChunk ()
@property (nonatomic,readwrite) uint32_t tsn;
@property (nonatomic,strong) NSData *data;
@end

@implementation ROUDataChunk
+(id)chunkWithEncodedChunk:(NSData *)encodedChunk{
    if (encodedChunk.length <= 8) {
        ROUThrow(@"Encoded data chunk is too short");
    }
    ROUDataChunk *chunk = [self new];
    chunk.encodedChunk = encodedChunk;
    
    NSAssert(4 == sizeof(ROUChunkHeader), @"ROUChunkHeader size should be 4");
    ROUChunkHeader header;
    [encodedChunk getBytes:&header range:NSMakeRange(0, 4)];
    chunk.header = header;

    uint32_t tsn;
    [encodedChunk getBytes:&tsn range:NSMakeRange(4, 4)];
    chunk.tsn = tsn;
    
    return chunk;
}
+(id)chunkWithData:(NSData *)data TSN:(uint32_t)tsn{
    if (data.length > UINT16_MAX-8) {
        ROUThrow(@"Data in chunk may not be longer than %u bytes",UINT16_MAX-8);
    }
    ROUDataChunk *chunk = [self new];
    chunk.header = ROUChunkHeaderMake(ROUChunkTypeData, 0, data.length + 8);
    chunk.tsn = tsn;
    chunk.data = data;
    return chunk;
}
-(NSData *)encodedChunk{
    if (nil != self->_encodedChunk) {
        return _encodedChunk;
    }
    NSAssert(nil != self.data, @"");
    NSMutableData *chunk = [NSMutableData dataWithCapacity:8+self.data.length];
    ROUChunkHeader header = self.header;
    [chunk appendBytes:&header length:4];
    [chunk appendBytes:&_tsn length:4];
    [chunk appendData:_data];
    return chunk;
}
-(NSData *)data{
    if (nil != _data) {
        return _data;
    }
    NSAssert(nil != self.encodedChunk, @"");
    return [self.encodedChunk
            subdataWithRange:NSMakeRange(8, self.encodedChunk.length-8)];
}
@end

@implementation ROUSndDataChunk
@end

#pragma mark Ack chunk
@interface ROUAckChunk ()
@property (nonatomic,readwrite) uint32_t tsn;
@end

@implementation ROUAckChunk{
    NSMutableIndexSet *_segmentsIndexSet;
}

+(id)chunkWithTSN:(uint32_t)tsn{
    ROUAckChunk *chunk = [self new];
    chunk.tsn = tsn;
    
    return chunk;
}

+(id)chunkWithEncodedChunk:(NSData *)encodedChunk{
    if (encodedChunk.length < 8) {
        ROUThrow(@"Encoded ack chunk is too short");
    }
    ROUAckChunk *chunk = [self new];
    chunk.encodedChunk = encodedChunk;
    
    NSAssert(4 == sizeof(ROUChunkHeader), @"ROUChunkHeader size should be 4");
    ROUChunkHeader header;
    [encodedChunk getBytes:&header range:NSMakeRange(0, 4)];    
    
    uint32_t tsn;
    [encodedChunk getBytes:&tsn range:NSMakeRange(4, 4)];
    chunk.tsn = tsn;
    
    if (header.flags & ROUAckFlagsHasSegments) {
        NSUInteger currentPosition = 8;
        while (currentPosition + 4 <= header.length) {
            ROUAckSegmentShift segmentShift;
            [encodedChunk getBytes:&segmentShift range:NSMakeRange(currentPosition, 4)];
            NSRange range =
                NSMakeRange(tsn+segmentShift.start,
                            segmentShift.end - segmentShift.start + 1);
            [chunk->_segmentsIndexSet
                addIndexesInRange:range];
            currentPosition += 4;
        }
    }
    
    return chunk;
}

-(id)init{
    self = [super init];
    if (nil == self) return nil;
	_segmentsIndexSet = [NSMutableIndexSet indexSet];
	return self;
}

-(NSString *)description{
    return [NSString stringWithFormat:@"<%@ %p> header.type=%u header.flags=%u header.length=%u TSN=%u segments=%@ encodedChunk=%@",
            NSStringFromClass([self class]),
            self,
            self.header.type,
            self.header.flags,
            self.header.length,
            _tsn,
            _segmentsIndexSet,
            _encodedChunk];
}

-(ROUChunkHeader)header{
    ROUAckFlags flags = 0;
    __block NSUInteger segmentsCount = 0;
    if (_segmentsIndexSet.count > 0) {
        flags = flags | ROUAckFlagsHasSegments;
        [_segmentsIndexSet enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
            ++segmentsCount;
        }];
    }
    NSUInteger length = 8 + 4*segmentsCount;
    if (length > UINT16_MAX) {
        ROUThrow(@"Can not create header. Too many segments in ROUAckChunk.");
    }
    return ROUChunkHeaderMake(ROUCHunkTypeAck, flags, length);
}

-(void)addSegmentFrom:(uint32_t)fromTSN to:(uint32_t)toTSN{
    NSAssert(fromTSN > self.tsn + 1,
             @"tsn=%u fromTSN=%u toTSN=%u",
             self.tsn,
             fromTSN,
             toTSN);
    NSAssert(toTSN >= fromTSN,
             @"tsn=%u fromTSN=%u toTSN=%u",
             self.tsn,
             fromTSN,
             toTSN);
    [self addSegmentWithRange:NSMakeRange(fromTSN, toTSN-fromTSN+1)];
}

-(void)addSegmentWithRange:(NSRange)range{
    NSAssert(range.location > self.tsn + 1,
             @"tsn=%u %@",
             self.tsn,
             NSStringFromRange(range));
    NSAssert(range.length > 0,
             @"tsn=%u %@",
             self.tsn,
             NSStringFromRange(range));
    _encodedChunk = nil;
    [_segmentsIndexSet addIndexesInRange:range];
}


-(NSIndexSet *)segmentsIndexSet{
    return _segmentsIndexSet;
}

-(NSIndexSet *)missedIndexSet{
    if (_segmentsIndexSet.firstIndex <= self.tsn + 1) {
        ROUThrow(@"In ack chunkTSN should be lower than segments.\n%@",self);
    }
    NSMutableIndexSet *missed = [NSMutableIndexSet indexSet];
    __block NSUInteger start = self.tsn + 1;
    [_segmentsIndexSet enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        NSUInteger end = range.location - 1;
        [missed addIndexesInRange:NSMakeRange(start, end-start+1)];
        start = range.length + range.location;
    }];
    return missed;
}

-(NSData *)encodedChunk{
    if (nil != _encodedChunk) {
        return _encodedChunk;
    }
    ROUChunkHeader header = self.header;
    NSMutableData *encodedChunk = [NSMutableData dataWithCapacity:header.length];
    [encodedChunk appendBytes:&header length:4];
    [encodedChunk appendBytes:&_tsn length:4];
    NSAssert(4 == sizeof(ROUAckSegmentShift), @"ROUAckSegmentShift size should be 4");
    [_segmentsIndexSet enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        ROUAckSegmentShift segment =
            ROUAckSegmentShiftMake(range.location-_tsn,
                                   range.location-_tsn+range.length-1);
        [encodedChunk appendBytes:&segment length:4];
    }];
    return encodedChunk;
}

@end

#pragma mark - Categories -
@implementation NSValue (ROUAckSegmentShift)

+(NSValue *)rou_valueWithAckSegmentShift:(ROUAckSegmentShift)segment{
    return [NSValue valueWithBytes:&segment objCType:@encode(ROUAckSegmentShift)];
}

-(ROUAckSegmentShift)rou_ackSegmentShift{
    ROUAckSegmentShift segment;
    [self getValue:&segment];
    return segment;
}

@end
