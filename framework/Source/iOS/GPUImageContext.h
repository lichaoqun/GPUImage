#import "GLProgram.h"
#import "GPUImageFramebuffer.h"
#import "GPUImageFramebufferCache.h"

#define GPUImageRotationSwapsWidthAndHeight(rotation) ((rotation) == kGPUImageRotateLeft || (rotation) == kGPUImageRotateRight || (rotation) == kGPUImageRotateRightFlipVertical || (rotation) == kGPUImageRotateRightFlipHorizontal)

typedef NS_ENUM(NSUInteger, GPUImageRotationMode) {
	kGPUImageNoRotation,
	kGPUImageRotateLeft,
	kGPUImageRotateRight,
	kGPUImageFlipVertical,
	kGPUImageFlipHorizonal,
	kGPUImageRotateRightFlipVertical,
	kGPUImageRotateRightFlipHorizontal,
	kGPUImageRotate180
};

@interface GPUImageContext : NSObject
/** openGL 绘制的队列 */
@property(readonly, nonatomic) dispatch_queue_t contextQueue;

/** 当前使用的着色器程序 */
@property(readwrite, retain, nonatomic) GLProgram *currentShaderProgram;

/** EAGLContext 的上下文对象 */
@property(readonly, retain, nonatomic) EAGLContext *context;

/** coreVideo的纹理缓存 */
@property(readonly) CVOpenGLESTextureCacheRef coreVideoTextureCache;

/** 帧缓存 */
@property(readonly) GPUImageFramebufferCache *framebufferCache;

+ (void *)contextKey;
+ (GPUImageContext *)sharedImageProcessingContext;
+ (dispatch_queue_t)sharedContextQueue;
+ (GPUImageFramebufferCache *)sharedFramebufferCache;
+ (void)useImageProcessingContext;
- (void)useAsCurrentContext;
+ (void)setActiveShaderProgram:(GLProgram *)shaderProgram;
- (void)setContextShaderProgram:(GLProgram *)shaderProgram;
+ (GLint)maximumTextureSizeForThisDevice;
+ (GLint)maximumTextureUnitsForThisDevice;
+ (GLint)maximumVaryingVectorsForThisDevice;
+ (BOOL)deviceSupportsOpenGLESExtension:(NSString *)extension;
+ (BOOL)deviceSupportsRedTextures;
+ (BOOL)deviceSupportsFramebufferReads;
+ (CGSize)sizeThatFitsWithinATextureForSize:(CGSize)inputSize;

- (void)presentBufferForDisplay;
- (GLProgram *)programForVertexShaderString:(NSString *)vertexShaderString fragmentShaderString:(NSString *)fragmentShaderString;

- (void)useSharegroup:(EAGLSharegroup *)sharegroup;

// Manage fast texture upload
+ (BOOL)supportsFastTextureUpload;

@end

@protocol GPUImageInput <NSObject>
- (void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex;
- (void)setInputFramebuffer:(GPUImageFramebuffer *)newInputFramebuffer atIndex:(NSInteger)textureIndex;
- (NSInteger)nextAvailableTextureIndex;
- (void)setInputSize:(CGSize)newSize atIndex:(NSInteger)textureIndex;
- (void)setInputRotation:(GPUImageRotationMode)newInputRotation atIndex:(NSInteger)textureIndex;
- (CGSize)maximumOutputSize;
- (void)endProcessing;
- (BOOL)shouldIgnoreUpdatesToThisTarget;
- (BOOL)enabled;
- (BOOL)wantsMonochromeInput;
- (void)setCurrentlyReceivingMonochromeInput:(BOOL)newValue;
@end
