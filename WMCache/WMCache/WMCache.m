//
//  WMCache.m
//  WMCache
//
//  Created by zengwm on 14-4-28.
//  Copyright (c) 2014年 zengwm. All rights reserved.
//

#import "WMCache.h"

#import "WMCacheInfo.h"

@implementation WMCacheInfo

#pragma mark NSCoding
- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:self.expirationDate forKey:@"expirationDate"];
    [encoder encodeObject:self.lastAccessTime forKey:@"lastAccessTime"];
    [encoder encodeObject:self.object forKey:@"object"];
    [encoder encodeObject:self.key forKey:@"key"];
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    if (self) {
        self.expirationDate = [decoder decodeObjectForKey:@"expirationDate"];
        self.lastAccessTime = [decoder decodeObjectForKey:@"lastAccessTime"];
        self.object = [decoder decodeObjectForKey:@"object"];
        self.key = [decoder decodeObjectForKey:@"key"];
    }
    return self;
}

- (BOOL)hasExpired {
    return (nil != _expirationDate
            && [[NSDate date] timeIntervalSinceDate:_expirationDate] >= 0);
}

@end

#define WMDiskCacheError(error) if (error) { NSLog(@"%@ (%d) ERROR: %@", \
[[NSString stringWithUTF8String:__FILE__] lastPathComponent], \
__LINE__, [error localizedDescription]); }

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
#define WMCacheStartBackgroundTask() UIBackgroundTaskIdentifier taskID = UIBackgroundTaskInvalid; \
taskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{ \
[[UIApplication sharedApplication] endBackgroundTask:taskID]; }];
#define WMCacheEndBackgroundTask() [[UIApplication sharedApplication] endBackgroundTask:taskID];
#else
#define WMCacheStartBackgroundTask()
#define WMCacheEndBackgroundTask()
#endif


NSString *const WMCacheClearNotification = @"WMCacheClearNotification";

static NSString* const kWMCacheDiskPath = @"WMCacheDiskPath";

static inline NSString *cachePathForKey(NSString* directory, NSString* key) {
	return [directory stringByAppendingPathComponent:key];
}

@interface WMCache(){
    dispatch_queue_t _cacheQueue;
}

@property (nonatomic,strong) NSCache *cache;
@property (nonatomic,strong) NSString *diskCachePath;

@end

@implementation WMCache

+ (WMCache *)shareCache
{
    static dispatch_once_t onceToken;
    static WMCache *instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (id)init
{
    return [self initWithNamespace:kWMCacheDiskPath];
}

- (id)initWithNamespace:(NSString *)ns
{
    if ((self = [super init]))
    {
        NSString *fullNamespace = [@"com.WMCache." stringByAppendingString:ns];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        _diskCachePath = [paths[0] stringByAppendingPathComponent:fullNamespace];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self createCacheDirectory];
        });
        
        //serial queue
        _cacheQueue = dispatch_queue_create("com.Vehicle360.VECounterCache", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_t lowPriQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
		dispatch_set_target_queue(_cacheQueue, lowPriQueue);
        
        _cache = [[NSCache alloc] init];
        _cache.name = fullNamespace;
        
#if TARGET_OS_IPHONE
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cleanAllCache)
                                                     name:WMCacheClearNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cleanMemory)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cleanMemory)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
#endif
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Private Method

- (BOOL)createCacheDirectory
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.diskCachePath]){
        return NO;
    }
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:self.diskCachePath
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&error];
    
    WMDiskCacheError(error);
    
    return success;
}

- (NSString *)defaultCachePathForKey:(NSString *)key
{
    return cachePathForKey(self.diskCachePath, key);
}

- (BOOL)dataExistForKey:(NSString*)key
{
    return [[NSFileManager defaultManager] fileExistsAtPath:[self defaultCachePathForKey:key]];
}


#pragma mark - Cache Method

- (void)storeImage:(UIImage *)image forKey:(NSString *)key
{
    [self storeImage:image forKey:key toDisk:YES];
}

- (void)storeImage:(UIImage *)image forKey:(NSString *)key toDisk:(BOOL)toDisk
{
    [self.cache setObject:image forKey:key];
    if (toDisk) {
        dispatch_async(_cacheQueue, ^{
            NSData *cacheData = [NSKeyedArchiver archivedDataWithRootObject:image];
            [cacheData writeToFile:[self defaultCachePathForKey:key] atomically:YES];
        });
        
    }
}

- (void)storeData:(id)data forKey:(NSString *)key
{
    [self storeData:data forKey:key toDisk:YES];
}

- (void)storeData:(id)data forKey:(NSString *)key toDisk:(BOOL)toDisk
{
    [self.cache setObject:data forKey:key];
    if (toDisk) {
        dispatch_async(_cacheQueue, ^{
            NSData *cacheData = [NSKeyedArchiver archivedDataWithRootObject:data];
            [cacheData writeToFile:[self defaultCachePathForKey:key] atomically:YES];
        });
    }
}

- (UIImage *)imageForKey:(NSString *)key
{
    UIImage* image = [self.cache objectForKey:key];
    if (!image) {
        image = [NSKeyedUnarchiver unarchiveObjectWithFile:[self defaultCachePathForKey:key]];
        [self storeImage:image forKey:key toDisk:NO];
        }
	return image;
}

- (id)dataForKey:(NSString *)key
{
    id data = [self.cache objectForKey:key];
    if (!data) {
        if ([self dataExistForKey:key]) {
            data = [NSKeyedUnarchiver unarchiveObjectWithFile:[self defaultCachePathForKey:key]];
            [self storeData:data forKey:key toDisk:NO];
        }
    }
    return data;
}

#pragma mark - Delete Method
- (void)removeCacheForKey:(NSString *)key
{
    __weak typeof (self)weakSelf = self;
	dispatch_async(_cacheQueue, ^{
        __strong typeof(weakSelf)strongSelf = weakSelf;
        if ([strongSelf dataExistForKey:key]) {
            [[NSFileManager defaultManager] removeItemAtPath:[strongSelf defaultCachePathForKey:key] error:NULL];
        }
		
	});
}

- (void)cleanAllCache
{
    [self cleanMemory];
    [self cleanDisk];
}

- (void)cleanDisk
{
    WMCacheStartBackgroundTask();
    dispatch_async(_cacheQueue, ^{
        NSArray *trashedItems = [self listAllItemPath];
        for (NSString *trashedItemPath in trashedItems) {
            NSError *error = nil;
            [[NSFileManager defaultManager] removeItemAtPath:trashedItemPath error:&error];
            WMDiskCacheError(error);
        }
        
        WMCacheEndBackgroundTask();
    });
}

- (void)cleanMemory
{
    [self.cache removeAllObjects];
}


- (NSArray *)listAllItemPath
{
    NSError *error = nil;
    NSArray *trashedItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.diskCachePath
                                                                                error:&error];
    WMDiskCacheError(error);
    NSMutableArray *trashedItemPaths = [NSMutableArray array];
    for (NSString *trashedItemKey in trashedItems)
    {
        [trashedItemPaths addObject:[self defaultCachePathForKey:trashedItemKey]];
    }
    return [trashedItemPaths copy];
}


@end
