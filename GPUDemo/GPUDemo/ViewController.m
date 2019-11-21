//
//  ViewController.m
//  GPUDemo
//
//  Created by 李超群 on 2019/11/21.
//  Copyright © 2019 李超群. All rights reserved.
//

#import "ViewController.h"
#import "GPUImage.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    UIImage *inputImage = [UIImage imageNamed:@"gyy"];
    GPUImageView * imageView = [[GPUImageView alloc] initWithFrame:self.view.bounds];
    self.view = imageView;

    GPUImagePicture *sourcePicture = [[GPUImagePicture alloc] initWithImage:inputImage smoothlyScaleOutput:YES];
    GPUImageTiltShiftFilter *sepiaFilter = [[GPUImageTiltShiftFilter alloc] init];
    [sepiaFilter forceProcessingAtSize:imageView.sizeInPixels];
    [sourcePicture addTarget:sepiaFilter];
    [sepiaFilter addTarget:imageView];
    [sourcePicture processImage];

}


@end
