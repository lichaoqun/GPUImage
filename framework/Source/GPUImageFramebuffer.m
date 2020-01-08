#import "GPUImageFramebuffer.h"
#import "GPUImageOutput.h"

@interface GPUImageFramebuffer()
{
    GLuint framebuffer;
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    CVPixelBufferRef renderTarget;
    CVOpenGLESTextureRef renderTexture;
    NSUInteger readLockCount;
#else
#endif
    NSUInteger framebufferReferenceCount;
    BOOL referenceCountingDisabled;
}

- (void)generateFramebuffer;
- (void)generateTexture;
- (void)destroyFramebuffer;

@end

void dataProviderReleaseCallback (void *info, const void *data, size_t size);
void dataProviderUnlockCallback (void *info, const void *data, size_t size);

@implementation GPUImageFramebuffer

/** 帧缓存大小 */
@synthesize size = _size;

/** 纹理设置选项 */
@synthesize textureOptions = _textureOptions;

/** 纹理缓存 */
@synthesize texture = _texture;

/** 是否忽略纹理没有帧缓存 */
@synthesize missingFramebuffer = _missingFramebuffer;


// - MARK: <-- 初始化方法 -->
- (id)initWithSize:(CGSize)framebufferSize textureOptions:(GPUTextureOptions)fboTextureOptions onlyTexture:(BOOL)onlyGenerateTexture;
{
    if (!(self = [super init]))
    {
		return nil;
    }
    
    /** 设置纹理选项 */
    _textureOptions = fboTextureOptions;
    _size = framebufferSize;
    framebufferReferenceCount = 0;
    referenceCountingDisabled = NO;
    
    // - 是否只生成纹理
    _missingFramebuffer = onlyGenerateTexture;

    // - 如果只生成纹理,则不生成帧缓存; 否则生成纹理缓存和帧缓存
    if (_missingFramebuffer)
    {
        runSynchronouslyOnVideoProcessingQueue(^{
            [GPUImageContext useImageProcessingContext];
            [self generateTexture];
            framebuffer = 0;
        });
    }else{
        [self generateFramebuffer];
    }
    return self;
}

- (id)initWithSize:(CGSize)framebufferSize overriddenTexture:(GLuint)inputTexture;
{
    if (!(self = [super init]))
    {
		return nil;
    }

    // - 设置纹理选项
    GPUTextureOptions defaultTextureOptions;
    defaultTextureOptions.minFilter = GL_LINEAR;
    defaultTextureOptions.magFilter = GL_LINEAR;
    defaultTextureOptions.wrapS = GL_CLAMP_TO_EDGE;
    defaultTextureOptions.wrapT = GL_CLAMP_TO_EDGE;
    defaultTextureOptions.internalFormat = GL_RGBA;
    defaultTextureOptions.format = GL_BGRA;
    defaultTextureOptions.type = GL_UNSIGNED_BYTE;

    _textureOptions = defaultTextureOptions;
    _size = framebufferSize;
    framebufferReferenceCount = 0;
    referenceCountingDisabled = YES;
    
    _texture = inputTexture;
    
    return self;
}

- (id)initWithSize:(CGSize)framebufferSize;
{
    // - 设置默认的纹理选项
    GPUTextureOptions defaultTextureOptions;
    defaultTextureOptions.minFilter = GL_LINEAR;
    defaultTextureOptions.magFilter = GL_LINEAR;
    defaultTextureOptions.wrapS = GL_CLAMP_TO_EDGE;
    defaultTextureOptions.wrapT = GL_CLAMP_TO_EDGE;
    defaultTextureOptions.internalFormat = GL_RGBA;
    defaultTextureOptions.format = GL_BGRA;
    defaultTextureOptions.type = GL_UNSIGNED_BYTE;

    // - 根据默认的纹理选项初始化 frameBuffer
    if (!(self = [self initWithSize:framebufferSize textureOptions:defaultTextureOptions onlyTexture:NO]))
    {
		return nil;
    }

    return self;
}

- (void)dealloc
{
    [self destroyFramebuffer];
}

// - MARK: <-- 当前使用的纹理和帧缓冲区的设置 -->
/** 设置纹理的通用参数 */
- (void)generateTexture;
{
    glActiveTexture(GL_TEXTURE1);
    glGenTextures(1, &_texture);
    glBindTexture(GL_TEXTURE_2D, _texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, _textureOptions.minFilter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, _textureOptions.magFilter);
    // This is necessary for non-power-of-two textures
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, _textureOptions.wrapS);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, _textureOptions.wrapT);
    
    // TODO: Handle mipmaps
}

