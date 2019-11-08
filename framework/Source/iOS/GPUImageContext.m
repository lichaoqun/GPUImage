#import "GPUImageContext.h"
#import <OpenGLES/EAGLDrawable.h>
#import <AVFoundation/AVFoundation.h>

#define MAXSHADERPROGRAMSALLOWEDINCACHE 40

extern dispatch_queue_attr_t GPUImageDefaultQueueAttribute(void);

@interface GPUImageContext()
{
    // - key : shader; value : shader program 的封装
    NSMutableDictionary *shaderProgramCache;
    NSMutableArray *shaderProgramUsageHistory;
    EAGLSharegroup *_sharegroup;
}

@end

@implementation GPUImageContext

@synthesize context = _context;
@synthesize currentShaderProgram = _currentShaderProgram;
@synthesize contextQueue = _contextQueue;
@synthesize coreVideoTextureCache = _coreVideoTextureCache;
@synthesize framebufferCache = _framebufferCache;

static void *openGLESContextQueueKey;

- (id)init;
{
    if (!(self = [super init]))
    {
		return nil;
    }

    // - openGLES 的渲染队列
	openGLESContextQueueKey = &openGLESContextQueueKey;
    _contextQueue = dispatch_queue_create("com.sunsetlakesoftware.GPUImage.openGLESContextQueue", GPUImageDefaultQueueAttribute());
    
#if OS_OBJECT_USE_OBJC
	dispatch_queue_set_specific(_contextQueue, openGLESContextQueueKey, (__bridge void *)self, NULL);
#endif
    
    // - 创建着色器缓存数组
    shaderProgramCache = [[NSMutableDictionary alloc] init];
    shaderProgramUsageHistory = [[NSMutableArray alloc] init];
    
    return self;
}

/** openGLES 绘制的队列的队列标识 */
+ (void *)contextKey {
	return openGLESContextQueueKey;
}

// Based on Colin Wheeler's example here: http://cocoasamurai.blogspot.com/2011/04/singletons-your-doing-them-wrong.html
/** context 单利对象 */
+ (GPUImageContext *)sharedImageProcessingContext;
{
    static dispatch_once_t pred;
    static GPUImageContext *sharedImageProcessingContext = nil;
    
    dispatch_once(&pred, ^{
        sharedImageProcessingContext = [[[self class] alloc] init];
    });
    return sharedImageProcessingContext;
}

/** 渲染的队列 */
+ (dispatch_queue_t)sharedContextQueue;
{
    return [[self sharedImageProcessingContext] contextQueue];
}

/** 渲染的帧缓存 */
+ (GPUImageFramebufferCache *)sharedFramebufferCache;
{
    return [[self sharedImageProcessingContext] framebufferCache];
}

/** 设置使用当前的上下文 */
+ (void)useImageProcessingContext;
{
    [[GPUImageContext sharedImageProcessingContext] useAsCurrentContext];
}
- (void)useAsCurrentContext;
{
    EAGLContext *imageProcessingContext = [self context];
    if ([EAGLContext currentContext] != imageProcessingContext)
    {
        [EAGLContext setCurrentContext:imageProcessingContext];
    }
}

/** 使用某个 shaderProgram */
+ (void)setActiveShaderProgram:(GLProgram *)shaderProgram;
{
    GPUImageContext *sharedContext = [GPUImageContext sharedImageProcessingContext];
    [sharedContext setContextShaderProgram:shaderProgram];
}
- (void)setContextShaderProgram:(GLProgram *)shaderProgram;
{
    EAGLContext *imageProcessingContext = [self context];
    if ([EAGLContext currentContext] != imageProcessingContext)
    {
        [EAGLContext setCurrentContext:imageProcessingContext];
    }
    
    if (self.currentShaderProgram != shaderProgram)
    {
        self.currentShaderProgram = shaderProgram;
        [shaderProgram use];
    }
}

/** 获取OpenGLES 相关的特性支持 */
+ (GLint)maximumTextureSizeForThisDevice;
{
    static dispatch_once_t pred;
    static GLint maxTextureSize = 0;
    
    dispatch_once(&pred, ^{
        [self useImageProcessingContext];
        glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTextureSize);
    });

    return maxTextureSize;
}

+ (GLint)maximumTextureUnitsForThisDevice;
{
    static dispatch_once_t pred;
    static GLint maxTextureUnits = 0;

    dispatch_once(&pred, ^{
        [self useImageProcessingContext];
        glGetIntegerv(GL_MAX_TEXTURE_IMAGE_UNITS, &maxTextureUnits);
    });
    
    return maxTextureUnits;
}

+ (GLint)maximumVaryingVectorsForThisDevice;
{
    static dispatch_once_t pred;
    static GLint maxVaryingVectors = 0;

    dispatch_once(&pred, ^{
        [self useImageProcessingContext];
        glGetIntegerv(GL_MAX_VARYING_VECTORS, &maxVaryingVectors);
    });

    return maxVaryingVectors;
}

+ (BOOL)deviceSupportsOpenGLESExtension:(NSString *)extension;
{
    static dispatch_once_t pred;
    static NSArray *extensionNames = nil;

    // Cache extensions for later quick reference, since this won't change for a given device
    dispatch_once(&pred, ^{
        [GPUImageContext useImageProcessingContext];
        NSString *extensionsString = [NSString stringWithCString:(const char *)glGetString(GL_EXTENSIONS) encoding:NSASCIIStringEncoding];
        extensionNames = [extensionsString componentsSeparatedByString:@" "];
    });

    return [extensionNames containsObject:extension];
}


