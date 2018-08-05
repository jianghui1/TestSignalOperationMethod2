# RACSignal+Operations方法（二）
### 接下来把`RACSignal+Operations`中剩下的方法分析完。

下面方法的所有测试用例在[这里](https://github.com/jianghui1/TestSignalOperationMethod2)。

***
    - (RACSignal *)switchToLatest {
    	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
    		RACMulticastConnection *connection = [self publish];
    
    		RACDisposable *subscriptionDisposable = [[connection.signal
    			flattenMap:^(RACSignal *x) {
    				NSCAssert(x == nil || [x isKindOfClass:RACSignal.class], @"-switchToLatest requires that the source signal (%@) send signals. Instead we got: %@", self, x);
    
    				// -concat:[RACSignal never] prevents completion of the receiver from
    				// prematurely terminating the inner signal.
    				return [x takeUntil:[connection.signal concat:[RACSignal never]]];
    			}]
    			subscribe:subscriber];
    
    		RACDisposable *connectionDisposable = [connection connect];
    		return [RACDisposable disposableWithBlock:^{
    			[subscriptionDisposable dispose];
    			[connectionDisposable dispose];
    		}];
    	}] setNameWithFormat:@"[%@] -switchToLatest", self.name];
    }
按照步骤分析如下：
1. 将`self`转为一个`connection`对象，
2. 对`connection.signal`进行订阅，由于此时`connection.signal`为`RACSubject`类型，其`subscribe:`方法如下：

        - (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
        	NSCParameterAssert(subscriber != nil);
        
        	RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];
        	subscriber = [[RACPassthroughSubscriber alloc] initWithSubscriber:subscriber signal:self disposable:disposable];
        
        	NSMutableArray *subscribers = self.subscribers;
        	@synchronized (subscribers) {
        		[subscribers addObject:subscriber];
        	}
        	
        	return [RACDisposable disposableWithBlock:^{
        		@synchronized (subscribers) {
        			// Since newer subscribers are generally shorter-lived, search
        			// starting from the end of the list.
        			NSUInteger index = [subscribers indexOfObjectWithOptions:NSEnumerationReverse passingTest:^ BOOL (id<RACSubscriber> obj, NSUInteger index, BOOL *stop) {
        				return obj == subscriber;
        			}];
        
        			if (index != NSNotFound) [subscribers removeObjectAtIndex:index];
        		}
        	}];
        }
所以`flattenMap:`并不会导致`connection.signal`的`next:` `error:` `completed`真正回调。`flattenMap`中的block块通过`takeUntil:`方法保证后面的信号终止前面的信号。也就是名字`switchToLatest`的含义，一直发送最新的信号值。
3. `[connection connect]`开始了对源信号的订阅，如果源信号有值，通过`connection.signal`发送出去，而`RACSubject` 的发送方法如下:

        - (void)sendNext:(id)value {
        	[self enumerateSubscribersUsingBlock:^(id<RACSubscriber> subscriber) {
        		[subscriber sendNext:value];
        	}];
        }
        
        - (void)sendError:(NSError *)error {
        	[self.disposable dispose];
        	
        	[self enumerateSubscribersUsingBlock:^(id<RACSubscriber> subscriber) {
        		[subscriber sendError:error];
        	}];
        }
        
        - (void)sendCompleted {
        	[self.disposable dispose];
        	
        	[self enumerateSubscribersUsingBlock:^(id<RACSubscriber> subscriber) {
        		[subscriber sendCompleted];
        	}];
        }
此时`connection.signal`的`sendNext:` `sendError:` `sendCompleted`方法会触发`flattenMap`中的`next:` `error:` `completed`块，并通过`subscriber`完成了信号信息的发送。

##### 综上，`switchToLatest`的源信号的信号值必定也是信号，然后通过对这些信号值进行订阅，一旦后面的信号有值，就会把前面信号的订阅给终止掉。也就是保证一直发送最新的信号值。

