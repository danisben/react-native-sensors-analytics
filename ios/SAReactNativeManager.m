//
// SAReactNativeManager.m
// RNSensorsAnalyticsModule
//
// Created by 彭远洋 on 2020/3/16.
// Copyright © 2020-2021 Sensors Data Co., Ltd. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#if ! __has_feature(objc_arc)
#error This file must be compiled with ARC. Either turn on ARC for the project or use -fobjc-arc flag on this file.
#endif

#import "SAReactNativeManager.h"
#import "SAReactNativeCategory.h"
#import "SAReactNativeEventProperty.h"
#import <React/RCTUIManager.h>

#if __has_include(<SensorsAnalyticsSDK/SensorsAnalyticsSDK.h>)
#import <SensorsAnalyticsSDK/SensorsAnalyticsSDK.h>
#else
#import "SensorsAnalyticsSDK.h"
#endif

#pragma mark - Constants
NSString *const kSAEventScreenNameProperty = @"$screen_name";
NSString *const kSAEventTitleProperty = @"$title";
NSString *const kSAEventElementContentProperty = @"$element_content";

#pragma mark - React Native Manager
@interface SAReactNativeManager ()

@property (nonatomic, strong) NSSet *reactNativeIgnoreClasses;

@end

@implementation SAReactNativeManager

+ (instancetype)sharedInstance {
    static SAReactNativeManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[SAReactNativeManager alloc] init];

    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSSet *nativeIgnoreClasses = [NSSet setWithObjects:@"RCTSwitch", @"RCTSlider", @"RCTSegmentedControl", @"RNGestureHandlerButton", @"RNCSlider", @"RNCSegmentedControl", nil];
        for (NSString *className in nativeIgnoreClasses) {
            if (NSClassFromString(className)) {
                [[SensorsAnalyticsSDK sharedInstance] ignoreViewType:NSClassFromString(className)];
            }
        }
        _reactNativeIgnoreClasses = [NSSet setWithObjects:@"RCTScrollView", @"RCTBaseTextInputView", nil];
    }
    return self;
}

- (SAReactNativeViewProperty *)viewPropertyWithReactTag:(NSNumber *)reactTag fromViewProperties:(NSSet <SAReactNativeViewProperty *>*)properties {
    for (SAReactNativeViewProperty *property in properties) {
        if (property.reactTag.integerValue == reactTag.integerValue) {
            return property;
        }
    }
    return nil;
}

- (BOOL)clickableForView:(UIView *)view {
    if (!view) {
        return NO;
    }
    for (NSString *className in _reactNativeIgnoreClasses) {
        if ([view isKindOfClass:NSClassFromString(className)]) {
            return NO;
        }
    }

    // 通过 RCTRootView 获取 viewProperty
    UIViewController *reactViewController = [self rootView].reactViewController;
    NSSet *viewProperties = reactViewController.sa_reactnative_viewProperties;
    NSDictionary *screenProperties = reactViewController.sa_reactnative_screenProperties;
    view.sa_reactnative_screenProperties = screenProperties;

    // 兼容 Native 可视化全埋点 UISegmentedControl 整体不可圈选的场景
    if  ([view isKindOfClass:NSClassFromString(@"UISegmentedControl")]) {
        return NO;
    }

    // UISegmentedControl 只有子视图 UISegment 是可点击的
    if ([view isKindOfClass:NSClassFromString(@"UISegment")]) {
        return [self viewPropertyWithReactTag:view.superview.reactTag fromViewProperties:viewProperties].clickable;
    }

    return [self viewPropertyWithReactTag:view.reactTag fromViewProperties:viewProperties].clickable;
}

- (BOOL)prepareView:(NSNumber *)reactTag clickable:(BOOL)clickable paramters:(NSDictionary *)paramters {
    if (!clickable) {
        return NO;
    }
    if (!reactTag) {
        return NO;
    }
    // 每个可点击控件都需要添加对应属性，集合内存在对应属性对象即表示控件可点击
    SAReactNativeViewProperty *viewProperty = [[SAReactNativeViewProperty alloc] init];
    viewProperty.reactTag = reactTag;
    viewProperty.clickable = clickable;
    viewProperty.properties = paramters;
    dispatch_async(dispatch_get_main_queue(), ^{
        RCTRootView *rootView = [self rootView];
        NSMutableSet *viewProperties = [NSMutableSet setWithSet:rootView.reactViewController.sa_reactnative_viewProperties];
        [viewProperties addObject:viewProperty];
        rootView.reactViewController.sa_reactnative_viewProperties = [viewProperties copy];
    });
    return YES;
}

#pragma mark - visualize
- (NSDictionary *)visualizeProperties {
    UIView *rootView = [self rootView];
    return rootView.window ? rootView.reactViewController.sa_reactnative_screenProperties : nil;
}

