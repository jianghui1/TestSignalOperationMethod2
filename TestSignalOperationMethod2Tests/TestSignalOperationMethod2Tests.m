//
//  TestSignalOperationMethod2Tests.m
//  TestSignalOperationMethod2Tests
//
//  Created by ys on 2018/8/5.
//  Copyright © 2018年 ys. All rights reserved.
//

#import <XCTest/XCTest.h>

#import <ReactiveCocoa.h>

@interface TestSignalOperationMethod2Tests : XCTestCase

@end

@implementation TestSignalOperationMethod2Tests

- (RACSignal *)syncSignal
{
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        for (int i = 0; i < 2; i++) {
            [subscriber sendNext:@(i)];
        }
        [subscriber sendCompleted];
        
        return nil;
    }];
}

- (RACSignal *)asyncSignal
{
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        
        [subscriber sendNext:@"start"];
        
        [[RACScheduler scheduler] afterDelay:2 schedule:^{
            [subscriber sendNext:@"end"];
            [subscriber sendCompleted];
        }];
        
        return nil;
    }];
}

- (RACSignal *)eagerlySignal1
{
    return [RACSubject startEagerlyWithScheduler:[RACScheduler mainThreadScheduler] block:^(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@"eagerly"];
        NSLog(@"1");
        [subscriber sendCompleted];
    }];
}

- (RACSignal *)eagerlySignal2
{
    return [RACSubject startEagerlyWithScheduler:[RACScheduler mainThreadScheduler] block:^(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@"eagerly"];
        NSLog(@"2");
        [subscriber sendCompleted];
    }];
}

- (RACSignal *)eagerlySignal3
{
    return [RACSubject startEagerlyWithScheduler:[RACScheduler mainThreadScheduler] block:^(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@"eagerly"];
        NSLog(@"3");
        [subscriber sendCompleted];
    }];
}



// 保证异步操作完成
- (void)ensureAsyncSignalCompleted
{
    [[RACSignal never] asynchronouslyWaitUntilCompleted:nil];
}

- (void)test_switchToLatest
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        for (int i = 0; i < 2; i++) {
            [subscriber sendNext:[self asyncSignal]];
        }
        [subscriber sendCompleted];
        
        return nil;
    }];
    [[signal
      switchToLatest]
     subscribeNext:^(id x) {
         NSLog(@"switchToLatest -- %@", x);
     }];
    
    [self ensureAsyncSignalCompleted];
    
    // 打印日志如下:
    /*
     2018-08-05 11:26:44.557265+0800 TestSignalOperationMethod2[94827:8279871] switchToLatest -- start
     2018-08-05 11:26:44.557661+0800 TestSignalOperationMethod2[94827:8279871] switchToLatest -- start
     2018-08-05 11:26:46.572932+0800 TestSignalOperationMethod2[94827:8279871] switchToLatest -- end
     */
}

- (void)test_switch
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@"sync"];
        [subscriber sendNext:@"async"];
        [subscriber sendNext:@"none"];
        [subscriber sendCompleted];
        
        return nil;
    }];
    
    NSDictionary *cases = @{
                            @"sync" : [self syncSignal],
                            @"async" : [self asyncSignal],
                            };
    
    RACSignal *defaultSignal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@"default"];
        [subscriber sendCompleted];
        
        return nil;
    }];
    
    [[RACSignal switch:signal cases:cases default:defaultSignal]
     subscribeNext:^(id x) {
         NSLog(@"switch -- %@", x);
     }];
    
    [self ensureAsyncSignalCompleted];
    
    // 打印日志如下:
    /*
     2018-08-05 11:37:37.530631+0800 TestSignalOperationMethod2[95264:8312414] switch -- 0
     2018-08-05 11:37:37.530898+0800 TestSignalOperationMethod2[95264:8312414] switch -- 1
     2018-08-05 11:37:37.531460+0800 TestSignalOperationMethod2[95264:8312414] switch -- start
     2018-08-05 11:37:37.531865+0800 TestSignalOperationMethod2[95264:8312414] switch -- default
     */

}

