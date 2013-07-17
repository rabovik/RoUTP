# Reliable-over-Unreliable Transport Protocol

**RoUTP** is an Objective-C implementation of a simple _Reliable-over-Unreliable Transport Protocol_. Its primary goal is a workaround for _«GKMatch GKMatchSendDataReliable packet loss bug»_ in Apple Game Center (see [SO question][SO] & [confirming example][GKMatchPacketLostExample]). But generally it may be used over any other unreliable protocol.

## How it works
RoUTP acts as an additional transport layer between your app and unreliable transport. It saves all sent messages until acknowledgement for each received, resends lost and buffers received messages in case of broken sequence. Technically the sender numbers all sent messages and the receiver regularly sends positive [selective acknowledgments][SACK].

## Integration
Here is an example of using RoUTP in 2-player Game Center game.
Suppose the code looks like

```objective-c
@interface MyController : UIViewController <GKMatchDelegate>
@property (nonatomic,strong) GKMatch *gkMatch;
@end

@implementation MyController
-(void)sendData:(NSData *)data{
    NSError *error;
    [self.gkMatch sendDataToAllPlayers:data
                          withDataMode:GKMatchSendDataReliable
                                 error:&error];
    // …
}
-(void)match:(GKMatch *)match didReceiveData:(NSData *)data fromPlayer:(NSString *)playerID{
    [self doSomethingWithReceivedData:data];
}
@end
```

Let's add RoUTP

```objective-c
// 1. Import ROUSession.h header
#import "ROUSession.h"
@interface MyController : UIViewController <GKMatchDelegate,
					    ROUSessionDelegate> // 2. implement its delegate
@property (nonatomic,strong) GKMatch *gkMatch;
@property (nonatomic,strong) ROUSession *rouSession; // 3. add ROUSession property
@end

@implementation MyController
-(void)someMethod{
    // 4. Make a ROUSession instance
    self.rouSession = [ROUSession new];
}
-(void)sendData:(NSData *)data{
    // 5. Send data to ROUSession instead of GKMatch
    [self.rouSession sendData:data];
}
-(void)match:(GKMatch *)match didReceiveData:(NSData *)data fromPlayer:(NSString *)playerID{
    // 6. Send data from GKMatch to ROUSession
    [self.rouSession receiveData:data];
}
-(void)session:(ROUSession *)session preparedDataForSending:(NSData *)data{
    // 7. Send prepared data from ROUSession to GKMatch
    NSError *error;
    [self.gkMatch sendDataToAllPlayers:data
                          withDataMode:GKMatchSendDataUnreliable // we can use unreliable mode now
                                 error:&error];
    // …    
}
-(void)session:(ROUSession *)session receivedData:(NSData *)data{
    // 8. Process ready data from ROUSession
    [self doSomethingWithReceivedData:data];
}
@end
```

## Requirements
* iOS 5.0 and later
* ARC

## License
MIT License.

[SO]: http://stackoverflow.com/q/16987880/441735
[GKMatchPacketLostExample]: https://github.com/rabovik/GKMatchPacketLostExample
[SACK]: http://en.wikipedia.org/wiki/Retransmission_(data_networks)
