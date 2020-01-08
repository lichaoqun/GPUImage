#import "GPUImageContext.h"
#import "GPUImageFramebuffer.h"

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
// For now, just redefine this on the Mac
typedef NS_ENUM(NSInteger, UIImageOrientation) {
    UIImageOrientationUp,            // default orientation
    UIImageOrientationDown,          // 180 deg rotation
    UIImageOrientationLeft,          // 90 deg CCW
    UIImageOrientationRight,         // 90 deg CW
    UIImageOrientationUpMirrored,    // as above but image mirrored along other axis. horizontal flip
    UIImageOrientationDownMirrored,  // horizontal flip
    UIImageOrientationLeftMirrored,  // vertical flip
    UIImageOrientationRightMirrored, // vertical flip
};
#endif

dispatch_queue_attr_t GPUImageDefaultQueueAttribute(void);
void runOnMainQueueWithoutDeadlocking(void (^block)(void));
void runSynchronouslyOnVideoProcessingQueue(void (^block)(void));
void runAsynchronouslyOnVideoProcessingQueue(void (^block)(void));
void runSynchronouslyOnContextQueue(GPUImageContext *context, void (^block)(void));
void runAsynchronouslyOnContextQueue(GPUImageContext *context, void (^block)(void));
void reportAvailableMemoryForGPUImage(NSString *tag);

@class GPUImageMovieWriter;

/** GPUImage's base source object
 
 Images or frames of video are uploaded from source objects, which are subclasses of GPUImageOutput. These include:
 
 - GPUImageVideoCamera (for live video from an iOS camera) 
 - GPUImageStillCamera (for taking photos with the camera)
 - GPUImagePicture (for still images)
 - GPUImageMovie (for movies)
 
 Source objects upload still image frames to OpenGL ES as textures, then hand those textures off to the next objects in the processing chain.
 */
@interface GPUImageOutput : NSObject
{
    // - 要输出给下一个着色器程序的 framebuffer 对象
    GPUImageFramebuffer *outputFramebuffer;
    
    // - target 数组, target纹理数组
    NSMutableArray *targets, *targetTextureIndices;

    // - 纹理尺寸
    CGSize inputTextureSize, cachedMaximumOutputSize, forcedMaximumSize;
    
    BOOL overrideInputSize;
    
    BOOL allTargetsWantMonochromeData;
    BOOL usingNextFrameForImageCapture;
}

/** 是否使用 mipmaps */
@property(readwrite, nonatomic) BOOL shouldSmoothlyScaleOutput;
/** 是否忽略处理当前的 target */
@property(readwrite, nonatomic) BOOL shouldIgnoreUpdatesToThisTarget;
@property(readwrite, nonatomic, retain) GPUImageMovieWriter *audioEncodingTarget;

/** 当前忽略处理的Target */
@property(readwrite, nonatomic, unsafe_unretained) id<GPUImageInput> targetToIgnoreForUpdates;

/** 每帧处理完回调 */
@property(nonatomic, copy) void(^frameProcessingCompletionBlock)(GPUImageOutput*, CMTime);

/** 是否启用渲染目标 */
@property(nonatomic) BOOL enabled;

/** 纹理选项 */
@property(readwrite, nonatomic) GPUTextureOptions outputTextureOptions;

/// @name Managing targets
- (void)setInputFramebufferForTarget:(id<GPUImageInput>)target atIndex:(NSInteger)inputTextureIndex;
- (GPUImageFramebuffer *)framebufferForOutput;
- (void)removeOutputFramebuffer;
- (void)notifyTargetsAboutNewOutputTexture;

/** Returns an array of the current targets.
 */
- (NSArray*)targets;

/** Adds a target to receive notifications when new frames are available.
 
 The target will be asked for its next available texture.
 
 See [GPUImageInput newFrameReadyAtTime:]
 
 @param newTarget Target to be added
 */
- (void)addTarget:(id<GPUImageInput>)newTarget;

/** Adds a target to receive notifications when new frames are available.
 
 See [GPUImageInput newFrameReadyAtTime:]
 
 @param newTarget Target to be added
 */
- (void)addTarget:(id<GPUImageInput>)newTarget atTextureLocation:(NSInteger)textureLocation;

/** Removes a target. The target will no longer receive notifications when new frames are available.
 
 @param targetToRemove Target to be removed
 */
- (void)removeTarget:(id<GPUImageInput>)targetToRemove;

/** Removes all targets.
 */
- (void)removeAllTargets;

/// @name Manage the output texture

- (void)forceProcessingAtSize:(CGSize)frameSize;
- (void)forceProcessingAtSizeRespectingAspectRatio:(CGSize)frameSize;

/// @name Still image processing

- (void)useNextFrameForImageCapture;
- (CGImageRef)newCGImageFromCurrentlyProcessedOutput;
- (CGImageRef)newCGImageByFilteringCGImage:(CGImageRef)imageToFilter;

// Platform-specific image output methods
// If you're trying to use these methods, remember that you need to set -useNextFrameForImageCapture before running -processImage or running video and calling any of these methods, or you will get a nil image
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
- (UIImage *)imageFromCurrentFramebuffer;
- (UIImage *)imageFromCurrentFramebufferWithOrientation:(UIImageOrientation)imageOrientation;
- (UIImage *)imageByFilteringImage:(UIImage *)imageToFilter;
- (CGImageRef)newCGImageByFilteringImage:(UIImage *)imageToFilter;
#else
- (NSImage *)imageFromCurrentFramebuffer;
- (NSImage *)imageFromCurrentFramebufferWithOrientation:(UIImageOrientation)imageOrientation;
- (NSImage *)imageByFilteringImage:(NSImage *)imageToFilter;
- (CGImageRef)newCGImageByFilteringImage:(NSImage *)imageToFilter;
#endif

- (BOOL)providesMonochromeOutput;

@end