#pragma mark - AppClick
- (void)trackViewClick:(NSNumber *)reactTag {
    if (![[SensorsAnalyticsSDK sharedInstance] isAutoTrackEnabled]) {
        return;
    }
    // 忽略 $AppClick 事件
    if ([[SensorsAnalyticsSDK sharedInstance] isAutoTrackEventTypeIgnored:SensorsAnalyticsEventTypeAppClick]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        // 通过 RCTRootView 获取 viewProperty
        RCTRootView *rootView = [self rootView];
        NSSet *viewProperties = rootView.reactViewController.sa_reactnative_viewProperties;
        NSDictionary *screenProperties = rootView.reactViewController.sa_reactnative_screenProperties;
        SAReactNativeViewProperty *viewProperty = [self viewPropertyWithReactTag:reactTag fromViewProperties:viewProperties];
        id ignoreParam = viewProperty.properties[@"ignore"];
        if ([ignoreParam respondsToSelector:@selector(boolValue)] && [ignoreParam boolValue]) {
            return;
        }

        UIView *view = [rootView.bridge.uiManager viewForReactTag:reactTag];
        for (NSString *className in self.reactNativeIgnoreClasses) {
            if ([view isKindOfClass:NSClassFromString(className)]) {
                return;
            }
        }
        NSMutableDictionary *properties = [NSMutableDictionary dictionary];
        NSString *content = [view.accessibilityLabel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        properties[kSAEventElementContentProperty] = content;
        [properties addEntriesFromDictionary:screenProperties];
        [properties addEntriesFromDictionary:viewProperty.properties];
        NSDictionary *newProps = [SAReactNativeEventProperty eventProperties:properties isAuto:YES];
        [[SensorsAnalyticsSDK sharedInstance] trackViewAppClick:view withProperties:newProps];
    });
}

#pragma mark - AppViewScreen
- (void)trackViewScreen:(nullable NSString *)url properties:(nullable NSDictionary *)properties autoTrack:(BOOL)autoTrack {
    if (url && ![url isKindOfClass:NSString.class]) {
        NSLog(@"[RNSensorsAnalytics] error: url {%@} is not String Class ！！！", url);
        return;
    }
    NSString *screenName = properties[kSAEventScreenNameProperty] ?: url;
    NSString *title = properties[kSAEventTitleProperty] ?: screenName;

    NSMutableDictionary *pageProps = [NSMutableDictionary dictionary];
    pageProps[kSAEventScreenNameProperty] = screenName;
    pageProps[kSAEventTitleProperty] = title;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self rootView].reactViewController.sa_reactnative_screenProperties = [pageProps copy];
    });

    // 忽略 React Native 触发的 $AppViewScreen 事件
    if (autoTrack && [properties[@"SAIgnoreViewScreen"] boolValue]) {
        return;
    }

    // 检查 SDK 全埋点功能开启状态
    if (autoTrack && ![[SensorsAnalyticsSDK sharedInstance] isAutoTrackEnabled]) {
        return;
    }

    // 忽略所有 $AppViewScreen 事件
    if (autoTrack && [[SensorsAnalyticsSDK sharedInstance] isAutoTrackEventTypeIgnored:SensorsAnalyticsEventTypeAppViewScreen]) {
        return;
    }

    NSMutableDictionary *eventProps = [NSMutableDictionary dictionary];
    [eventProps addEntriesFromDictionary:pageProps];
    [eventProps addEntriesFromDictionary:properties];

    dispatch_async(dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSDictionary *properties = [SAReactNativeEventProperty eventProperties:eventProps isAuto:autoTrack];
        [[SensorsAnalyticsSDK sharedInstance] trackViewScreen:url withProperties:properties];
#pragma clang diagnostic pop
    });
}

#pragma mark - Find RCTRootView
- (RCTRootView *)rootView {
    UIViewController *current = [[SensorsAnalyticsSDK sharedInstance] currentViewController];
    RCTRootView *rootView = [self rootViewWithCurrentView:current.view];
    while (current && !rootView) {
        current = current.presentingViewController;
        rootView = [self rootViewWithCurrentView:current.view];
    }

    if (!rootView) {
        // 当 rootViewController 为普通 UIViewController，且添加了 childController 时无法获取到 RCTRootView
        // 此时直接通过 rootViewController 的 subview 获取 RCTRootView
        // 这里是通过遍历所有的  subviews 查找，作为补充逻辑存在
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        rootView = [self rootViewWithCurrentView:root.view];
    }

    return rootView;
}

- (RCTRootView *)rootViewWithCurrentView:(UIView *)currentView {
    if (!currentView) {
        return nil;
    }
    if (currentView.isReactRootView) {
        return (RCTRootView *)currentView;
    }
    for (UIView *subView in currentView.subviews) {
        RCTRootView *rootView = [self rootViewWithCurrentView:subView];
        if (rootView) {
            return rootView;
        }
    }
    return nil;
}

@end
