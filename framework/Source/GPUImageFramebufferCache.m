#import "GPUImageFramebufferCache.h"
#import "GPUImageContext.h"
#import "GPUImageOutput.h"

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#endif

@interface GPUImageFramebufferCache()
{
//    NSCache *framebufferCache;
    
    // - frameBuffer 缓存数组
    NSMutableDictionary *framebufferCache;
    NSMutableDictionary *framebufferTypeCounts;
    
    // - 当前正在使用的 GPUImgeFrameBuffer 的数组
    NSMutableArray *activeImageCaptureList; // Where framebuffers that may be lost by a filter, but which are still needed for a UIImage, etc., are stored
    
    // - 内存警告
    id memoryWarningObserver;

    // - 帧缓存数组的队列
    dispatch_queue_t framebufferCacheQueue;
}

- (NSString *)hashForSize:(CGSize)size textureOptions:(GPUTextureOptions)textureOptions onlyTexture:(BOOL)onlyTexture;

@end


@implementation GPUImageFramebufferCache

// - MARK: <-- 初始化方法 -->
- (id)init;
{
    if (!(self = [super init]))
    {
		return nil;
    }
    
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    __unsafe_unretained __typeof__ (self) weakSelf = self;
    memoryWarningObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        __typeof__ (self) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf purgeAllUnassignedFramebuffers];
        }
    }];
#else
#endif

//    framebufferCache = [[NSCache alloc] init];
    framebufferCache = [[NSMutableDictionary alloc] init];
    framebufferTypeCounts = [[NSMutableDictionary alloc] init];
    activeImageCaptureList = [[NSMutableArray alloc] init];
    framebufferCacheQueue = dispatch_queue_create("com.sunsetlakesoftware.GPUImage.framebufferCacheQueue", GPUImageDefaultQueueAttribute());
    
    return self;
}

- (void)dealloc;
{
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#else
#endif
}

// - MARK: <-- 查找和存储的 key -->
/** 将 size 和 textureOptions 和 onlyTexture 生成一个字符串 */
- (NSString *)hashForSize:(CGSize)size textureOptions:(GPUTextureOptions)textureOptions onlyTexture:(BOOL)onlyTexture;
{
    if (onlyTexture)
    {
        return [NSString stringWithFormat:@"%.1fx%.1f-%d:%d:%d:%d:%d:%d:%d-NOFB", size.width, size.height, textureOptions.minFilter, textureOptions.magFilter, textureOptions.wrapS, textureOptions.wrapT, textureOptions.internalFormat, textureOptions.format, textureOptions.type];
    }
    else
    {
        return [NSString stringWithFormat:@"%.1fx%.1f-%d:%d:%d:%d:%d:%d:%d", size.width, size.height, textureOptions.minFilter, textureOptions.magFilter, textureOptions.wrapS, textureOptions.wrapT, textureOptions.internalFormat, textureOptions.format, textureOptions.type];
    }
}

// - MARK: <--  根据 key 查找 去framebufferTypeCounts 和 framebufferCache 中查找  -->
/** 根据 size 和 textureOptions 和 onlyTexture 查找 frameBuffer */
- (GPUImageFramebuffer *)fetchFramebufferForSize:(CGSize)framebufferSize textureOptions:(GPUTextureOptions)textureOptions onlyTexture:(BOOL)onlyTexture;
{
    __block GPUImageFramebuffer *framebufferFromCache = nil;
//    dispatch_sync(framebufferCacheQueue, ^{
    runSynchronouslyOnVideoProcessingQueue(^{
        
        // - 根据 size 和 textureOptions 和 onlyTexture 生成 key
        NSString *lookupHash = [self hashForSize:framebufferSize textureOptions:textureOptions onlyTexture:onlyTexture];
        
        // - 根据key 去 framebufferTypeCounts 中取到 value (缓存中匹配的 texture 数量)
        NSNumber *numberOfMatchingTexturesInCache = [framebufferTypeCounts objectForKey:lookupHash];
        NSInteger numberOfMatchingTextures = [numberOfMatchingTexturesInCache integerValue];
        
        /**
         如果匹配的数量 numberOfMatchingTexturesInCache < 1, 则创建一个 GPUImageFramebuffer;
         如果匹配的数量大于 1, 则取最后一个; 如果取出 GPUImageFramebuffer 为空，则取倒数第二个，依次类推
         */
        if ([numberOfMatchingTexturesInCache integerValue] < 1)
        {
            // Nothing in the cache, create a new framebuffer to use
            framebufferFromCache = [[GPUImageFramebuffer alloc] initWithSize:framebufferSize textureOptions:textureOptions onlyTexture:onlyTexture];
        }
        else
        {
            // Something found, pull the old framebuffer and decrement the count
            NSInteger currentTextureID = (numberOfMatchingTextures - 1);
            while ((framebufferFromCache == nil) && (currentTextureID >= 0))
            {
                NSString *textureHash = [NSString stringWithFormat:@"%@-%ld", lookupHash, (long)currentTextureID];
                framebufferFromCache = [framebufferCache objectForKey:textureHash];
                // Test the values in the cache first, to see if they got invalidated behind our back
                if (framebufferFromCache != nil)
                {
                    // Withdraw this from the cache while it's in use
                    // - 取到后,在  framebufferCache 中移除这个 GPUImageFramebuffer
                    [framebufferCache removeObjectForKey:textureHash];
                }
                currentTextureID--;
            }
            
            currentTextureID++;
            
            // - 更新 frameBufferTypeCounts 中相同类型的 GPUImageFrameBuffer 的数量
            [framebufferTypeCounts setObject:[NSNumber numberWithInteger:currentTextureID] forKey:lookupHash];
            
            if (framebufferFromCache == nil)
            {
                // - 取到的所有的 GPUImageFrameBuffer 都是空的, 则创建一个新的 GPUImageFrameBuffer;
                framebufferFromCache = [[GPUImageFramebuffer alloc] initWithSize:framebufferSize textureOptions:textureOptions onlyTexture:onlyTexture];
            }
        }
    });

    [framebufferFromCache lock];
    return framebufferFromCache;
}