// http://www.khronos.org/registry/gles/extensions/EXT/EXT_texture_rg.txt

+ (BOOL)deviceSupportsRedTextures;
{
    static dispatch_once_t pred;
    static BOOL supportsRedTextures = NO;
    
    dispatch_once(&pred, ^{
        supportsRedTextures = [GPUImageContext deviceSupportsOpenGLESExtension:@"GL_EXT_texture_rg"];
    });
    
    return supportsRedTextures;
}

+ (BOOL)deviceSupportsFramebufferReads;
{
    static dispatch_once_t pred;
    static BOOL supportsFramebufferReads = NO;
    
    dispatch_once(&pred, ^{
        supportsFramebufferReads = [GPUImageContext deviceSupportsOpenGLESExtension:@"GL_EXT_shader_framebuffer_fetch"];
    });
    
    return supportsFramebufferReads;
}

/** 调整纹理的大小, 使纹理在OpenGLES 支持的纹理范围内 */
+ (CGSize)sizeThatFitsWithinATextureForSize:(CGSize)inputSize;
{
    GLint maxTextureSize = [self maximumTextureSizeForThisDevice]; 
    if ( (inputSize.width < maxTextureSize) && (inputSize.height < maxTextureSize) )
    {
        return inputSize;
    }
    
    CGSize adjustedSize;
    if (inputSize.width > inputSize.height)
    {
        adjustedSize.width = (CGFloat)maxTextureSize;
        adjustedSize.height = ((CGFloat)maxTextureSize / inputSize.width) * inputSize.height;
    }
    else
    {
        adjustedSize.height = (CGFloat)maxTextureSize;
        adjustedSize.width = ((CGFloat)maxTextureSize / inputSize.height) * inputSize.width;
    }

    return adjustedSize;
}

/** 将渲染缓存呈现在设备上 */
- (void)presentBufferForDisplay;
{
    [self.context presentRenderbuffer:GL_RENDERBUFFER];
}

// - 获取 shader 对应的 program
- (GLProgram *)programForVertexShaderString:(NSString *)vertexShaderString fragmentShaderString:(NSString *)fragmentShaderString;
{
    // - 从 shaderProgramCache 中取GLProgram, 如果能取到就返回, 取不到就创建;
    NSString *lookupKeyForShaderProgram = [NSString stringWithFormat:@"V: %@ - F: %@", vertexShaderString, fragmentShaderString];
    GLProgram *programFromCache = [shaderProgramCache objectForKey:lookupKeyForShaderProgram];

    if (programFromCache == nil)
    {
        programFromCache = [[GLProgram alloc] initWithVertexShaderString:vertexShaderString fragmentShaderString:fragmentShaderString];
        [shaderProgramCache setObject:programFromCache forKey:lookupKeyForShaderProgram];
//        [shaderProgramUsageHistory addObject:lookupKeyForShaderProgram];
//        if ([shaderProgramUsageHistory count] >= MAXSHADERPROGRAMSALLOWEDINCACHE)
//        {
//            for (NSUInteger currentShaderProgramRemovedFromCache = 0; currentShaderProgramRemovedFromCache < 10; currentShaderProgramRemovedFromCache++)
//            {
//                NSString *shaderProgramToRemoveFromCache = [shaderProgramUsageHistory objectAtIndex:0];
//                [shaderProgramUsageHistory removeObjectAtIndex:0];
//                [shaderProgramCache removeObjectForKey:shaderProgramToRemoveFromCache];
//            }
//        }
    }
    
    return programFromCache;
}

- (void)useSharegroup:(EAGLSharegroup *)sharegroup;
{
    NSAssert(_context == nil, @"Unable to use a share group when the context has already been created. Call this method before you use the context for the first time.");
    
    _sharegroup = sharegroup;
}

/** 创建 EAGLContext[ */
- (EAGLContext *)createContext;
{
    EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2 sharegroup:_sharegroup];
    NSAssert(context != nil, @"Unable to create an OpenGL ES 2.0 context. The GPUImage framework requires OpenGL ES 2.0 support to work.");
    return context;
}


#pragma mark -
#pragma mark Manage fast texture upload

+ (BOOL)supportsFastTextureUpload;
{
#if TARGET_IPHONE_SIMULATOR
    return NO;
#else
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wtautological-pointer-compare"
    return (CVOpenGLESTextureCacheCreate != NULL);
#pragma clang diagnostic pop

#endif
}

#pragma mark -
#pragma mark Accessors

- (EAGLContext *)context;
{
    if (_context == nil)
    {
        _context = [self createContext];
        [EAGLContext setCurrentContext:_context];
        
        // Set up a few global settings for the image processing pipeline
        glDisable(GL_DEPTH_TEST);
    }
    
    return _context;
}

- (CVOpenGLESTextureCacheRef)coreVideoTextureCache;
{
    if (_coreVideoTextureCache == NULL)
    {
#if defined(__IPHONE_6_0)
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, [self context], NULL, &_coreVideoTextureCache);
#else
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (__bridge void *)[self context], NULL, &_coreVideoTextureCache);
#endif
        
        if (err)
        {
            NSAssert(NO, @"Error at CVOpenGLESTextureCacheCreate %d", err);
        }

    }
    
    return _coreVideoTextureCache;
}

- (GPUImageFramebufferCache *)framebufferCache;
{
    if (_framebufferCache == nil)
    {
        _framebufferCache = [[GPUImageFramebufferCache alloc] init];
    }
    
    return _framebufferCache;
}

@end