- (void)test_if
{
    RACSignal *boolSignal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@(YES)];
        
        [[RACScheduler mainThreadScheduler] afterDelay:0.5 schedule:^{
            [subscriber sendNext:@(NO)];
            [subscriber sendCompleted];
        }];
        
        return nil;
    }];
    
    [[RACSignal if:boolSignal then:[self syncSignal] else:[self asyncSignal]]
     subscribeNext:^(id x) {
         NSLog(@"if -- %@", x);
     }];
    
    [self ensureAsyncSignalCompleted];
    
    // 打印日志
    /*
     2018-08-05 11:43:23.940426+0800 TestSignalOperationMethod2[95507:8330141] if -- 0
     2018-08-05 11:43:23.940634+0800 TestSignalOperationMethod2[95507:8330141] if -- 1
     2018-08-05 11:43:24.454039+0800 TestSignalOperationMethod2[95507:8330141] if -- start
     2018-08-05 11:43:26.457834+0800 TestSignalOperationMethod2[95507:8330141] if -- end
     */
}

- (void)test_first
{
    id x = [[self syncSignal] first];
    NSLog(@"first -- %@", x);
    
    // 打印日志
    /*
     2018-08-05 12:46:04.868054+0800 TestSignalOperationMethod2[97825:8511130] first -- 0
     */
}

- (void)test_firstOrDefault
{
    id x = [[self syncSignal] firstOrDefault:@"default"];
    id x1 = [[RACSignal empty] firstOrDefault:@"default"];
    NSLog(@"firstOrDefault -- %@", x);
    NSLog(@"firstOrDefault -- %@", x1);
    
    // 打印日志
    /*
     2018-08-05 12:48:53.383552+0800 TestSignalOperationMethod2[97950:8519788] firstOrDefault -- 0
     2018-08-05 12:48:53.383798+0800 TestSignalOperationMethod2[97950:8519788] firstOrDefault -- default
     */
}

- (void)test_firstOrDefault_success_error
{
    BOOL success;
    NSError *error;
    id x = [[self syncSignal] firstOrDefault:@"default" success:&success error:&error];
    
    NSLog(@"firstOrDefault_success_error -- %@", x);
    NSLog(@"suceesss - %d", success);
    NSLog(@"error - %@", error);
    
    // 打印日志
    /*
     2018-08-05 12:50:47.441003+0800 TestSignalOperationMethod2[98041:8526293] firstOrDefault_success_error -- 0
     2018-08-05 12:50:47.441209+0800 TestSignalOperationMethod2[98041:8526293] suceesss - 1
     2018-08-05 12:50:47.441397+0800 TestSignalOperationMethod2[98041:8526293] error - (null)
     */
}

- (void)test_waitUntilCompleted
{
    NSError *error;
    BOOL sussess = [[self syncSignal] waitUntilCompleted:&error];
    NSLog(@"waitUntilCompleted -- %d -- %@", sussess, error);
    
    // 打印日志
    /*
     2018-08-05 12:53:40.514999+0800 TestSignalOperationMethod2[98180:8534913] waitUntilCompleted -- 1 -- (null)
     */
}

