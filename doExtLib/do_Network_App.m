//
//  do_Network_App.m
//  DoExt_SM
//
//  Created by @userName on @time.
//  Copyright (c) 2015年 DoExt. All rights reserved.
//

#import "do_Network_App.h"
static do_Network_App* instance;
@implementation do_Network_App
@synthesize OpenURLScheme;
+(id) Instance
{
    if(instance==nil)
        instance = [[do_Network_App alloc]init];
    return instance;
}
@end
