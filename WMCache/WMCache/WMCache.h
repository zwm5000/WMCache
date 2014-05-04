//
//  WMCache.h
//  WMCache
//
//  Created by zengwm on 14-4-28.
//  Copyright (c) 2014年 zengwm. All rights reserved.
//

#import <Foundation/Foundation.h>


extern NSString *const WMCacheClearNotification;

@interface WMCacheInfo : NSObject<NSCoding>

@property (nonatomic,copy) NSString *key;
@property (nonatomic,strong) id object;
@property (nonatomic,strong) NSDate *expirationDate;
@property (nonatomic,strong) NSDate *lastAccessTime;

- (BOOL)hasExpired;

@end

@interface WMCache : NSObject

+ (WMCache *)shareCache;

- (void)storeImage:(UIImage *)image forKey:(NSString *)key;
- (void)storeImage:(UIImage *)image forKey:(NSString *)key toDisk:(BOOL)toDisk;

- (void)storeData:(id)data forKey:(NSString *)key;
- (void)storeData:(id)data forKey:(NSString *)key toDisk:(BOOL)toDisk;

- (UIImage *)imageForKey:(NSString *)key;
- (id)dataForKey:(NSString *)key;

- (void)removeCacheForKey:(NSString *)key;
- (void)cleanAllCache;

@end