- (void)test_defer
{
    [self eagerlySignal1];
    
    [RACSignal defer:^RACSignal *{
        return [self eagerlySignal2];
    }];
    
    [[RACSignal defer:^RACSignal *{
        return [self eagerlySignal3];
    }]
     subscribeNext:^(id x) {
         NSLog(@"defer -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 13:04:55.015092+0800 TestSignalOperationMethod2[98674:8569294] 1
     2018-08-05 13:04:55.016002+0800 TestSignalOperationMethod2[98674:8569294] 3
     2018-08-05 13:04:55.016539+0800 TestSignalOperationMethod2[98674:8569294] defer -- eagerly
     */
}

- (void)test_toArray
{
    NSArray *array = [[self asyncSignal] toArray];
    NSLog(@"toArray -- %@", array);
    
    // 打印日志
    /*
     2018-08-05 13:40:34.841292+0800 TestSignalOperationMethod2[1278:8683106] toArray -- (
     start,
     end
     )
     */
}

- (void)test_sequence
{
    NSArray *array = [[[self syncSignal] sequence]
     array];
    NSLog(@"sequence -- %@", array);
    
    // 打印日志
    /*
     2018-08-05 13:44:06.099832+0800 TestSignalOperationMethod2[1426:8693604] sequence -- (
     0,
     1
     )
     */
}

- (void)test_publish
{
    RACSignal *signal1 = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        NSLog(@"signal1");
        [subscriber sendCompleted];
        
        return nil;
    }];
    
    RACSignal *signal2 = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        NSLog(@"signal2");
        [subscriber sendCompleted];
        
        return nil;
    }];
    
    [signal1 subscribeCompleted:^{
        
    }];
    [signal1 subscribeCompleted:^{
        
    }];
    
    RACMulticastConnection *connect = [signal2 publish];
    [connect.signal subscribeCompleted:^{
        
    }];
    [connect.signal subscribeCompleted:^{
        
    }];
    [connect connect];
    
    // 打印日志
    /*
     2018-08-05 13:54:05.225665+0800 TestSignalOperationMethod2[1870:8724037] signal1
     2018-08-05 13:54:05.225887+0800 TestSignalOperationMethod2[1870:8724037] signal1
     2018-08-05 13:54:05.226226+0800 TestSignalOperationMethod2[1870:8724037] signal2
     */
}

- (void)test_replay
{
    RACSignal *signal = [[self syncSignal] replay];
    [signal
     subscribeNext:^(id x) {
         NSLog(@"replay -- %@", x);
     }];

    // 打印日志
    /*
     2018-08-05 14:16:14.532877+0800 TestSignalOperationMethod2[2809:8792845] replay -- 0
     2018-08-05 14:16:14.533059+0800 TestSignalOperationMethod2[2809:8792845] replay -- 1
     */
}

- (void)test_replayLast
{
    RACSignal *signal = [[self syncSignal] replayLast];
    [signal subscribeNext:^(id x) {
        NSLog(@"replayLast -- %@", x);
    }];
    
    // 打印日志
    /*
     2018-08-05 14:20:37.502216+0800 TestSignalOperationMethod2[2994:8805833] replayLast -- 1
     */
}