测试用例：
    
    - (RACSignal *)asyncSignal
    {
        return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
            
            [subscriber sendNext:@"start"];
            
            [[RACScheduler mainThreadScheduler] afterDelay:2 schedule:^{
                [subscriber sendNext:@"end"];
                [subscriber sendCompleted];
            }];
            
            return nil;
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
***
    + (RACSignal *)switch:(RACSignal *)signal cases:(NSDictionary *)cases default:(RACSignal *)defaultSignal {
    	NSCParameterAssert(signal != nil);
    	NSCParameterAssert(cases != nil);
    
    	for (id key in cases) {
    		id value __attribute__((unused)) = cases[key];
    		NSCAssert([value isKindOfClass:RACSignal.class], @"Expected all cases to be RACSignals, %@ isn't", value);
    	}
    
    	NSDictionary *copy = [cases copy];
    
    	return [[[signal
    		map:^(id key) {
    			if (key == nil) key = RACTupleNil.tupleNil;
    
    			RACSignal *signal = copy[key] ?: defaultSignal;
    			if (signal == nil) {
    				NSString *description = [NSString stringWithFormat:NSLocalizedString(@"No matching signal found for value %@", @""), key];
    				return [RACSignal error:[NSError errorWithDomain:RACSignalErrorDomain code:RACSignalErrorNoMatchingCase userInfo:@{ NSLocalizedDescriptionKey: description }]];
    			}
    
    			return signal;
    		}]
    		switchToLatest]
    		setNameWithFormat:@"+switch: %@ cases: %@ default: %@", signal, cases, defaultSignal];
    }
该方法参数`cases`中的`value`也是信号。首先对`signal`进行`map:`操作，拿到`signal`的值作为`key`找到`cases`中的`value`信号，如果`cases`中存在`key`对应的信号，返回出去；如果不存在，使用默认`defaultSignal`信号；如果两种都没有，就返回一个`error`信号。最后通过`switchToLatest`保证一直获取信号的最新值。

##### 所以，该方法的作用就是以`signal`的信号值作为判断条件，获取`cases`在该改条件下的信号的最新信号值。

测试用例：
    
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
            
            [[RACScheduler mainThreadScheduler] afterDelay:2 schedule:^{
                [subscriber sendNext:@"end"];
                [subscriber sendCompleted];
            }];
            
            return nil;
        }];
    }
    // 保证异步操作完成
    - (void)ensureAsyncSignalCompleted
    {
        [[RACSignal never] asynchronouslyWaitUntilCompleted:nil];
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
***
    + (RACSignal *)if:(RACSignal *)boolSignal then:(RACSignal *)trueSignal else:(RACSignal *)falseSignal {
    	NSCParameterAssert(boolSignal != nil);
    	NSCParameterAssert(trueSignal != nil);
    	NSCParameterAssert(falseSignal != nil);
    
    	return [[[boolSignal
    		map:^(NSNumber *value) {
    			NSCAssert([value isKindOfClass:NSNumber.class], @"Expected %@ to send BOOLs, not %@", boolSignal, value);
    
    			return (value.boolValue ? trueSignal : falseSignal);
    		}]
    		switchToLatest]
    		setNameWithFormat:@"+if: %@ then: %@ else: %@", boolSignal, trueSignal, falseSignal];
    }
##### 该方法与上面方法类似，通过`boolSignal`作为判断条件，选择使用`trueSignal`的值还是`falseSignal`的值。

测试用例：
    
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
            
            [[RACScheduler mainThreadScheduler] afterDelay:2 schedule:^{
                [subscriber sendNext:@"end"];
                [subscriber sendCompleted];
            }];
            
            return nil;
        }];
    }
    
    // 保证异步操作完成
    - (void)ensureAsyncSignalCompleted
    {
        [[RACSignal never] asynchronouslyWaitUntilCompleted:nil];
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
***
    - (id)first {
    	return [self firstOrDefault:nil];
    }
    
    - (id)firstOrDefault:(id)defaultValue {
    	return [self firstOrDefault:defaultValue success:NULL error:NULL];
    }
    
    - (id)firstOrDefault:(id)defaultValue success:(BOOL *)success error:(NSError **)error {
    	NSCondition *condition = [[NSCondition alloc] init];
    	condition.name = [NSString stringWithFormat:@"[%@] -firstOrDefault: %@ success:error:", self.name, defaultValue];
    
    	__block id value = defaultValue;
    	__block BOOL done = NO;
    
    	// Ensures that we don't pass values across thread boundaries by reference.
    	__block NSError *localError;
    	__block BOOL localSuccess;
    
    	[[self take:1] subscribeNext:^(id x) {
    		[condition lock];
    
    		value = x;
    		localSuccess = YES;
    
    		done = YES;
    		[condition broadcast];
    		[condition unlock];
    	} error:^(NSError *e) {
    		[condition lock];
    
    		if (!done) {
    			localSuccess = NO;
    			localError = e;
    
    			done = YES;
    			[condition broadcast];
    		}
    
    		[condition unlock];
    	} completed:^{
    		[condition lock];
    
    		localSuccess = YES;
    
    		done = YES;
    		[condition broadcast];
    		[condition unlock];
    	}];
    
    	[condition lock];
    	while (!done) {
    		[condition wait];
    	}
    
    	if (success != NULL) *success = localSuccess;
    	if (error != NULL) *error = localError;
    
    	[condition unlock];
    	return value;
    }
* 首先看`firstOrDefault:success:error:`方法。通过`take:1`只获取源信号的第一个值。然后使用`NSCondition`保证源信号执行完毕拿到结果。`defaultValue`作为源信号一个值都没有情况下的默认值。
* `firstOrDefault:`调用上面的方法获取源信号第一个值，并提供一个默认值。
* `first` 调用上面的方法获取源信号的第一个值，不提供默认值。

##### 所以这三个方法都是获取源信号的第一个值，只是提供的参数不同而已。

测试用例：

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
***
    - (BOOL)waitUntilCompleted:(NSError **)error {
    	BOOL success = NO;
    
    	[[[self
    		ignoreValues]
    		setNameWithFormat:@"[%@] -waitUntilCompleted:", self.name]
    		firstOrDefault:nil success:&success error:error];
    
    	return success;
    }
首先调用`ignoreValues`忽略掉信号所有的值，然后调用`firstOrDefault:success:error:`保证信号订阅完成。

##### 所以该方法就是一直等待信号订阅结束，并返回一个标识表示信号的订阅过程是否直接出错了。

测试用例：

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
***
    + (RACSignal *)defer:(RACSignal * (^)(void))block {
    	NSCParameterAssert(block != NULL);
    
    	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
    		return [block() subscribe:subscriber];
    	}] setNameWithFormat:@"+defer:"];
    }
