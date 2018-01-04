//
//  do_Network_SM.m
//  DoExt_SM
//
//  Created by @userName on @time.
//  Copyright (c) 2015年 DoExt. All rights reserved.
//

#import "do_Network_SM.h"
#import "doReachability.h"

#import <UIKit/UIKit.h>

#import "doScriptEngineHelper.h"
#import "doIScriptEngine.h"
#import "doInvokeResult.h"

#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/CaptiveNetwork.h>

#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>

#import "doEventCenter.h"

#define IOS_CELLULAR    @"pdp_ip0"
#define IOS_WIFI        @"en0"
#define IOS_VPN         @"utun0"
#define IP_ADDR_IPv4    @"ipv4"
#define IP_ADDR_IPv6    @"ipv6"

@implementation do_Network_SM
{
    doReachability *_hostReach;
}
#pragma mark -
#pragma mark - 同步异步方法的实现

static do_Network_SM      * theInstance = nil;
+(do_Network_SM *)Instance
{
    if( theInstance == nil )
    {
        theInstance = [[do_Network_SM alloc]init];
    }
    
    return theInstance;
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        [self startObserve];
        
    }
    return self;
}
-(void)startObserve
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged:)
                                                 name: dokReachabilityChangedNotification
                                               object: nil];
    _hostReach = [doReachability reachabilityWithHostName:@"www.baidu.com"] ;
    [_hostReach startNotifier];
}
- (void)reachabilityChanged:(NSNotification *)note {
    doReachability* curReach = [note object];
    NetworkStatus status = [curReach currentReachabilityStatus];
    
    NSString *changedStatus = @"";
    switch (status) {
        case NotReachable:
            changedStatus = @"None";
            break;
        case kReachableVia2G:
            changedStatus = @"2G";
            break;
        case kReachableVia3G:
            changedStatus = @"3G";
            break;
        case ReachableViaWiFi:
            changedStatus = @"WIFI";
            break;
        case kReachableVia4G:
            changedStatus = @"4G";
            break;
        default:
            changedStatus = @"UnKnown";;
            break;
    }
    doInvokeResult  *invoke = [[doInvokeResult alloc] init];
    [invoke SetResultText:changedStatus];
    [self.EventCenter FireEvent:@"changed" :invoke];
    
}

//同步
- (void)getIP:(NSArray *)parms
{
    doInvokeResult *_invokeResult = [parms objectAtIndex:2];
    //自己的代码实现
    NSString *address = [self.class getIPAddress:YES];

    [_invokeResult SetResultText:address];
}

+ (NSString *)getIPAddress:(BOOL)preferIPv4
{
    NSArray *searchArray = preferIPv4 ?
    @[ IOS_VPN @"/" IP_ADDR_IPv4, IOS_VPN @"/" IP_ADDR_IPv6, IOS_WIFI @"/" IP_ADDR_IPv4, IOS_WIFI @"/" IP_ADDR_IPv6, IOS_CELLULAR @"/" IP_ADDR_IPv4, IOS_CELLULAR @"/" IP_ADDR_IPv6 ] :
    @[ IOS_VPN @"/" IP_ADDR_IPv6, IOS_VPN @"/" IP_ADDR_IPv4, IOS_WIFI @"/" IP_ADDR_IPv6, IOS_WIFI @"/" IP_ADDR_IPv4, IOS_CELLULAR @"/" IP_ADDR_IPv6, IOS_CELLULAR @"/" IP_ADDR_IPv4 ] ;
    
    NSDictionary *addresses = [self getIPAddresses];
    NSLog(@"addresses: %@", addresses);
    
    __block NSString *address;
    [searchArray enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL *stop)
     {
         address = addresses[key];
         //筛选出IP地址格式
         if([self isValidatIP:address]) *stop = YES;
     } ];
    return address ? address : @"0.0.0.0";
}

+ (BOOL)isValidatIP:(NSString *)ipAddress {
    if (ipAddress.length == 0) {
        return NO;
    }
    NSString *urlRegEx = @"^([01]?\\d\\d?|2[0-4]\\d|25[0-5])\\."
    "([01]?\\d\\d?|2[0-4]\\d|25[0-5])\\."
    "([01]?\\d\\d?|2[0-4]\\d|25[0-5])\\."
    "([01]?\\d\\d?|2[0-4]\\d|25[0-5])$";
    
    NSError *error;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:urlRegEx options:0 error:&error];
    
    if (regex != nil) {
        NSTextCheckingResult *firstMatch=[regex firstMatchInString:ipAddress options:0 range:NSMakeRange(0, [ipAddress length])];
        
        if (firstMatch) {
            NSRange resultRange = [firstMatch rangeAtIndex:0];
            NSString *result=[ipAddress substringWithRange:resultRange];
            //输出结果
            NSLog(@"%@",result);
            return YES;
        }
    }
    return NO;
}