/** 设置帧缓冲的通用参数 */
- (void)generateFramebuffer;
{
    
    /**
    * CVPixelBufferCreate()两个函数作用相当于
       *  kCVPixelFormatType_32BGRA:相当于glTexImage2D()倒数第三个参数，定义像素数据的格式
       *  attrs:定义纹理的其它属性
       *  renderTarget:最终将生成一个CVPixelBufferRef类型的像素块，默认值为0，相当于void *pixbuffer = (void*)malloc(size);
       *  最终将根据传入参数，宽、高，像素格式，和属性生成一个用于存储像素的内存块
    
     CVReturn err = CVPixelBufferCreate(kCFAllocatorDefault, (size_t)_size.width, (size_t)_size.height, kCVPixelFormatType_32BGRA, attrs, &renderTarget);
     if (err) {
         NSLog(@"FBO size: %f, %f", _size.width, _size.height);
         NSAssert(NO, @"Error at CVPixelBufferCreate %d", err);
     }
             
    * 该函数有两个作用：
      *  1、renderTarget像素数据传给opengles，类似于相当于glTexImage2D()，当然renderTarget中数据可以是由CVPixelBufferCreate()创建的默认值都是0的像素数据，也可以是具体的像素数据
      *  2、生成对应格式的CVOpenGLESTextureRef对象(相当于glGenTextures()生成的texture id)
      *  CVOpenGLESTextureRef对象(它是对Opengl es中由glGenTextures()生成的texture id的封装)
     err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                 textureCache,
                                 renderTarget,
                                 NULL, // texture attributes
                                 GL_TEXTURE_2D,
                                 _textureOptions.internalFormat, // opengl format，相当于glTexImage2D()函数第三个参数
                                 (int)_size.width,(int)_size.height,
                                 _textureOptions.format, // native iOS format，相当于glTexImage2D()函数倒数第三个参数，这里即renderTarget的像素格式，这里是IOS系统默认的BGRA数据格式
                                 _textureOptions.type,// 相当于glTexImage2D()函数第二个参数
                                 0,// 对于planner存储方式的像素数据，这里填写对应的索引。非planner格式写0即可
                                 &renderTexture);// 生成texture id
     if (err){
                 NSAssert(NO, @"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
     }
     */
    
    runSynchronouslyOnVideoProcessingQueue(^{
        
        // - 使用 context
        [GPUImageContext useImageProcessingContext];
    
        // - 生成和绑定帧缓冲
        glGenFramebuffers(1, &framebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
        
        // By default, all framebuffers on iOS 5.0+ devices are backed by texture caches, using one shared cache
        // - 允许快速纹理上传 (通常为 video 中的 texture)
        if ([GPUImageContext supportsFastTextureUpload])
        {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
            CVOpenGLESTextureCacheRef coreVideoTextureCache = [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache];
            // Code originally sourced from http://allmybrain.com/2011/12/08/rendering-to-a-texture-with-ios-5-texture-cache-api/
            
            CFDictionaryRef empty; // empty value for attr value.
            CFMutableDictionaryRef attrs;
            empty = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); // our empty IOSurface properties dictionary
            attrs = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFDictionarySetValue(attrs, kCVPixelBufferIOSurfacePropertiesKey, empty);
            
            CVReturn err = CVPixelBufferCreate(kCFAllocatorDefault, (int)_size.width, (int)_size.height, kCVPixelFormatType_32BGRA, attrs, &renderTarget);
            if (err)
            {
                NSLog(@"FBO size: %f, %f", _size.width, _size.height);
                NSAssert(NO, @"Error at CVPixelBufferCreate %d", err);
            }
            
            err = CVOpenGLESTextureCacheCreateTextureFromImage (kCFAllocatorDefault, coreVideoTextureCache, renderTarget,
                                                                NULL, // texture attributes
                                                                GL_TEXTURE_2D,
                                                                _textureOptions.internalFormat, // opengl format
                                                                (int)_size.width,
                                                                (int)_size.height,
                                                                _textureOptions.format, // native iOS format
                                                                _textureOptions.type,
                                                                0,
                                                                &renderTexture);
            if (err)
            {
                NSAssert(NO, @"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
            }
            
            CFRelease(attrs);
            CFRelease(empty);

            _texture = CVOpenGLESTextureGetName(renderTexture);
            glBindTexture(CVOpenGLESTextureGetTarget(renderTexture), _texture);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, _textureOptions.wrapS);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, _textureOptions.wrapT);
            
            /** 将 framebuffer 和 texture 绑定到一起 */
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _texture, 0);
#endif
        }
        else
        {
            // - 图片纹理
            [self generateTexture];

            glBindTexture(GL_TEXTURE_2D, _texture);
            
            /** 创建一个帧缓冲的纹理 (和创建普通的纹理对象一样, 只不过最后一个参数不是图片数据, 而是 NULL) */
            glTexImage2D(GL_TEXTURE_2D, 0, _textureOptions.internalFormat, (int)_size.width, (int)_size.height, 0, _textureOptions.format, _textureOptions.type, NULL);
            
            // - 将纹理附加到帧缓存上
            /**
             当渲染的图片需要直接显示到屏幕上时候,使用 renderbufferStorage:fromDrawable:函数即可 不用在调用 glFramebufferTexture2D
             如果不直接渲染到 view 上时候, 可以用 glFramebufferTexture2D 将纹理附加到帧缓冲中
             
             这里将新建的纹理绑定到framebufer中, 这时候 framebuffer 的渲染结果就会保存在 texture 中, 此时通过 _texture 拿到的纹理是渲染之后的有内容的纹理
             */
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _texture, 0);
        }
        
        #ifndef NS_BLOCK_ASSERTIONS
        
        // - 检查帧缓冲区对象的状态
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        NSAssert(status == GL_FRAMEBUFFER_COMPLETE, @"Incomplete filter FBO: %d", status);
        #endif
        
        glBindTexture(GL_TEXTURE_2D, 0);
    });
}

