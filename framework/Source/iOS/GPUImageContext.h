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


/** 遵守这个协议的类表示能接受帧缓存的输入 */
@protocol GPUImageInput <NSObject>

/** 准备下一个要使用的帧 */
- (void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex;

/** 设置输入的帧缓冲对象以及纹理 */
- (void)setInputFramebuffer:(GPUImageFramebuffer *)newInputFramebuffer atIndex:(NSInteger)textureIndex;

/** 下一个有效的纹理索引 */
- (NSInteger)nextAvailableTextureIndex;

/** 设置目标的尺寸 */
- (void)setInputSize:(CGSize)newSize atIndex:(NSInteger)textureIndex;

/** 设置输入的旋转模式 */
- (void)setInputRotation:(GPUImageRotationMode)newInputRotation atIndex:(NSInteger)textureIndex;

/** 输出缓冲区的最大尺寸 */
- (CGSize)maximumOutputSize;

/** 结束处理 */
- (void)endProcessing;

/** 是否忽略渲染目标的更新 */
- (BOOL)shouldIgnoreUpdatesToThisTarget;

/** 是否启用渲染目标 */
- (BOOL)enabled;

/** 是否为单色输入 */
- (BOOL)wantsMonochromeInput;

/** 设置单色输入 */
- (void)setCurrentlyReceivingMonochromeInput:(BOOL)newValue;

@end
