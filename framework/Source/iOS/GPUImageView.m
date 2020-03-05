#import "GPUImageView.h"
#import <OpenGLES/EAGLDrawable.h>
#import <QuartzCore/QuartzCore.h>
#import "GPUImageContext.h"
#import "GPUImageFilter.h"
#import <AVFoundation/AVFoundation.h>

@interface GPUImageView () 
{
    GPUImageFramebuffer *inputFramebufferForDisplay;
    GLuint displayRenderbuffer, displayFramebuffer;
    
    GLProgram *displayProgram;
    GLint displayPositionAttribute, displayTextureCoordinateAttribute;
    GLint displayInputTextureUniform;

    CGSize inputImageSize;
    GLfloat imageVertices[8];
    GLfloat backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha;

    CGSize boundsSizeAtFrameBufferEpoch;
}

@property (assign, nonatomic) NSUInteger aspectRatio;

// Initialization and teardown
- (void)commonInit;

// Managing the display FBOs
- (void)createDisplayFramebuffer;
- (void)destroyDisplayFramebuffer;

// Handling fill mode
- (void)recalculateViewGeometry;

@end

@implementation GPUImageView

@synthesize aspectRatio;
@synthesize sizeInPixels = _sizeInPixels;
@synthesize fillMode = _fillMode;
@synthesize enabled;

// - MARK: <-- 初始化 -->
+ (Class)layerClass
{
	return [CAEAGLLayer class];
}

- (id)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame]))
    {
		return nil;
    }
    
    [self commonInit];
    
    return self;
}

-(id)initWithCoder:(NSCoder *)coder
{
	if (!(self = [super initWithCoder:coder])) 
    {
        return nil;
	}

    [self commonInit];

	return self;
}

