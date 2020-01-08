//
//  ViewController.m
//  GPUDemo
//
//  Created by 李超群 on 2019/11/21.
//  Copyright © 2019 李超群. All rights reserved.
//

#import "ViewController.h"
#import "GPUImage.h"
#import "GPUImageVideoCamera.h"


@interface ViewController ()
// - MARK: <-- 默认的设置 -->
@property (nonatomic, copy) void(^valueChanged)(UISlider *slider);

/** <#注释#> */
@property (nonatomic, strong) GPUImageView *imageView;

/** <#注释#> */
@property (nonatomic, strong) UISlider *slider;


// - MARK: <-- 简单使用 GPUImageVideoCamera  -->
@property (nonatomic, strong) GPUImageVideoCamera *camera;


// - MARK: <-- GPUImageFilterGroup -->
@property (nonatomic, strong) GPUImageFilterGroup *myFilterGroup;


// - MARK: <-- 简单使用 GPUImageMovie -->
@property(nonatomic, strong)GPUImageMovie *movie;

@end

@implementation ViewController

-(void)updateSliderValue:(UISlider *)slider{
    !self.valueChanged ? : self.valueChanged(slider);
}

// - MARK: <-- 默认设置 -->
-(void)defaultSetting{
    
    // - 默认尺寸
    CGRect mainScreenFrame = [[UIScreen mainScreen] bounds];

    // - 显示图片的 view
    self.imageView = [[GPUImageView alloc] initWithFrame:mainScreenFrame];
    [self.view addSubview:self.imageView];
    
    // - 调节的 slider
    self.slider = [[UISlider alloc] initWithFrame:CGRectMake(25.0, mainScreenFrame.size.height - 50.0, mainScreenFrame.size.width - 50.0, 40.0)];
    [self.slider addTarget:self action:@selector(updateSliderValue:) forControlEvents:UIControlEventValueChanged];
    self.slider.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.slider];
}

// - MARK: <-- 简单使用 GPUImagePicture -->
-(void)test1{
    UIImage *inputImage = [UIImage imageNamed:@"gyy"];
    GPUImagePicture *sourcePicture = [[GPUImagePicture alloc] initWithImage:inputImage];

    GPUImageBrightnessFilter *filter1 = [[GPUImageBrightnessFilter alloc] init];
    GPUImageSepiaFilter *filter2 = [[GPUImageSepiaFilter alloc] init];
    
    [sourcePicture addTarget:filter1];
    [filter1 addTarget:filter2];
    [filter2 addTarget:self.imageView];
    
    [sourcePicture processImage];
    
    self.valueChanged = ^(UISlider *slider) {
        CGFloat midpoint = [(UISlider *)slider value];
        filter2.intensity = midpoint;
        filter1.brightness = midpoint;
        [sourcePicture processImage];
    };

}

// - MARK: <-- 简单使用 GPUImageVideoCamera 和 GPUImageMovieWriter -->
-(void)test2{
    GPUImageVideoCamera *videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:AVCaptureSessionPreset640x480 cameraPosition:AVCaptureDevicePositionFront];
    self.camera = videoCamera;
    
    GPUImageSepiaFilter *filter = [[GPUImageSepiaFilter alloc] init];
    filter.intensity = 4;
    GPUImageBrightnessFilter *filter1 = [[GPUImageBrightnessFilter alloc]init];
    filter1.brightness = 0.8;

    [videoCamera addTarget:filter];
    [filter addTarget:filter1];
    [filter1 addTarget:self.imageView];

    [videoCamera startCameraCapture];
    
    self.slider.minimumValue = -1.0;
    self.slider.maximumValue = 1.0;
    self.slider.value = 0.1;

    self.valueChanged = ^(UISlider *slider) {
        CGFloat midpoint = [(UISlider *)slider value];
        filter1.brightness = midpoint;
    };
    
    // - 本地录制
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/ZBMovied%u.mp4", arc4random() % 1000]];
    GPUImageMovieWriter *movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:[NSURL fileURLWithPath:path] size:CGSizeMake(480.0, 640.0)];
    [filter addTarget:movieWriter];
    [movieWriter startRecording];
}

