#import "GPUImageUIElement.h"

@interface GPUImageUIElement ()
{
    UIView *view;
    CALayer *layer;
    
    CGSize previousLayerSizeInPixels;
    CMTime time;
    NSTimeInterval actualTimeOfLastUpdate;
}

@end

@implementation GPUImageUIElement

// - MARK: <-- 初始化 -->
- (id)initWithView:(UIView *)inputView;
{
    if (!(self = [super init]))
    {
		return nil;
    }
    
    view = inputView;
    layer = inputView.layer;

    previousLayerSizeInPixels = CGSizeZero;
    [self update];
    
    return self;
}

- (id)initWithLayer:(CALayer *)inputLayer;
{
    if (!(self = [super init]))
    {
		return nil;
    }
    
    view = nil;
    layer = inputLayer;

    previousLayerSizeInPixels = CGSizeZero;
    [self update];

    return self;
}

/** layer 的尺寸 */
- (CGSize)layerSizeInPixels;
{
    CGSize pointSize = layer.bounds.size;
    return CGSizeMake(layer.contentsScale * pointSize.width, layer.contentsScale * pointSize.height);
}

/** 更新 */
- (void)update;
{
    [self updateWithTimestamp:kCMTimeIndefinite];
}
- (void)updateUsingCurrentTime;
{
    if(CMTIME_IS_INVALID(time)) {
        time = CMTimeMakeWithSeconds(0, 600);
        actualTimeOfLastUpdate = [NSDate timeIntervalSinceReferenceDate];
    } else {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval diff = now - actualTimeOfLastUpdate;
        time = CMTimeAdd(time, CMTimeMakeWithSeconds(diff, 600));
        actualTimeOfLastUpdate = now;
    }

    [self updateWithTimestamp:time];
}

- (void)updateWithTimestamp:(CMTime)frameTime;
{
    // - 使用 context
    [GPUImageContext useImageProcessingContext];
    CGSize layerPixelSize = [self layerSizeInPixels];
    
    // - 初始化内存空间
    GLubyte *imageData = (GLubyte *) calloc(1, (int)layerPixelSize.width * (int)layerPixelSize.height * 4);
    
    // - 色彩空间
    CGColorSpaceRef genericRGBColorspace = CGColorSpaceCreateDeviceRGB();
    
    // - 创建上下文
    CGContextRef imageContext = CGBitmapContextCreate(imageData, (int)layerPixelSize.width, (int)layerPixelSize.height, 8, (int)layerPixelSize.width * 4, genericRGBColorspace,  kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
//    CGContextRotateCTM(imageContext, M_PI_2);
    
    // - 旋转方向
	CGContextTranslateCTM(imageContext, 0.0f, layerPixelSize.height);
    CGContextScaleCTM(imageContext, layer.contentsScale, -layer.contentsScale);
    //        CGContextSetBlendMode(imageContext, kCGBlendModeCopy); // From Technical Q&A QA1708: http://developer.apple.com/library/ios/#qa/qa1708/_index.html
    
    // - 将 layer 绘制到 上下文中
    [layer renderInContext:imageContext];
    
    // - 绘制完释放
    CGContextRelease(imageContext);
    CGColorSpaceRelease(genericRGBColorspace);
    
    // TODO: This may not work
    // - 设置输出的 outputFramebuffer
    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:layerPixelSize textureOptions:self.outputTextureOptions onlyTexture:YES];

    // - 绑定并生成纹理
    glBindTexture(GL_TEXTURE_2D, [outputFramebuffer texture]);
    // no need to use self.outputTextureOptions here, we always need these texture options
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)layerPixelSize.width, (int)layerPixelSize.height, 0, GL_BGRA, GL_UNSIGNED_BYTE, imageData);
    
    free(imageData);
    
    // - 通知所有的 target 有新的纹理输出
    for (id<GPUImageInput> currentTarget in targets)
    {
        if (currentTarget != self.targetToIgnoreForUpdates)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [currentTarget setInputSize:layerPixelSize atIndex:textureIndexOfTarget];
            
            // - 设置 GPUImageTwoInputFilter 中 hasReceivedFirstFrame 或 hasReceivedSecondFrame 的值, 只有这两个值都为 YES 时候, 才可以正常渲染纹理, 所以在 [GPUImageUIElement addTarget:]时候, 需要重新调用下 update, 才能赋值 hasReceivedFirstFrame 或 hasReceivedSecondFrame;
            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
        }
    }    
}

@end
