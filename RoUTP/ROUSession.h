//
//  ROUSession.h
//  RoUTPTests
//
//  Created by Yan Rabovik on 27.06.13.
//  Copyright (c) 2013 Yan Rabovik. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ROUSession;

@protocol ROUSessionDelegate <NSObject>
-(void)session:(ROUSession *)session receivedData:(NSData *)data;
-(void)session:(ROUSession *)session preparedDataForSending:(NSData *)data;
@end

@interface ROUSession : NSObject
/**
 @discussion Session automatically starts on first data sent. Use this method to start
 session earlier.
 */
-(void)start;
-(void)sendData:(NSData *)data;
-(void)receiveData:(NSData *)data;
-(void)setDelegate:(id<ROUSessionDelegate>)delegate;
/**
 @queue The queue where the delegate methods will be dispatched.
 The queue is retained by session.
 If no queue specified then dispatch_get_main_queue() will be used.
 */
-(void)setDelegate:(id<ROUSessionDelegate>)delegate
             queue:(dispatch_queue_t)queue;
@end