/** 根据默认的 GPUTextureOptions 查找 frameBuffer */
- (GPUImageFramebuffer *)fetchFramebufferForSize:(CGSize)framebufferSize onlyTexture:(BOOL)onlyTexture;
{
    GPUTextureOptions defaultTextureOptions;
    defaultTextureOptions.minFilter = GL_LINEAR;
    defaultTextureOptions.magFilter = GL_LINEAR;
    defaultTextureOptions.wrapS = GL_CLAMP_TO_EDGE;
    defaultTextureOptions.wrapT = GL_CLAMP_TO_EDGE;
    defaultTextureOptions.internalFormat = GL_RGBA;
    defaultTextureOptions.format = GL_BGRA;
    defaultTextureOptions.type = GL_UNSIGNED_BYTE;
    
    return [self fetchFramebufferForSize:framebufferSize textureOptions:defaultTextureOptions onlyTexture:onlyTexture];
}

// - MARK: <-- 根据 key 添加到 framebufferTypeCounts 和 framebufferCache 中 -->
/** 将 frameBuffer 加入到缓存中 */
- (void)returnFramebufferToCache:(GPUImageFramebuffer *)framebuffer;
{
    [framebuffer clearAllLocks];
    
//    dispatch_async(framebufferCacheQueue, ^{
    runAsynchronouslyOnVideoProcessingQueue(^{
        CGSize framebufferSize = framebuffer.size;
        GPUTextureOptions framebufferTextureOptions = framebuffer.textureOptions;
        
        NSString *lookupHash = [self hashForSize:framebufferSize textureOptions:framebufferTextureOptions onlyTexture:framebuffer.missingFramebuffer];
        
        // - framebufferTypeCounts 的 key
        NSNumber *numberOfMatchingTexturesInCache = [framebufferTypeCounts objectForKey:lookupHash];
        NSInteger numberOfMatchingTextures = [numberOfMatchingTexturesInCache integerValue];
        
        // - framebufferCache 的 key
        NSString *textureHash = [NSString stringWithFormat:@"%@-%ld", lookupHash, (long)numberOfMatchingTextures];
        
//        [framebufferCache setObject:framebuffer forKey:textureHash cost:round(framebufferSize.width * framebufferSize.height * 4.0)];
        
        // - 存储 framebufferCache 和 framebufferTypeCounts 的键值
        [framebufferCache setObject:framebuffer forKey:textureHash];
        [framebufferTypeCounts setObject:[NSNumber numberWithInteger:(numberOfMatchingTextures + 1)] forKey:lookupHash];
    });
}

// - MARK: <-- 内存警告 -->
/** 内存警告删除 GPUImageFrameBuffer */
- (void)purgeAllUnassignedFramebuffers;
{
    runAsynchronouslyOnVideoProcessingQueue(^{
//    dispatch_async(framebufferCacheQueue, ^{
        [framebufferCache removeAllObjects];
        [framebufferTypeCounts removeAllObjects];
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
        CVOpenGLESTextureCacheFlush([[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache], 0);
#else
#endif
    });
}

// - MARK: <-- 帧缓存持有与释放 -->
- (void)addFramebufferToActiveImageCaptureList:(GPUImageFramebuffer *)framebuffer;
{
    runAsynchronouslyOnVideoProcessingQueue(^{
//    dispatch_async(framebufferCacheQueue, ^{
        [activeImageCaptureList addObject:framebuffer];
    });
}

- (void)removeFramebufferFromActiveImageCaptureList:(GPUImageFramebuffer *)framebuffer;
{
    runAsynchronouslyOnVideoProcessingQueue(^{
//  dispatch_async(framebufferCacheQueue, ^{
        [activeImageCaptureList removeObject:framebuffer];
    });
}

@end
