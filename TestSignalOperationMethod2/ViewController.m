//
//  ViewController.m
//  TestSignalOperationMethod2
//
//  Created by ys on 2018/8/5.
//  Copyright © 2018年 ys. All rights reserved.
//

#import "ViewController.h"

#import <ReactiveCocoa.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSArray *array = [[self asyncSignal] toArray];
    NSLog(@"toArray -- %@", array);
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



- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


@end