/** 清理帧缓冲对象 */
- (void)destroyFramebuffer;
{
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        
        if (framebuffer)
        {
            glDeleteFramebuffers(1, &framebuffer);
            framebuffer = 0;
        }

        
        if ([GPUImageContext supportsFastTextureUpload] && (!_missingFramebuffer))
        {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
            if (renderTarget)
            {
                CFRelease(renderTarget);
                renderTarget = NULL;
            }
            
            if (renderTexture)
            {
                CFRelease(renderTexture);
                renderTexture = NULL;
            }
#endif
        }
        else
        {
            glDeleteTextures(1, &_texture);
        }

    });
}

/** 绑定帧缓冲区, 并显示到屏幕上 */
- (void)activateFramebuffer;
{
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glViewport(0, 0, (int)_size.width, (int)_size.height);
}

// - MARK: <-- 引用计数 -->
/** 引用计数原理 来释放framebufferCache缓存字典 */
- (void)lock;
{
    if (referenceCountingDisabled)
    {
        return;
    }
    
    framebufferReferenceCount++;
}

- (void)unlock;
{
    if (referenceCountingDisabled)
    {
        return;
    }

    NSAssert(framebufferReferenceCount > 0, @"Tried to overrelease a framebuffer, did you forget to call -useNextFrameForImageCapture before using -imageFromCurrentFramebuffer?");
    framebufferReferenceCount--;
    if (framebufferReferenceCount < 1)
    {
        // - 引用计数 framebufferReferenceCount < 1 时候, 会把自己加入到 GPUImageFramebufferCache 中
        [[GPUImageContext sharedFramebufferCache] returnFramebufferToCache:self];
    }
}

- (void)clearAllLocks;
{
    framebufferReferenceCount = 0;
}

- (void)disableReferenceCounting;
{
    referenceCountingDisabled = YES;
}

- (void)enableReferenceCounting;
{
    referenceCountingDisabled = NO;
}


// - MARK: <-- 从帧缓冲区中取到图片数据 -->
void dataProviderReleaseCallback (void *info, const void *data, size_t size)
{
    free((void *)data);
}

void dataProviderUnlockCallback (void *info, const void *data, size_t size)
{
    GPUImageFramebuffer *framebuffer = (__bridge_transfer GPUImageFramebuffer*)info;
    
    [framebuffer restoreRenderTarget];
    [framebuffer unlock];
    [[GPUImageContext sharedFramebufferCache] removeFramebufferFromActiveImageCaptureList:framebuffer];
}