// - MARK: <-- GPUImageFilterGroup -->
-(void)test3{
     //加载一个UIImage对象
    UIImage *image = [UIImage imageNamed:@"gyy"];
    
    //初始化GPUImagePicture
    GPUImagePicture *picture = [[GPUImagePicture alloc] initWithImage:image smoothlyScaleOutput:YES];
    
    GPUImageColorInvertFilter *invertFilter = [[GPUImageColorInvertFilter alloc] init];
    GPUImageGammaFilter *gammaFilter = [[GPUImageGammaFilter alloc]init];
    gammaFilter.gamma = 0.2;
    GPUImageExposureFilter *exposureFilter = [[GPUImageExposureFilter alloc]init];
    exposureFilter.exposure = -1.0;
    GPUImageSepiaFilter *sepiaFilter = [[GPUImageSepiaFilter alloc] init];
    
    self.myFilterGroup = [[GPUImageFilterGroup alloc] init];
    [self addGPUImageFilter:invertFilter];
    [self addGPUImageFilter:gammaFilter];
    [self addGPUImageFilter:exposureFilter];
    [self addGPUImageFilter:sepiaFilter];
    
    [picture addTarget:self.myFilterGroup];
    [self.myFilterGroup addTarget:self.imageView];

    [picture processImage];
}

- (void)addGPUImageFilter:(GPUImageFilter *)filter{
    [self.myFilterGroup addFilter:filter];
    
    [self.myFilterGroup addTarget:filter];
    self.myFilterGroup.terminalFilter = filter;
    if (!self.myFilterGroup.initialFilters){
        self.myFilterGroup.initialFilters = @[filter];
    }
    
    /** 这里觉得GPUImageFilterGroup 这个类的 -(void)addFilter:(GPUImageOutput<GPUImageInput> *)newFilter; 方法可以改为以下写法, 用起来就会很舒服, 其他人使用时候不用关心具体的实现
     - (void)addFilter:(GPUImageOutput<GPUImageInput> *)newFilter;
     {
         [filters addObject:newFilter];
         self.initialFilters = @[filters[0]];
         [self.terminalFilter addTarget:newFilter];
         self.terminalFilter = newFilter;
     }
     */

}
// - MARK: <-- GPUImageUIElement -->
-(void)test4{
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(100, 480, 120, 20)];
    lab.text = @"滤镜信息";
    lab.font = [UIFont systemFontOfSize:20];
    lab.textColor = [UIColor redColor];
    lab.backgroundColor = [UIColor greenColor];
    UIView *view = [[UIView alloc] initWithFrame:self.view.bounds];
    view.backgroundColor = [UIColor greenColor];
    [view addSubview:lab];

    UIImage *inputImage = [UIImage imageNamed:@"gyy"];
    GPUImagePicture *sourcePicture = [[GPUImagePicture alloc] initWithImage:inputImage];
    GPUImageBrightnessFilter *filter = [[GPUImageBrightnessFilter alloc] init];
    GPUImageAlphaBlendFilter *filter1 = [[GPUImageAlphaBlendFilter alloc] init];
    GPUImageUIElement *element = [[GPUImageUIElement alloc] initWithView:view];

    [sourcePicture addTarget:filter];
    [filter addTarget:filter1];
    [element addTarget:filter1];
    [filter1 addTarget:self.imageView];
    
    [element update];
    [sourcePicture processImage];
}

// - MARK: <-- 简单使用 GPUImageStillCamera -->
-(void)test5{
    GPUImageStillCamera *videoCamera = [[GPUImageStillCamera alloc] initWithSessionPreset:AVCaptureSessionPresetHigh cameraPosition:AVCaptureDevicePositionFront];
    self.camera = videoCamera;
    
    GPUImageSepiaFilter *filter = [[GPUImageSepiaFilter alloc] init];
    filter.intensity = 4;
    GPUImageBrightnessFilter *filter1 = [[GPUImageBrightnessFilter alloc]init];
    filter1.brightness = 0.8;

    [videoCamera addTarget:filter];
    [filter addTarget:filter1];
    [filter1 addTarget:self.imageView];

    [videoCamera startCameraCapture];
    
    [NSTimer scheduledTimerWithTimeInterval:10 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [videoCamera capturePhotoAsImageProcessedUpToFilter:filter withCompletionHandler:^(UIImage *processedImage, NSError *error) {
            UIImage *img = processedImage;
            NSLog(@"xx");
        }];
    }];
}

// - MARK: <-- 简单使用 GPUImageMovie -->
-(void)test6{
    GPUImageMovie *movie = [[GPUImageMovie alloc]initWithURL:[[NSBundle mainBundle] URLForResource:@"example" withExtension:@"mp4" subdirectory:nil]];
    self.movie = movie;
    GPUImageToonFilter *filter = [[GPUImageToonFilter alloc] init];

    [movie addTarget:filter];
    [filter addTarget:self.imageView];

    [movie startProcessing];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self defaultSetting];
    
    [self test5];
}

@end