##### `defer`意思是推迟，这里的作用主要是将热信号转为冷信号的，对于冷信号是没有作用的。
测试用例：

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
***
    - (NSArray *)toArray {
    	return [[[self collect] first] copy];
    }
##### 通过调用`collect`获取信号值组成的数组，通过`first`保证信号的完成。也就是同步获取一个结果数组。

测试用例：

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
***
    - (RACSequence *)sequence {
    	return [[RACSignalSequence sequenceWithSignal:self] setNameWithFormat:@"[%@] -sequence", self.name];
    }
##### 将`signal`转成一个`RACSequence`对象。`RACSequence`后面再进行分析。

测试用例：
    
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
***
    - (RACMulticastConnection *)publish {
    	RACSubject *subject = [[RACSubject subject] setNameWithFormat:@"[%@] -publish", self.name];
    	RACMulticastConnection *connection = [self multicast:subject];
    	return connection;
    }
    
    - (RACMulticastConnection *)multicast:(RACSubject *)subject {
    	[subject setNameWithFormat:@"[%@] -multicast: %@", self.name, subject.name];
    	RACMulticastConnection *connection = [[RACMulticastConnection alloc] initWithSourceSignal:self subject:subject];
    	return connection;
    }
* `multicast:`获取一个由`signal`转成的`RACMulticastConnection`对象，而`RACMulticastConnection`通过`RACSubject`对象和`connect`方法实现即使外部的多次订阅最后都是对源信号的一次真正的订阅。
* `publish`创建了一个`subject`对象，并调用上面的方法。