- (void)test_replayLazily
{
    RACSignal *signal1 = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        for (int i = 0; i < 2; i++) {
            [subscriber sendNext:@(i)];
        }
        NSLog(@"signal1");
        [subscriber sendCompleted];
        
        return nil;
    }];
    
    RACSignal *signal2 = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        for (int i = 0; i < 2; i++) {
            [subscriber sendNext:@(i)];
        }
        NSLog(@"signal2");
        [subscriber sendCompleted];
        
        return nil;
    }];
    
    RACSignal *signal3 = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        for (int i = 0; i < 2; i++) {
            [subscriber sendNext:@(i)];
        }
        NSLog(@"signal3");
        [subscriber sendCompleted];
        
        return nil;
    }];
    
    [signal1 replayLazily];
    [signal2 replayLast];
    [[signal3 replayLazily]
     subscribeNext:^(id x) {
         NSLog(@"replayLazily -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 14:25:56.084932+0800 TestSignalOperationMethod2[3215:8821534] signal2
     2018-08-05 14:25:56.085287+0800 TestSignalOperationMethod2[3215:8821534] signal3
     2018-08-05 14:25:56.085583+0800 TestSignalOperationMethod2[3215:8821534] replayLazily -- 0
     2018-08-05 14:25:56.085695+0800 TestSignalOperationMethod2[3215:8821534] replayLazily -- 1
     */
}

- (void)test_timeout
{
    [[[self asyncSignal] timeout:1 onScheduler:[RACScheduler scheduler]]
     subscribeNext:^(id x) {
         NSLog(@"timeout -- %@", x);
     }];
    
    [self ensureAsyncSignalCompleted];
    
    // 打印日志
    /*
     2018-08-05 14:28:55.707857+0800 TestSignalOperationMethod2[3352:8830680] timeout -- start
     */
}

- (void)test_deliverOn
{
    [[[self syncSignal] deliverOn:[RACScheduler scheduler]]
     subscribeNext:^(id x) {
         NSLog(@"deliverOn -- %@", [RACScheduler currentScheduler]);
     }];
    
    // 打印日志
    /*
     2018-08-05 14:32:42.301185+0800 TestSignalOperationMethod2[3535:8842438] deliverOn -- <RACTargetQueueScheduler: 0x600000237a00> com.ReactiveCocoa.RACScheduler.backgroundScheduler
     2018-08-05 14:32:42.305680+0800 TestSignalOperationMethod2[3535:8842438] deliverOn -- <RACTargetQueueScheduler: 0x600000237a00> com.ReactiveCocoa.RACScheduler.backgroundScheduler
     */
}

- (void)test_subscribeOn
{
    [[[self syncSignal] subscribeOn:[RACScheduler scheduler]]
     subscribeNext:^(id x) {
         NSLog(@"subscribeOn -- %@", [RACScheduler currentScheduler]);
     }];
    
    // 打印日志
    /*
     2018-08-05 14:34:36.216687+0800 TestSignalOperationMethod2[3624:8848481] subscribeOn -- <RACTargetQueueScheduler: 0x600000430de0> com.ReactiveCocoa.RACScheduler.backgroundScheduler
     Test Case '-[TestSignalOperationMethod2Tests test_subscribeOn]' passed (0.003 seconds).
     2018-08-05 14:34:36.216860+0800 TestSignalOperationMethod2[3624:8848481] subscribeOn -- <RACTargetQueueScheduler: 0x600000430de0> com.ReactiveCocoa.RACScheduler.backgroundScheduler
     */
}

- (void)test_deliverOnMainThread
{
    [[[[[self syncSignal] deliverOn:[RACScheduler scheduler]]
      map:^id(id value) {
          NSLog(@"value -- %@", [RACScheduler currentScheduler]);
          return value;
      }]
     deliverOnMainThread]
     subscribeNext:^(id x) {
         NSLog(@"deliverOnMainThread -- %@", [RACScheduler currentScheduler]);
     }];
    
    // 打印日志
    /*
     2018-08-05 14:37:36.170316+0800 TestSignalOperationMethod2[3755:8857343] value -- <RACTargetQueueScheduler: 0x6000002312a0> com.ReactiveCocoa.RACScheduler.backgroundScheduler
     2018-08-05 14:37:36.171484+0800 TestSignalOperationMethod2[3755:8857343] value -- <RACTargetQueueScheduler: 0x6000002312a0> com.ReactiveCocoa.RACScheduler.backgroundScheduler
     2018-08-05 14:37:36.178110+0800 TestSignalOperationMethod2[3755:8857274] deliverOnMainThread -- <RACTargetQueueScheduler: 0x600000231380> com.ReactiveCocoa.RACScheduler.mainThreadScheduler
     2018-08-05 14:37:36.178428+0800 TestSignalOperationMethod2[3755:8857274] deliverOnMainThread -- <RACTargetQueueScheduler: 0x600000231380> com.ReactiveCocoa.RACScheduler.mainThreadScheduler
     */
}

- (void)test_groupBy_transform
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        for (int i = 0; i < 2; i++) {
            [subscriber sendNext:@(i)];
        }
        [subscriber sendCompleted];
        
        return nil;
    }];
    
    id<NSCopying> (^keyBlock)(id object) = ^(NSNumber *number) {
        if ([number intValue] == 0) {
            return @"first";
        }
        else {
            return @"second";
        }
    };
    
    id (^transformBlock)(id object) = ^(NSNumber *number) {
        return @([number intValue] + 100);
    };
    
    [[[signal groupBy:keyBlock transform:transformBlock]
     flatten]
     subscribeNext:^(id x) {
         NSLog(@"groupBy -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 14:49:36.812818+0800 TestSignalOperationMethod2[4258:8892225] groupBy -- 100
     2018-08-05 14:49:36.813018+0800 TestSignalOperationMethod2[4258:8892225] groupBy -- 101
     */
}

- (void)test_groupBy
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        for (int i = 0; i < 2; i++) {
            [subscriber sendNext:@(i)];
        }
        [subscriber sendCompleted];
        
        return nil;
    }];
    
    id<NSCopying> (^keyBlock)(id object) = ^(NSNumber *number) {
        if ([number intValue] == 0) {
            return @"first";
        }
        else {
            return @"second";
        }
    };
    
    [[[signal groupBy:keyBlock]
      flatten]
     subscribeNext:^(id x) {
         NSLog(@"groupBy -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 14:51:45.975598+0800 TestSignalOperationMethod2[4359:8898907] groupBy -- 0
     2018-08-05 14:51:45.975807+0800 TestSignalOperationMethod2[4359:8898907] groupBy -- 1
     */
}

- (void)test_materialize
{
    [[[self syncSignal] materialize]
     subscribeNext:^(id x) {
         NSLog(@"materialize -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 14:53:48.391226+0800 TestSignalOperationMethod2[4462:8905168] materialize -- <RACEvent: 0x60000003b380>{ next = 0 }
     2018-08-05 14:53:48.391591+0800 TestSignalOperationMethod2[4462:8905168] materialize -- <RACEvent: 0x60000003b380>{ next = 1 }
     2018-08-05 14:53:48.391827+0800 TestSignalOperationMethod2[4462:8905168] materialize -- <RACEvent: 0x60000003b380>{ completed }
     */
}

- (void)test_any_
{
    [[[self syncSignal] any:^BOOL(NSNumber *number) {
        return [number intValue] == 1;
    }]
     subscribeNext:^(id x) {
         NSLog(@"any: -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 14:56:57.068424+0800 TestSignalOperationMethod2[4600:8914608] any: -- 1
     */
}

- (void)test_any
{
    [[[self syncSignal] any]
     subscribeNext:^(id x) {
         NSLog(@"any -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 14:58:16.748284+0800 TestSignalOperationMethod2[4668:8918957] any -- 1
     */
}

- (void)test_all
{
    [[[self syncSignal] all:^BOOL(id object) {
        return [object isKindOfClass:[NSNumber class]];
    }]
     subscribeNext:^(id x) {
         NSLog(@"all -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 15:00:51.292786+0800 TestSignalOperationMethod2[4791:8927077] all -- 1
     */
}

- (void)test_retry_
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        NSLog(@"signal");
        [subscriber sendError:nil];
        return nil;
    }];
    
    [[signal retry:2]
     subscribeNext:^(id x) {
         NSLog(@"retry -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 15:04:24.310577+0800 TestSignalOperationMethod2[4944:8937749] signal
     2018-08-05 15:04:24.311167+0800 TestSignalOperationMethod2[4944:8937749] signal
     */
}

- (void)test_retry
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        NSLog(@"signal");
        [subscriber sendError:nil];
        return nil;
    }];
    
    [[signal retry]
     subscribeNext:^(id x) {
         NSLog(@"retry -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 15:05:30.947823+0800 TestSignalOperationMethod2[5006:8941446] signal
     2018-08-05 15:05:30.948378+0800 TestSignalOperationMethod2[5006:8941446] signal
     2018-08-05 15:05:30.948854+0800 TestSignalOperationMethod2[5006:8941446] signal
     .......
     */
}

- (void)test_sampler
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:@(1)];
        
        [[RACScheduler scheduler] afterDelay:1.8 schedule:^{
            [subscriber sendNext:@(2)];
        }];
        
        return nil;
    }];
    
    RACSignal *sampler = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [[RACScheduler scheduler] afterDelay:1 schedule:^{
            [subscriber sendNext:@"first"];
        }];
        [[RACScheduler scheduler] afterDelay:1.5 schedule:^{
            [subscriber sendNext:@"second"];
        }];
        [[RACScheduler scheduler] afterDelay:2 schedule:^{
            [subscriber sendNext:@"third"];
            [subscriber sendCompleted];
        }];
        
        return nil;
    }];
    
    [[signal sample:sampler] subscribeNext:^(id x) {
        NSLog(@"sampler -- %@", x);
    }];
    
    [self ensureAsyncSignalCompleted];
    
    // 打印日志
    /*
     2018-08-05 15:14:58.734512+0800 TestSignalOperationMethod2[5447:8971432] sampler -- 1
     2018-08-05 15:14:59.237173+0800 TestSignalOperationMethod2[5447:8971432] sampler -- 1
     2018-08-05 15:15:03.231478+0800 TestSignalOperationMethod2[5447:8971432] sampler -- 2
     */
}

- (void)test_dematerialize
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:[RACEvent eventWithValue:@(1)]];
        [subscriber sendNext:[RACEvent completedEvent]];
        [subscriber sendNext:[RACEvent eventWithError:nil]];
        return nil;
    }];
    
    [[signal dematerialize]
     subscribeNext:^(id x) {
         NSLog(@"dematerialize -- %@", x);
     } error:^(NSError *error) {
         NSLog(@"dematerialize -- error");
     } completed:^{
         NSLog(@"dematerialize -- completed");
     }];
    
    // 打印日志
    /*
     2018-08-05 15:21:47.781749+0800 TestSignalOperationMethod2[5755:8992054] dematerialize -- 1
     2018-08-05 15:21:47.782075+0800 TestSignalOperationMethod2[5755:8992054] dematerialize -- completed
     */
}

- (void)test_not
{
    [[[self syncSignal] not]
     subscribeNext:^(id x) {
         NSLog(@"not -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 15:24:36.067371+0800 TestSignalOperationMethod2[5883:9000602] not -- 1
     2018-08-05 15:24:36.067841+0800 TestSignalOperationMethod2[5883:9000602] not -- 0
     */
}

- (void)test_and
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:[RACTuple tupleWithObjects:@(0), @(1), nil]];
        return nil;
    }];
    
    [[signal and]
     subscribeNext:^(id x) {
         NSLog(@"and -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 15:27:03.260225+0800 TestSignalOperationMethod2[6007:9008180] and -- 0
     */
}

- (void)test_or
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:[RACTuple tupleWithObjects:@(0), @(1), nil]];
        return nil;
    }];
    
    [[signal or]
     subscribeNext:^(id x) {
         NSLog(@"or -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 15:28:08.928557+0800 TestSignalOperationMethod2[6062:9011914] or -- 1
     */
}

- (void)test_reduceApply
{
    NSNumber *(^block)(NSNumber *number1, NSNumber *number2) = ^(NSNumber *number1, NSNumber *number2) {
        return @([number1 intValue] + [number2 intValue] + 100);
    };
    
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        [subscriber sendNext:[RACTuple tupleWithObjects:block, @(0), @(1), nil]];
        return nil;
    }];
    
    [[signal reduceApply]
     subscribeNext:^(id x) {
         NSLog(@"reduceApply -- %@", x);
     }];
    
    // 打印日志
    /*
     2018-08-05 15:31:44.860973+0800 TestSignalOperationMethod2[6232:9022747] reduceApply -- 101
     */
}


@end
