#import "GPUImageFilterGroup.h"
#import "GPUImagePicture.h"

@implementation GPUImageFilterGroup

@synthesize terminalFilter = _terminalFilter;
@synthesize initialFilters = _initialFilters;
@synthesize inputFilterToIgnoreForUpdates = _inputFilterToIgnoreForUpdates;

- (id)init;
{
    if (!(self = [super init]))
    {
		return nil;
    }
    
    filters = [[NSMutableArray alloc] init];
    
    return self;
}

#pragma mark -
#pragma mark Filter management
/** 保存所有的滤镜 */
- (void)addFilter:(GPUImageOutput<GPUImageInput> *)newFilter;
{
    [filters addObject:newFilter];
}

- (GPUImageOutput<GPUImageInput> *)filterAtIndex:(NSUInteger)filterIndex;
{
    return [filters objectAtIndex:filterIndex];
}

- (NSUInteger)filterCount;
{
    return [filters count];
}

#pragma mark -
#pragma mark Still image processing

- (void)useNextFrameForImageCapture;
{
    [self.terminalFilter useNextFrameForImageCapture];
}

- (CGImageRef)newCGImageFromCurrentlyProcessedOutput;
{
    return [self.terminalFilter newCGImageFromCurrentlyProcessedOutput];
}

#pragma mark -
#pragma mark GPUImageOutput overrides

- (void)setTargetToIgnoreForUpdates:(id<GPUImageInput>)targetToIgnoreForUpdates;
{
    [_terminalFilter setTargetToIgnoreForUpdates:targetToIgnoreForUpdates];
}

/** 实现链式编程, (就是给每个 filter 添加一个新的 filter) */
- (void)addTarget:(id<GPUImageInput>)newTarget atTextureLocation:(NSInteger)textureLocation;
{
    [_terminalFilter addTarget:newTarget atTextureLocation:textureLocation];
}

- (void)removeTarget:(id<GPUImageInput>)targetToRemove;
{
    [_terminalFilter removeTarget:targetToRemove];
}

- (void)removeAllTargets;
{
    [_terminalFilter removeAllTargets];
}

- (NSArray *)targets;
{
    return [_terminalFilter targets];
}

- (void)setFrameProcessingCompletionBlock:(void (^)(GPUImageOutput *, CMTime))frameProcessingCompletionBlock;
{
    [_terminalFilter setFrameProcessingCompletionBlock:frameProcessingCompletionBlock];
}

- (void (^)(GPUImageOutput *, CMTime))frameProcessingCompletionBlock;
{
    return [_terminalFilter frameProcessingCompletionBlock];
}

#pragma mark -
#pragma mark GPUImageInput protocol
/** 链式编程的开始 (先调用 _initialFilter 的 newFrameReadyAtTime:atIndex:) 在 _initialFilter render 完成之后, 会调用 _initialFilter 的 targets 中的 BFilter, 然后调用 BFilter 的 newFrameReadyAtTime:atIndex: 在 BFilter render 完成之后, 会调用 BFilter 的 targets 中的 CFilter, 然后调用 CFilter 的 newFrameReadyAtTime:atIndex:, 一直循环下去, 直到target 为 GPUImageView 时候, 就会将所有的结果绘制到GPUImageView 中 */
/** 流程
 _initialFilter -> newFrameReadyAtTime:atIndex:
 */
- (void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex;
{
    for (GPUImageOutput<GPUImageInput> *currentFilter in _initialFilters)
    {
        if (currentFilter != self.inputFilterToIgnoreForUpdates)
        {
            [currentFilter newFrameReadyAtTime:frameTime atIndex:textureIndex];
        }
    }
}
/** 链式编程的开始 (设置 outputframebuffer 为下一个 filter 的firstFramebuffer) */
/**
 _initialFilter -> setInputFramebuffer:atIndex:
 */
- (void)setInputFramebuffer:(GPUImageFramebuffer *)newInputFramebuffer atIndex:(NSInteger)textureIndex;
{
    for (GPUImageOutput<GPUImageInput> *currentFilter in _initialFilters)
    {
        [currentFilter setInputFramebuffer:newInputFramebuffer atIndex:textureIndex];
    }
}

- (NSInteger)nextAvailableTextureIndex;
{
//    if ([_initialFilters count] > 0)
//    {
//        return [[_initialFilters objectAtIndex:0] nextAvailableTextureIndex];
//    }
    
    return 0;
}

- (void)setInputSize:(CGSize)newSize atIndex:(NSInteger)textureIndex;
{
    for (GPUImageOutput<GPUImageInput> *currentFilter in _initialFilters)
    {
        [currentFilter setInputSize:newSize atIndex:textureIndex];
    }
}

- (void)setInputRotation:(GPUImageRotationMode)newInputRotation atIndex:(NSInteger)textureIndex;
{
    for (GPUImageOutput<GPUImageInput> *currentFilter in _initialFilters)
    {
        [currentFilter setInputRotation:newInputRotation  atIndex:(NSInteger)textureIndex];
    }
}

- (void)forceProcessingAtSize:(CGSize)frameSize;
{
    for (GPUImageOutput<GPUImageInput> *currentFilter in filters)
    {
        [currentFilter forceProcessingAtSize:frameSize];
    }
}

- (void)forceProcessingAtSizeRespectingAspectRatio:(CGSize)frameSize;
{
    for (GPUImageOutput<GPUImageInput> *currentFilter in filters)
    {
        [currentFilter forceProcessingAtSizeRespectingAspectRatio:frameSize];
    }
}

- (CGSize)maximumOutputSize;
{
    // I'm temporarily disabling adjustments for smaller output sizes until I figure out how to make this work better
    return CGSizeZero;

    /*
    if (CGSizeEqualToSize(cachedMaximumOutputSize, CGSizeZero))
    {
        for (id<GPUImageInput> currentTarget in _initialFilters)
        {
            if ([currentTarget maximumOutputSize].width > cachedMaximumOutputSize.width)
            {
                cachedMaximumOutputSize = [currentTarget maximumOutputSize];
            }
        }
    }
    
    return cachedMaximumOutputSize;
     */
}

- (void)endProcessing;
{
    if (!isEndProcessing)
    {
        isEndProcessing = YES;
        
        for (id<GPUImageInput> currentTarget in _initialFilters)
        {
            [currentTarget endProcessing];
        }
    }
}

- (BOOL)wantsMonochromeInput;
{
    BOOL allInputsWantMonochromeInput = YES;
    for (GPUImageOutput<GPUImageInput> *currentFilter in _initialFilters)
    {
        allInputsWantMonochromeInput = allInputsWantMonochromeInput && [currentFilter wantsMonochromeInput];
    }
    
    return allInputsWantMonochromeInput;
}

- (void)setCurrentlyReceivingMonochromeInput:(BOOL)newValue;
{
    for (GPUImageOutput<GPUImageInput> *currentFilter in _initialFilters)
    {
        [currentFilter setCurrentlyReceivingMonochromeInput:newValue];
    }
}

@end