/** 根据 frameBuffer 生成 CGImageRef */
- (CGImageRef)newCGImageFromFramebufferContents;
{
    // a CGImage can only be created from a 'normal' color texture
    NSAssert(self.textureOptions.internalFormat == GL_RGBA, @"For conversion to a CGImage the output texture format for this filter must be GL_RGBA.");
    NSAssert(self.textureOptions.type == GL_UNSIGNED_BYTE, @"For conversion to a CGImage the type of the output texture of this filter must be GL_UNSIGNED_BYTE.");
    
    __block CGImageRef cgImageFromBytes;
    
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        
        
        // - 图片总大小 用于色彩空间为 rbga 的图片
        NSUInteger totalBytesForImage = (int)_size.width * (int)_size.height * 4;
        // It appears that the width of a texture must be padded out to be a multiple of 8 (32 bytes) if reading from it using a texture cache
        
        GLubyte *rawImagePixels;
        
        CGDataProviderRef dataProvider = NULL;
        
        // - 是否支持 coreVideo的快速纹理上传
        if ([GPUImageContext supportsFastTextureUpload])
        {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
            
            // - 图片宽度 = 每行图像数据大小 / 每个像素点字节数
            NSUInteger paddedWidthOfImage = CVPixelBufferGetBytesPerRow(renderTarget) / 4.0;
            
            // - 图像大小 = 图像宽度 * 高度 * 每个像素点字节数
            NSUInteger paddedBytesForImage = paddedWidthOfImage * (int)_size.height * 4;
            
            glFinish();
            CFRetain(renderTarget); // I need to retain the pixel buffer here and release in the data source callback to prevent its bytes from being prematurely deallocated during a photo write operation
            [self lockForReading];
            
            // - 获取 PixelBuffer 的基址
            rawImagePixels = (GLubyte *)CVPixelBufferGetBaseAddress(renderTarget);
            
            // - 创建 CGDataProviderRef 对象
            dataProvider = CGDataProviderCreateWithData((__bridge_retained void*)self, rawImagePixels, paddedBytesForImage, dataProviderUnlockCallback);
            [[GPUImageContext sharedFramebufferCache] addFramebufferToActiveImageCaptureList:self]; // In case the framebuffer is swapped out on the filter, need to have a strong reference to it somewhere for it to hang on while the image is in existence
#else
#endif
        }
        else
        {
            [self activateFramebuffer];
            
            // - 开辟一个图片大小的内存空间
            rawImagePixels = (GLubyte *)malloc(totalBytesForImage);
            
            /** 通过glReadPixels 读取frameBuffer中的每一个像素到rawImagePixels中 */
            glReadPixels(0, 0, (int)_size.width, (int)_size.height, GL_RGBA, GL_UNSIGNED_BYTE, rawImagePixels);
            
            /** 根据 rawImagePixels 创建 CGDataProvider  */
            dataProvider = CGDataProviderCreateWithData(NULL, rawImagePixels, totalBytesForImage, dataProviderReleaseCallback);
            [self unlock]; // Don't need to keep this around anymore
        }
        
        /** 默认的色彩空间 rgb */
        CGColorSpaceRef defaultRGBColorSpace = CGColorSpaceCreateDeviceRGB();
        
        if ([GPUImageContext supportsFastTextureUpload])
        {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
            
            // - 通过 data创建  CGImage; 这里因为不用解压图片, 所以不用 CGContextDrawImage
            cgImageFromBytes = CGImageCreate((int)_size.width, (int)_size.height, 8, 32, CVPixelBufferGetBytesPerRow(renderTarget), defaultRGBColorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst, dataProvider, NULL, NO, kCGRenderingIntentDefault);
#else
#endif
        }
        else
        {
            // - 通过 data创建  CGImage; 这里因为不用解压图片, 所以不用 CGContextDrawImage
            cgImageFromBytes = CGImageCreate((int)_size.width, (int)_size.height, 8, 32, 4 * (int)_size.width, defaultRGBColorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaLast, dataProvider, NULL, NO, kCGRenderingIntentDefault);
        }
        
        // Capture image with current device orientation
        CGDataProviderRelease(dataProvider);
        CGColorSpaceRelease(defaultRGBColorSpace);
        
    });
    
    return cgImageFromBytes;
}

- (void)restoreRenderTarget;
{
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    [self unlockAfterReading];
    CFRelease(renderTarget);
#else
#endif
}

#pragma mark -
#pragma mark Raw data bytes

- (void)lockForReading
{
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    if ([GPUImageContext supportsFastTextureUpload])
    {
        if (readLockCount == 0)
        {
            CVPixelBufferLockBaseAddress(renderTarget, 0);
        }
        readLockCount++;
    }
#endif
}

- (void)unlockAfterReading
{
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    if ([GPUImageContext supportsFastTextureUpload])
    {
        NSAssert(readLockCount > 0, @"Unbalanced call to -[GPUImageFramebuffer unlockAfterReading]");
        readLockCount--;
        if (readLockCount == 0)
        {
            CVPixelBufferUnlockBaseAddress(renderTarget, 0);
        }
    }
#endif
}

- (NSUInteger)bytesPerRow;
{
    if ([GPUImageContext supportsFastTextureUpload])
    {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
        return CVPixelBufferGetBytesPerRow(renderTarget);
#else
        return _size.width * 4; // TODO: do more with this on the non-texture-cache side
#endif
    }
    else
    {
        return _size.width * 4;
    }
}

- (GLubyte *)byteBuffer;
{
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    [self lockForReading];
    GLubyte * bufferBytes = CVPixelBufferGetBaseAddress(renderTarget);
    [self unlockAfterReading];
    return bufferBytes;
#else
    return NULL; // TODO: do more with this on the non-texture-cache side
#endif
}

- (CVPixelBufferRef )pixelBuffer;
{
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    return renderTarget;
#else
    return NULL; // TODO: do more with this on the non-texture-cache side
#endif
}

- (GLuint)texture;
{
//    NSLog(@"Accessing texture: %d from FB: %@", _texture, self);
    return _texture;
}

@end