##### 所以，这两个就是将一个信号转换为`RACMulticastConnection`对象，从而节约订阅的次数。尽管外部多次订阅，最终都只是对源信号的一次真正订阅。

测试用例：

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
***
    - (RACSignal *)replay {
    	RACReplaySubject *subject = [[RACReplaySubject subject] setNameWithFormat:@"[%@] -replay", self.name];
    
    	RACMulticastConnection *connection = [self multicast:subject];
    	[connection connect];
    
    	return connection.signal;
    }
##### 创建一个`RACReplaySubject`对象，并调用`multicast:`方法，也是保证对源信号只有一次真正的订阅。而`RACReplaySubject`作为`RACSubject`的子类提供了一个参数`capacity`用来保存源信号的值的个数。

测试用例：

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
***
    - (RACSignal *)replayLast {
    	RACReplaySubject *subject = [[RACReplaySubject replaySubjectWithCapacity:1] setNameWithFormat:@"[%@] -replayLast", self.name];
    
    	RACMulticastConnection *connection = [self multicast:subject];
    	[connection connect];
    
    	return connection.signal;
    }
##### 该方法就是通过设置参数为`1`保证只获取源信号的最后一个值。

测试用例：

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
***
    - (RACSignal *)replayLazily {
    	RACMulticastConnection *connection = [self multicast:[RACReplaySubject subject]];
    	return [[RACSignal
    		defer:^{
    			[connection connect];
    			return connection.signal;
    		}]
    		setNameWithFormat:@"[%@] -replayLazily", self.name];
    }
##### 该方法通过`defer:`实现将热信号转为冷信号。上面的方法`replayLast`一旦调用，就会开始对源信号的订阅，而`replayLazily`只有对返回的信号订阅的时候，才会对源信号进行订阅。

测试用例：

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
***
    - (RACSignal *)timeout:(NSTimeInterval)interval onScheduler:(RACScheduler *)scheduler {
    	NSCParameterAssert(scheduler != nil);
    	NSCParameterAssert(scheduler != RACScheduler.immediateScheduler);
    
    	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
    		RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];
    
    		RACDisposable *timeoutDisposable = [scheduler afterDelay:interval schedule:^{
    			[disposable dispose];
    			[subscriber sendError:[NSError errorWithDomain:RACSignalErrorDomain code:RACSignalErrorTimedOut userInfo:nil]];
    		}];
    
    		[disposable addDisposable:timeoutDisposable];
    
    		RACDisposable *subscriptionDisposable = [self subscribeNext:^(id x) {
    			[subscriber sendNext:x];
    		} error:^(NSError *error) {
    			[disposable dispose];
    			[subscriber sendError:error];
    		} completed:^{
    			[disposable dispose];
    			[subscriber sendCompleted];
    		}];
    
    		[disposable addDisposable:subscriptionDisposable];
    		return disposable;
    	}] setNameWithFormat:@"[%@] -timeout: %f onScheduler: %@", self.name, (double)interval, scheduler];
    }
该方法通过`RACScheduler`的`afterDelay:schedule:`设置一个延时任务，如果到了指定时间源信号还没有订阅完成，就会发送错误信息，并终止源信号的订阅。

##### 所以该方法就是在订阅调度器上设置一个超时时间。