/** 初始化OpenGLES 的 view 的设置 */
- (void)commonInit;
{
    // - openGLES 的显示图片的view的 初始化设置
    // Set scaling to account for Retina display	
    if ([self respondsToSelector:@selector(setContentScaleFactor:)])
    {
        self.contentScaleFactor = [[UIScreen mainScreen] scale];
    }

    inputRotation = kGPUImageNoRotation;
    self.opaque = YES;
    self.hidden = NO;
    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
    eaglLayer.opaque = YES;
    eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];

    self.enabled = YES;
    
    runSynchronouslyOnVideoProcessingQueue(^{
        
        // - 使用上下文
        [GPUImageContext useImageProcessingContext];
        
        // - 从 shaderProgramCache 中去 program 如果取到就直接取到, 没有取到就创建
        displayProgram = [[GPUImageContext sharedImageProcessingContext] programForVertexShaderString:kGPUImageVertexShaderString fragmentShaderString:kGPUImagePassthroughFragmentShaderString];
        
        /**
         initialized 字段, 如果这个 shader link过, initialized值为 YES, 否则 initialized 值为 NO;
         这里的 initialized 字段, 在 displayProgram 的初始化中, 值为 NO, 在调用 link 后值为 YES;
         */
        if (!displayProgram.initialized)
        {
            [displayProgram addAttribute:@"position"];
            [displayProgram addAttribute:@"inputTextureCoordinate"];
            
            if (![displayProgram link])
            {
                NSString *progLog = [displayProgram programLog];
                NSLog(@"Program link log: %@", progLog);
                NSString *fragLog = [displayProgram fragmentShaderLog];
                NSLog(@"Fragment shader compile log: %@", fragLog);
                NSString *vertLog = [displayProgram vertexShaderLog];
                NSLog(@"Vertex shader compile log: %@", vertLog);
                displayProgram = nil;
                NSAssert(NO, @"Filter shader link failed");
            }
        }
        
        // - 获取 shader 中属性的 id
        displayPositionAttribute = [displayProgram attributeIndex:@"position"];
        displayTextureCoordinateAttribute = [displayProgram attributeIndex:@"inputTextureCoordinate"];
        displayInputTextureUniform = [displayProgram uniformIndex:@"inputImageTexture"]; // This does assume a name of "inputTexture" for the fragment shader

        // - 使用 shaderprogram 开启顶点属性
        [GPUImageContext setActiveShaderProgram:displayProgram];
        glEnableVertexAttribArray(displayPositionAttribute);
        glEnableVertexAttribArray(displayTextureCoordinateAttribute);
        
        [self setBackgroundColorRed:0.0 green:0.0 blue:0.0 alpha:1.0];
        
        /** 设置缩放模式为保持源图像的纵横比 */
        _fillMode = kGPUImageFillModePreserveAspectRatio;
        
        // - 设置帧缓冲
        [self createDisplayFramebuffer];
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // The frame buffer needs to be trashed and re-created when the view size changes.
    if (!CGSizeEqualToSize(self.bounds.size, boundsSizeAtFrameBufferEpoch) &&
        !CGSizeEqualToSize(self.bounds.size, CGSizeZero)) {
        runSynchronouslyOnVideoProcessingQueue(^{
            
            // - 销毁上一次的帧缓冲
            [self destroyDisplayFramebuffer];
            
            // - 重新创建缓冲
            [self createDisplayFramebuffer];
        });
    } else if (!CGSizeEqualToSize(self.bounds.size, CGSizeZero)) {
        [self recalculateViewGeometry];
    }
}

- (void)dealloc
{
    runSynchronouslyOnVideoProcessingQueue(^{
        [self destroyDisplayFramebuffer];
    });
}

// - MARK: <-- framebuffer 操作 -->
/** 创建 framebuffer */
- (void)createDisplayFramebuffer;
{
    // - 使用当前的上下文
    [GPUImageContext useImageProcessingContext];
    
    /** 生成并绑定 framebuffer */
    glGenFramebuffers(1, &displayFramebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, displayFramebuffer);
	
    // - 生成并绑定 renderbuffer
    glGenRenderbuffers(1, &displayRenderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, displayRenderbuffer);
	
    // - 将可绘制对象的存储绑定到 renderbuffer对象上。
    [[[GPUImageContext sharedImageProcessingContext] context] renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
    
    // - 获取 renderbuffer 的宽和高
    GLint backingWidth, backingHeight;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    
    // - 如果宽高为 0, 就销毁 framebuffer
    if ( (backingWidth == 0) || (backingHeight == 0) )
    {
        [self destroyDisplayFramebuffer];
        return;
    }
    
    _sizeInPixels.width = (CGFloat)backingWidth;
    _sizeInPixels.height = (CGFloat)backingHeight;

//    NSLog(@"Backing width: %d, height: %d", backingWidth, backingHeight);

    // - 将 renderbuffer 附加到 framebuffer 中
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, displayRenderbuffer);
	
    // - 检查 framebuffer 的创建状态, 如果创建失败, 就直接报错
    __unused GLuint framebufferCreationStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    NSAssert(framebufferCreationStatus == GL_FRAMEBUFFER_COMPLETE, @"Failure with display framebuffer generation for display of size: %f, %f", self.bounds.size.width, self.bounds.size.height);
    boundsSizeAtFrameBufferEpoch = self.bounds.size;

    [self recalculateViewGeometry];
}

/** 销毁 framebuffer */
- (void)destroyDisplayFramebuffer;
{
    [GPUImageContext useImageProcessingContext];

    if (displayFramebuffer)
	{
		glDeleteFramebuffers(1, &displayFramebuffer);
		displayFramebuffer = 0;
	}
	
	if (displayRenderbuffer)
	{
		glDeleteRenderbuffers(1, &displayRenderbuffer);
		displayRenderbuffer = 0;
	}
}

/** 设置显示的 farmebuffer 并设置视口大小 */
- (void)setDisplayFramebuffer;
{
    // - 如果没有 framebuffer, 就创建 framebuffer
    if (!displayFramebuffer)
    {
        [self createDisplayFramebuffer];
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, displayFramebuffer);
    
    glViewport(0, 0, (GLint)_sizeInPixels.width, (GLint)_sizeInPixels.height);
}

/** 将渲染的结果呈现在屏幕上 */
- (void)presentFramebuffer;
{
    glBindRenderbuffer(GL_RENDERBUFFER, displayRenderbuffer);
    [[GPUImageContext sharedImageProcessingContext] presentBufferForDisplay];
}

#pragma mark -
#pragma mark Handling fill mode

- (void)recalculateViewGeometry;
{
    runSynchronouslyOnVideoProcessingQueue(^{
        CGFloat heightScaling, widthScaling;
        
        CGSize currentViewSize = self.bounds.size;
        
        //    CGFloat imageAspectRatio = inputImageSize.width / inputImageSize.height;
        //    CGFloat viewAspectRatio = currentViewSize.width / currentViewSize.height;
        
        CGRect insetRect = AVMakeRectWithAspectRatioInsideRect(inputImageSize, self.bounds);
        
        /**
         如果 kGPUImageFillModeStretch 缩放的系数是 1.0
         如果 kGPUImageFillModePreserveAspectRatio 等比例缩放
         如果 kGPUImageFillModePreserveAspectRatioAndFill 等比例缩放并且填满屏幕
         */
        switch(_fillMode)
        {
            case kGPUImageFillModeStretch:
            {
                widthScaling = 1.0;
                heightScaling = 1.0;
            }; break;
            case kGPUImageFillModePreserveAspectRatio:
            {
                widthScaling = insetRect.size.width / currentViewSize.width;
                heightScaling = insetRect.size.height / currentViewSize.height;
            }; break;
            case kGPUImageFillModePreserveAspectRatioAndFill:
            {
                //            CGFloat widthHolder = insetRect.size.width / currentViewSize.width;
                widthScaling = currentViewSize.height / insetRect.size.height;
                heightScaling = currentViewSize.width / insetRect.size.width;
            }; break;
        }
        
        // - 纹理顶点缩放系数
        imageVertices[0] = -widthScaling;
        imageVertices[1] = -heightScaling;
        imageVertices[2] = widthScaling;
        imageVertices[3] = -heightScaling;
        imageVertices[4] = -widthScaling;
        imageVertices[5] = heightScaling;
        imageVertices[6] = widthScaling;
        imageVertices[7] = heightScaling;
    });
    
//    static const GLfloat imageVertices[] = {
//        -1.0f, -1.0f,
//        1.0f, -1.0f,
//        -1.0f,  1.0f,
//        1.0f,  1.0f,
//    };
}

/** 设置背景色 */
- (void)setBackgroundColorRed:(GLfloat)redComponent green:(GLfloat)greenComponent blue:(GLfloat)blueComponent alpha:(GLfloat)alphaComponent;
{
    backgroundColorRed = redComponent;
    backgroundColorGreen = greenComponent;
    backgroundColorBlue = blueComponent;
    backgroundColorAlpha = alphaComponent;
}

/** 根据旋转模式获取纹理坐标 */
+ (const GLfloat *)textureCoordinatesForRotation:(GPUImageRotationMode)rotationMode;
{
//    static const GLfloat noRotationTextureCoordinates[] = {
//        0.0f, 0.0f,
//        1.0f, 0.0f,
//        0.0f, 1.0f,
//        1.0f, 1.0f,
//    };
    
    static const GLfloat noRotationTextureCoordinates[] = {
        0.0f, 1.0f,
        1.0f, 1.0f,
        0.0f, 0.0f,
        1.0f, 0.0f,
    };

    static const GLfloat rotateRightTextureCoordinates[] = {
        1.0f, 1.0f,
        1.0f, 0.0f,
        0.0f, 1.0f,
        0.0f, 0.0f,
    };

    static const GLfloat rotateLeftTextureCoordinates[] = {
        0.0f, 0.0f,
        0.0f, 1.0f,
        1.0f, 0.0f,
        1.0f, 1.0f,
    };
        
    static const GLfloat verticalFlipTextureCoordinates[] = {
        0.0f, 0.0f,
        1.0f, 0.0f,
        0.0f, 1.0f,
        1.0f, 1.0f,
    };
    
    static const GLfloat horizontalFlipTextureCoordinates[] = {
        1.0f, 1.0f,
        0.0f, 1.0f,
        1.0f, 0.0f,
        0.0f, 0.0f,
    };
    
    static const GLfloat rotateRightVerticalFlipTextureCoordinates[] = {
        1.0f, 0.0f,
        1.0f, 1.0f,
        0.0f, 0.0f,
        0.0f, 1.0f,
    };
    
    static const GLfloat rotateRightHorizontalFlipTextureCoordinates[] = {
        0.0f, 1.0f,
        0.0f, 0.0f,
        1.0f, 1.0f,
        1.0f, 0.0f,
    };

    static const GLfloat rotate180TextureCoordinates[] = {
        1.0f, 0.0f,
        0.0f, 0.0f,
        1.0f, 1.0f,
        0.0f, 1.0f,
    };
    
    // - 返回纹理的顶点坐标
    switch(rotationMode)
    {
        case kGPUImageNoRotation: return noRotationTextureCoordinates;
        case kGPUImageRotateLeft: return rotateLeftTextureCoordinates;
        case kGPUImageRotateRight: return rotateRightTextureCoordinates;
        case kGPUImageFlipVertical: return verticalFlipTextureCoordinates;
        case kGPUImageFlipHorizonal: return horizontalFlipTextureCoordinates;
        case kGPUImageRotateRightFlipVertical: return rotateRightVerticalFlipTextureCoordinates;
        case kGPUImageRotateRightFlipHorizontal: return rotateRightHorizontalFlipTextureCoordinates;
        case kGPUImageRotate180: return rotate180TextureCoordinates;
    }
}

// - MARK: <-- GPUImageInput 协议方法 -->
/** /** OpenGLES 图形绘制并显示到屏幕上 */
- (void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex;
{
    runSynchronouslyOnVideoProcessingQueue(^{
        
        // - 激活 shader
        [GPUImageContext setActiveShaderProgram:displayProgram];
        [self setDisplayFramebuffer];
        
        // - 设置背景色 rgb, 清除颜色和深度缓冲
        glClearColor(backgroundColorRed, backgroundColorGreen, backgroundColorBlue, backgroundColorAlpha);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        
        // - 激活并绑定纹理
        glActiveTexture(GL_TEXTURE4);
        glBindTexture(GL_TEXTURE_2D, [inputFramebufferForDisplay texture]);
        glUniform1i(displayInputTextureUniform, 4);
        
        // - 设置shader 解析顶点的方式
        glVertexAttribPointer(displayPositionAttribute, 2, GL_FLOAT, 0, 0, imageVertices);
        glVertexAttribPointer(displayTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, [GPUImageView textureCoordinatesForRotation:inputRotation]);
        
        // - 根据要求绘制顶点
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        // - 将帧缓冲的数据呈现到屏幕上
        [self presentFramebuffer];
        
        [inputFramebufferForDisplay unlock];
        inputFramebufferForDisplay = nil;
    });
}

/** 下一个有效的纹理索引 */
- (NSInteger)nextAvailableTextureIndex;
{
    return 0;
}

/** 设置输入的帧缓冲对象以及纹理 */
- (void)setInputFramebuffer:(GPUImageFramebuffer *)newInputFramebuffer atIndex:(NSInteger)textureIndex;
{
    inputFramebufferForDisplay = newInputFramebuffer;
    [inputFramebufferForDisplay lock];
}

/** 设置输入的旋转模式 */
- (void)setInputRotation:(GPUImageRotationMode)newInputRotation atIndex:(NSInteger)textureIndex;
{
    inputRotation = newInputRotation;
}

/** 设置目标的尺寸 */
- (void)setInputSize:(CGSize)newSize atIndex:(NSInteger)textureIndex;
{
    runSynchronouslyOnVideoProcessingQueue(^{
        CGSize rotatedSize = newSize;
        
        if (GPUImageRotationSwapsWidthAndHeight(inputRotation))
        {
            rotatedSize.width = newSize.height;
            rotatedSize.height = newSize.width;
        }
        
        if (!CGSizeEqualToSize(inputImageSize, rotatedSize))
        {
            inputImageSize = rotatedSize;
            [self recalculateViewGeometry];
        }
    });
}

/** 纹理的最大输出尺寸 */
- (CGSize)maximumOutputSize;
{
    if ([self respondsToSelector:@selector(setContentScaleFactor:)])
    {
        CGSize pointSize = self.bounds.size;
        return CGSizeMake(self.contentScaleFactor * pointSize.width, self.contentScaleFactor * pointSize.height);
    }
    else
    {
        return self.bounds.size;
    }
}

/** 结束图片处理 */
- (void)endProcessing
{
}

/** 是否忽略渲染目标的更新 */
- (BOOL)shouldIgnoreUpdatesToThisTarget;
{
    return NO;
}

/** 是否为单色输入 */
- (BOOL)wantsMonochromeInput;
{
    return NO;
}

/** 设置单色输入 */
- (void)setCurrentlyReceivingMonochromeInput:(BOOL)newValue;
{
    
}


// - MARK: <-- getter 和 setter -->
/** 纹理尺寸 */
- (CGSize)sizeInPixels;
{
    if (CGSizeEqualToSize(_sizeInPixels, CGSizeZero))
    {
        return [self maximumOutputSize];
    }
    else
    {
        return _sizeInPixels;
    }
}

/** 填充模式 */
- (void)setFillMode:(GPUImageFillModeType)newValue;
{
    _fillMode = newValue;
    [self recalculateViewGeometry];
}

@end