+ (NSDictionary *)getIPAddresses
{
    NSMutableDictionary *addresses = [NSMutableDictionary dictionaryWithCapacity:8];
    
    // retrieve the current interfaces - returns 0 on success
    struct ifaddrs *interfaces;
    if(!getifaddrs(&interfaces)) {
        // Loop through linked list of interfaces
        struct ifaddrs *interface;
        for(interface=interfaces; interface; interface=interface->ifa_next) {
            if(!(interface->ifa_flags & IFF_UP) /* || (interface->ifa_flags & IFF_LOOPBACK) */ ) {
                continue; // deeply nested code harder to read
            }
            const struct sockaddr_in *addr = (const struct sockaddr_in*)interface->ifa_addr;
            char addrBuf[ MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN) ];
            if(addr && (addr->sin_family==AF_INET || addr->sin_family==AF_INET6)) {
                NSString *name = [NSString stringWithUTF8String:interface->ifa_name];
                NSString *type;
                if(addr->sin_family == AF_INET) {
                    if(inet_ntop(AF_INET, &addr->sin_addr, addrBuf, INET_ADDRSTRLEN)) {
                        type = IP_ADDR_IPv4;
                    }
                } else {
                    const struct sockaddr_in6 *addr6 = (const struct sockaddr_in6*)interface->ifa_addr;
                    if(inet_ntop(AF_INET6, &addr6->sin6_addr, addrBuf, INET6_ADDRSTRLEN)) {
                        type = IP_ADDR_IPv6;
                    }
                }
                if(type) {
                    NSString *key = [NSString stringWithFormat:@"%@/%@", name, type];
                    addresses[key] = [NSString stringWithUTF8String:addrBuf];
                }
            }
        }
        // Free memory
        freeifaddrs(interfaces);
    }
    return [addresses count] ? addresses : nil;
}

//获取设备的运营商
- (void)getOperators:(NSArray *)parms
{
    doInvokeResult *_invokeResult = [parms objectAtIndex:2];
    //自己的代码实现
    
    //首先判断是否插入了sim卡
    
    BOOL isSimCardAvailable = YES;
    
    CTTelephonyNetworkInfo* info = [[CTTelephonyNetworkInfo alloc] init];
    
    CTCarrier* carrier = info.subscriberCellularProvider;
    
    if(carrier.mobileNetworkCode == nil || [carrier.mobileNetworkCode isEqualToString:@""])
        
    {
        
        isSimCardAvailable = NO;
        [_invokeResult SetResultText:@"未插入sim卡"];
        
    }
    
    else
    {
        NSString *communicationType = [NSString stringWithFormat:@"%@",[carrier carrierName]];
        
        [_invokeResult SetResultText:communicationType];
    }
}
//获取网络状态
- (void)getStatus:(NSArray *)parms
{
    //自己的代码实现
    doInvokeResult *_invokeResult = [parms objectAtIndex:2];
    doReachability*reach=[doReachability reachabilityWithHostName:@"www.baidu.com"];
    NSString *state = @"none";
    switch ([reach currentReachabilityStatus]) {
        case NotReachable: {
            state = @"none";
            break;
        }
        case ReachableViaWiFi: {
            state = @"wifi";
            break;
        }
        case kReachableVia2G: {
            state = @"2G";
            break;
        }
        case kReachableVia3G: {
            state = @"3G";
            break;
        }
        case kReachableVia4G: {
            state = @"4G";
            break;
        }
        default: {
            state = @"unknown";
            break;
        }
    }
    [_invokeResult SetResultText:state];
}



- (void)openWifiSetting:(NSArray *)parms
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"prefs:root=WIFI"]];
}

- (void)isProxyUsed:(NSArray *)parms {
    BOOL useProxy = [self isVPNConnected];
//    NSArray *children = [[[[UIApplication sharedApplication]  valueForKeyPath:@"statusBar"]valueForKeyPath:@"foregroundView"]subviews];
//    int netType = 0;
    //获取到网络返回码
    
//    // 1: 2g 2: 3g 3: 4g 5: wifi 0: 无网
//    for (id child in children) {
//        if ([child isKindOfClass:NSClassFromString(@"UIStatusBarDataNetworkItemView")]) {
//            //获取到状态栏
//            netType = [[child valueForKeyPath:@"dataNetworkType"]intValue];
//            break;
//        }
//        
//    }
//    if (netType == 1 || netType == 2 || netType == 3 || netType == 5) { // 有网络
//    
//        useProxy = [self isVPNConnected];
//    }else {
//        useProxy = false;
//    }
    
    
    
    doInvokeResult *_invokeResult = [parms objectAtIndex:2];
    [_invokeResult SetResultBoolean:useProxy];
    
}

- (BOOL)isVPNConnected
{
    NSDictionary *dict = CFBridgingRelease(CFNetworkCopySystemProxySettings());
    NSArray *keys = [dict[@"__SCOPED__"]allKeys];
    for (NSString *key in keys) {
        if ([key rangeOfString:@"tap"].location != NSNotFound ||
            [key rangeOfString:@"tun"].location != NSNotFound ||
            [key rangeOfString:@"ppp"].location != NSNotFound){
            return YES;
        }
    }
    return NO;
}

- (void)getMACAddress:(NSArray *)parms
{
  
}


- (void)getWifiInfo:(NSArray *)parms
{
    id<doIScriptEngine> _scriptEngine = [parms objectAtIndex:1];
    NSString* _callbackFuncName = [parms objectAtIndex:2];
    doInvokeResult * _invokeResult = [[doInvokeResult alloc ] init:self.UniqueKey];
  
    NSDictionary *ifs = [self fetchSSIDInfo];
    NSString *ssid = [ifs objectForKey:@"SSID"];
    if (!ssid) {
        ssid = @"";
    }
    
    NSString *bssid = [ifs objectForKey:@"BSSID"];
    if (!bssid){
        bssid = @"";
    }
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject:[NSArray array] forKey:@"wifiName"];
    [dict setObject:ssid forKey:@"currentWifiName"];
    [dict setObject:bssid forKey:@"routerMacAddress"];
    [_invokeResult SetResultNode:dict];
    
    [_scriptEngine Callback:_callbackFuncName :_invokeResult];
}

- (id)fetchSSIDInfo {
    NSArray *ifs = (__bridge_transfer id)CNCopySupportedInterfaces();
    id info = nil;
    for (NSString *ifnam in ifs) {
        info = (__bridge_transfer id)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
        if (info && [info count]) { break; }
    }
    return info;
}
@end