测试用例：

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
    // 保证异步操作完成
    - (void)ensureAsyncSignalCompleted
    {
        [[RACSignal never] asynchronouslyWaitUntilCompleted:nil];
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
***
    - (RACSignal *)deliverOn:(RACScheduler *)scheduler {
    	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
    		return [self subscribeNext:^(id x) {
    			[scheduler schedule:^{
    				[subscriber sendNext:x];
    			}];
    		} error:^(NSError *error) {
    			[scheduler schedule:^{
    				[subscriber sendError:error];
    			}];
    		} completed:^{
    			[scheduler schedule:^{
    				[subscriber sendCompleted];
    			}];
    		}];
    	}] setNameWithFormat:@"[%@] -deliverOn: %@", self.name, scheduler];
    }
##### 该方法将信号的`next:` `error:` `completed`转换到指定的调度器上。

测试用例：

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
***
    - (RACSignal *)subscribeOn:(RACScheduler *)scheduler {
    	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
    		RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];
    
    		RACDisposable *schedulingDisposable = [scheduler schedule:^{
    			RACDisposable *subscriptionDisposable = [self subscribe:subscriber];
    
    			[disposable addDisposable:subscriptionDisposable];
    		}];
    
    		[disposable addDisposable:schedulingDisposable];
    		return disposable;
    	}] setNameWithFormat:@"[%@] -subscribeOn: %@", self.name, scheduler];
    }

##### 该方法将信号的订阅转换到指定的调度器上。

与上面的方法有什么区别呢？`subscribeOn`是将`subscribe:`都放到`scheduler`上执行，后续的`next:` `error:` `completed`肯定也会转到`subscribe:`上执行。

但是注释中说明了一般情况下还是使用`deliverOn:`方法。因为信号的`subscribe`会切换到`subscriptionScheduler`调度器上，使用`subscribeOn:`可能会造成一些事件发生在不同的线程上。

测试用例：

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
***
    - (RACSignal *)deliverOnMainThread {
    	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
    		__block volatile int32_t queueLength = 0;
    		
    		void (^performOnMainThread)(dispatch_block_t) = ^(dispatch_block_t block) {
    			int32_t queued = OSAtomicIncrement32(&queueLength);
    			if (NSThread.isMainThread && queued == 1) {
    				block();
    				OSAtomicDecrement32(&queueLength);
    			} else {
    				dispatch_async(dispatch_get_main_queue(), ^{
    					block();
    					OSAtomicDecrement32(&queueLength);
    				});
    			}
    		};
    
    		return [self subscribeNext:^(id x) {
    			performOnMainThread(^{
    				[subscriber sendNext:x];
    			});
    		} error:^(NSError *error) {
    			performOnMainThread(^{
    				[subscriber sendError:error];
    			});
    		} completed:^{
    			performOnMainThread(^{
    				[subscriber sendCompleted];
    			});
    		}];
    	}] setNameWithFormat:@"[%@] -deliverOnMainThread", self.name];
    }
##### 通过`performOnMainThread`块将`sendNext:` `sendError:` `sendCompleted`转换到主线程中执行。

测试用例：

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
***
    - (RACSignal *)groupBy:(id<NSCopying> (^)(id object))keyBlock transform:(id (^)(id object))transformBlock {
    	NSCParameterAssert(keyBlock != NULL);
    
    	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
    		NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    		NSMutableArray *orderedGroups = [NSMutableArray array];
    
    		return [self subscribeNext:^(id x) {
    			id<NSCopying> key = keyBlock(x);
    			RACGroupedSignal *groupSubject = nil;
    			@synchronized(groups) {
    				groupSubject = groups[key];
    				if (groupSubject == nil) {
    					groupSubject = [RACGroupedSignal signalWithKey:key];
    					groups[key] = groupSubject;
    					[orderedGroups addObject:groupSubject];
    					[subscriber sendNext:groupSubject];
    				}
    			}
    
    			[groupSubject sendNext:transformBlock != NULL ? transformBlock(x) : x];
    		} error:^(NSError *error) {
    			[subscriber sendError:error];
    
    			[orderedGroups makeObjectsPerformSelector:@selector(sendError:) withObject:error];
    		} completed:^{
    			[subscriber sendCompleted];
    
    			[orderedGroups makeObjectsPerformSelector:@selector(sendCompleted)];
    		}];
    	}] setNameWithFormat:@"[%@] -groupBy:transform:", self.name];
    }
首先看下`RACGroupedSignal`，他是`RACSubject`的子类，增加了一个`key`。

然后在对源信号的订阅过程中，通过`keyBlock`将源信号的值转换为一个`key`，并用`key`创建了一个`RACGroupedSignal`对象，保存到`groups`字典和`orderedGroups`数组中。如果这个`RACGroupedSignal`是第一次创建的，还会被当做信号的值发送出去。接下来`groupSubject`会根据`transformBlock`是否存在来决定是将源信号值直接发送还是做`transformBlock`处理。

##### 所以该方法其实最终返回的是以`RACGroupedSignal`作为信号值的信号。当对`RACGroupedSignal`进行订阅的时候才会拿到源信号的值或者是对源信号值进行处理的值。

测试用例：

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
***
    - (RACSignal *)groupBy:(id<NSCopying> (^)(id object))keyBlock {
    	return [[self groupBy:keyBlock transform:nil] setNameWithFormat:@"[%@] -groupBy:", self.name];
    }
##### 调用上面的方法实现信号的分组，不对源信号值做额外处理。

测试用例：

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
***
    - (RACSignal *)any {
    	return [[self any:^(id x) {
    		return YES;
    	}] setNameWithFormat:@"[%@] -any", self.name];
    }
    
    - (RACSignal *)any:(BOOL (^)(id object))predicateBlock {
    	NSCParameterAssert(predicateBlock != NULL);
    
    	return [[[self materialize] bind:^{
    		return ^(RACEvent *event, BOOL *stop) {
    			if (event.finished) {
    				*stop = YES;
    				return [RACSignal return:@NO];
    			}
    
    			if (predicateBlock(event.value)) {
    				*stop = YES;
    				return [RACSignal return:@YES];
    			}
    
    			return [RACSignal empty];
    		};
    	}] setNameWithFormat:@"[%@] -any:", self.name];
    }
    
    - (RACSignal *)materialize {
    	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
    		return [self subscribeNext:^(id x) {
    			[subscriber sendNext:[RACEvent eventWithValue:x]];
    		} error:^(NSError *error) {
    			[subscriber sendNext:[RACEvent eventWithError:error]];
    			[subscriber sendCompleted];
    		} completed:^{
    			[subscriber sendNext:RACEvent.completedEvent];
    			[subscriber sendCompleted];
    		}];
    	}] setNameWithFormat:@"[%@] -materialize", self.name];
    }

* `materialize`将源信号的所有信息转换为`RACEvent`类型。
* `any:`先调用`materialize`将源信号的所有信息转换为`RACEvent`类型，然后如果`event.finished`，就会终止订阅并返回`[RACSignal return:@NO]`；否则就根据`predicateBlock`对`event.value`校验，通过了终止订阅并会返回`[RACSignal return:@YES]`。其他情况下返回`[RACSignal empty];`。所以此方法的作用就是源信号是否存在一个值符合`predicateBlock`的条件。
* `any`调用上面的方法判断源信号是否有值。

测试用例：

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
***
    - (RACSignal *)all:(BOOL (^)(id object))predicateBlock {
    	NSCParameterAssert(predicateBlock != NULL);
    
    	return [[[self materialize] bind:^{
    		return ^(RACEvent *event, BOOL *stop) {
    			if (event.eventType == RACEventTypeCompleted) {
    				*stop = YES;
    				return [RACSignal return:@YES];
    			}
    
    			if (event.eventType == RACEventTypeError || !predicateBlock(event.value)) {
    				*stop = YES;
    				return [RACSignal return:@NO];
    			}
    
    			return [RACSignal empty];
    		};
    	}] setNameWithFormat:@"[%@] -all:", self.name];
    }
##### 与上面方法类似，作用是检验源信号是否所有值都符合`predicateBlock`条件并且没有任何错误信息。

测试用例：

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
***
    - (RACSignal *)retry:(NSInteger)retryCount {
    	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
    		__block NSInteger currentRetryCount = 0;
    		return subscribeForever(self,
    			^(id x) {
    				[subscriber sendNext:x];
    			},
    			^(NSError *error, RACDisposable *disposable) {
    				if (retryCount == 0 || currentRetryCount < retryCount) {
    					// Resubscribe.
    					currentRetryCount++;
    					return;
    				}
    
    				[disposable dispose];
    				[subscriber sendError:error];
    			},
    			^(RACDisposable *disposable) {
    				[disposable dispose];
    				[subscriber sendCompleted];
    			});
    	}] setNameWithFormat:@"[%@] -retry: %lu", self.name, (unsigned long)retryCount];
    }
##### 通过`subscribeForever`保证源信号发生错误的时候重新进行订阅，最大订阅次数为`retryCount`。

测试用例：

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
***
    - (RACSignal *)retry {
    	return [[self retry:0] setNameWithFormat:@"[%@] -retry", self.name];
    }
##### 通过调用上面的方法保证源信号订阅发生错误的情况下一直重新订阅下去。

测试用例：

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
***

    - (RACSignal *)sample:(RACSignal *)sampler {
    	NSCParameterAssert(sampler != nil);
    
    	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
    		NSLock *lock = [[NSLock alloc] init];
    		__block id lastValue;
    		__block BOOL hasValue = NO;
    
    		RACSerialDisposable *samplerDisposable = [[RACSerialDisposable alloc] init];
    		RACDisposable *sourceDisposable = [self subscribeNext:^(id x) {
    			[lock lock];
    			hasValue = YES;
    			lastValue = x;
    			[lock unlock];
    		} error:^(NSError *error) {
    			[samplerDisposable dispose];
    			[subscriber sendError:error];
    		} completed:^{
    			[samplerDisposable dispose];
    			[subscriber sendCompleted];
    		}];
    
    		samplerDisposable.disposable = [sampler subscribeNext:^(id _) {
    			BOOL shouldSend = NO;
    			id value;
    			[lock lock];
    			shouldSend = hasValue;
    			value = lastValue;
    			[lock unlock];
    
    			if (shouldSend) {
    				[subscriber sendNext:value];
    			}
    		} error:^(NSError *error) {
    			[sourceDisposable dispose];
    			[subscriber sendError:error];
    		} completed:^{
    			[sourceDisposable dispose];
    			[subscriber sendCompleted];
    		}];
    
    		return [RACDisposable disposableWithBlock:^{
    			[samplerDisposable dispose];
    			[sourceDisposable dispose];
    		}];
    	}] setNameWithFormat:@"[%@] -sample: %@", self.name, sampler];
    }
##### 方法中同时对`self`和`sampler`进行了订阅，`self`的信号值保存下来等到`sampler`有信号值的时候再发送出去。也就是必须`self`和`sampler`同时都有信号值的时候才会发送`self`的信号值。同时，`self`或者`sampler`有一个订阅完成，就会终止整个订阅过程。

测试用例：

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
***
    - (RACSignal *)dematerialize {
    	return [[self bind:^{
    		return ^(RACEvent *event, BOOL *stop) {
    			switch (event.eventType) {
    				case RACEventTypeCompleted:
    					*stop = YES;
    					return [RACSignal empty];
    
    				case RACEventTypeError:
    					*stop = YES;
    					return [RACSignal error:event.error];
    
    				case RACEventTypeNext:
    					return [RACSignal return:event.value];
    			}
    		};
    	}] setNameWithFormat:@"[%@] -dematerialize", self.name];
    }
##### 如果源信号的信号值为`RACEvent`类型，调用该方法获取到`RACEvent`对象中存储的`value` or `error` or 完成信息。

测试用例：

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
***
    - (RACSignal *)not {
    	return [[self map:^(NSNumber *value) {
    		NSCAssert([value isKindOfClass:NSNumber.class], @"-not must only be used on a signal of NSNumbers. Instead, got: %@", value);
    
    		return @(!value.boolValue);
    	}] setNameWithFormat:@"[%@] -not", self.name];
    }
##### 该方法对源信号的值做求反运算。源信号值必须为`NSNumber`类型。

测试用例：

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
*** 
    - (RACSignal *)and {
    	return [[self map:^(RACTuple *tuple) {
    		NSCAssert([tuple isKindOfClass:RACTuple.class], @"-and must only be used on a signal of RACTuples of NSNumbers. Instead, received: %@", tuple);
    		NSCAssert(tuple.count > 0, @"-and must only be used on a signal of RACTuples of NSNumbers, with at least 1 value in the tuple");
    
    		return @([tuple.rac_sequence all:^(NSNumber *number) {
    			NSCAssert([number isKindOfClass:NSNumber.class], @"-and must only be used on a signal of RACTuples of NSNumbers. Instead, tuple contains a non-NSNumber value: %@", tuple);
    
    			return number.boolValue;
    		}]);
    	}] setNameWithFormat:@"[%@] -and", self.name];
    }
##### 该方法通过调用`RACSequence`的`all:`方法将源信号值进行与运算。源信号值必须为`RACTuple`类型，并且`RACTuple`中的对象为`NSNumber`类型。

测试用例：

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
***
    - (RACSignal *)or {
    	return [[self map:^(RACTuple *tuple) {
    		NSCAssert([tuple isKindOfClass:RACTuple.class], @"-or must only be used on a signal of RACTuples of NSNumbers. Instead, received: %@", tuple);
    		NSCAssert(tuple.count > 0, @"-or must only be used on a signal of RACTuples of NSNumbers, with at least 1 value in the tuple");
    
    		return @([tuple.rac_sequence any:^(NSNumber *number) {
    			NSCAssert([number isKindOfClass:NSNumber.class], @"-or must only be used on a signal of RACTuples of NSNumbers. Instead, tuple contains a non-NSNumber value: %@", tuple);
    
    			return number.boolValue;
    		}]);
    	}] setNameWithFormat:@"[%@] -or", self.name];
    }
##### 与上面方法相似，对源信号的值做或的运算，源信号的值类型与上面一样。

测试用例：

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
***
    - (RACSignal *)reduceApply {
    	return [[self map:^(RACTuple *tuple) {
    		NSCAssert([tuple isKindOfClass:RACTuple.class], @"-reduceApply must only be used on a signal of RACTuples. Instead, received: %@", tuple);
    		NSCAssert(tuple.count > 1, @"-reduceApply must only be used on a signal of RACTuples, with at least a block in tuple[0] and its first argument in tuple[1]");
    
    		// We can't use -array, because we need to preserve RACTupleNil
    		NSMutableArray *tupleArray = [NSMutableArray arrayWithCapacity:tuple.count];
    		for (id val in tuple) {
    			[tupleArray addObject:val];
    		}
    		RACTuple *arguments = [RACTuple tupleWithObjectsFromArray:[tupleArray subarrayWithRange:NSMakeRange(1, tupleArray.count - 1)]];
    
    		return [RACBlockTrampoline invokeBlock:tuple[0] withArguments:arguments];
    	}] setNameWithFormat:@"[%@] -reduceApply", self.name];
    }
##### 通过`RACBlockTrampoline`实现对源信号值的处理。首先源信号值必须是`TACTuple`类型，里面的第一个值为`block`，其他值为`block`的参数，最后通过调用`block`获取一个返回值作为对源信号值的处理。

测试用例：

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
***
#### 到此，`RACSignal`的所有方法基本分析完了，接下来就要分析`RACSequence`了。
