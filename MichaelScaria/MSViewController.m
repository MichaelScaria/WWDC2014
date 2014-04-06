//
//  MSViewController.m
//  MichaelScaria
//
//  Created by Michael Scaria on 4/3/14.
//  Copyright (c) 2014 michaelscaria. All rights reserved.
//

#import "MSViewController.h"


#define BLACK_THRESHOLD 35
static inline double radians (double degrees) {return degrees * M_PI/180;}

@interface MSViewController ()
@property (readwrite) CMVideoCodecType videoType;
@end

@implementation MSViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    hasOverlay = YES;
	self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    screenSize = [[UIScreen mainScreen] bounds].size;
    _cameraView.context = self.context;
    _cameraView.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    coreImageContext = [CIContext contextWithEAGLContext:self.context];
    
    glGenRenderbuffers(1, &_renderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderBuffer);
    
    NSError *error;
    self.device = [self videoDeviceWithPosition:AVCaptureDevicePositionBack];
    videoIn = [[AVCaptureDeviceInput alloc] initWithDevice:self.device error:&error];
    
    AVCaptureVideoDataOutput *videoOut = [[AVCaptureVideoDataOutput alloc] init];
    [videoOut setAlwaysDiscardsLateVideoFrames:YES];
    //    @{(id)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInt:kCVPixelFormatType_32BGRA]};
    [videoOut setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    [videoOut setSampleBufferDelegate:self queue:dispatch_queue_create("com.michaelscaria.VidLab Video", DISPATCH_QUEUE_SERIAL)];
    
    avCaptureSession = [[AVCaptureSession alloc] init];
    [avCaptureSession beginConfiguration];
    [avCaptureSession setSessionPreset:AVCaptureSessionPreset1280x720];
    if ([avCaptureSession canAddInput:videoIn]) [avCaptureSession addInput:videoIn];
    if ([avCaptureSession canAddOutput:videoOut]) [avCaptureSession addOutput:videoOut];
    videoConnection = [videoOut connectionWithMediaType:AVMediaTypeVideo];
    
    [avCaptureSession commitConfiguration];
    [avCaptureSession startRunning];
    
    [self setupCGContext];
    CGImageRef cgImg = CGBitmapContextCreateImage(cgContext);
    maskImage = [CIImage imageWithCGImage:cgImg];
    CGImageRelease(cgImg);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, .75 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        update = YES;
    });
    
    
    /*UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(takePicture)];
    tap.numberOfTapsRequired = 2;
*/
    
    //    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, .25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    //        [self goToCamera];
    //    });
}

- (AVCaptureDevice *)videoDeviceWithPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *aDevice in devices)
        if ([aDevice position] == position)
            return aDevice;
    
    return nil;
}

-(void)setupCGContext {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * screenSize.width;
    NSUInteger bitsPerComponent = 8;
    NSLog(@"%lu %f", (unsigned long)bytesPerRow, screenSize.width);
    cgContext = CGBitmapContextCreate(NULL, screenSize.width, screenSize.height, bitsPerComponent, bytesPerRow, colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    if (!cgContext) {
        NSLog(@"nil");
    }
    CGColorSpaceRelease(colorSpace);
}



#pragma mark Capture

- (unsigned char*) rotateBuffer: (CMSampleBufferRef) sampleBuffer
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer,0);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    size_t currSize = bytesPerRow*height*sizeof(unsigned char);
    size_t bytesPerRowOut = 4*height*sizeof(unsigned char);
    
    void *srcBuff = CVPixelBufferGetBaseAddress(imageBuffer);
    
    /*
     * rotationConstant:   0 -- rotate 0 degrees (simply copy the data from src to dest)
     *             1 -- rotate 90 degrees counterclockwise
     *             2 -- rotate 180 degress
     *             3 -- rotate 270 degrees counterclockwise
     */
    uint8_t rotationConstant = 3;
    
    unsigned char *outBuff = (unsigned char*)malloc(currSize);
    
    vImage_Buffer ibuff = { srcBuff, height, width, bytesPerRow};
    vImage_Buffer ubuff = { outBuff, width, height, bytesPerRowOut};
    Pixel_8888 backgroundColor = {0,0,0,0} ;
    vImage_Error err= vImageRotate90_ARGB8888 (&ibuff, &ubuff,rotationConstant, backgroundColor, kvImageNoFlags);
    if (err != kvImageNoError) NSLog(@"%ld", err);
    
    return outBuff;
}



-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    
    unsigned char *buffer;

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    
    CVReturn lock = CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    if (lock == kCVReturnSuccess) {
        unsigned long w = 0; unsigned long h = 0; unsigned long r = 0;
        int red = 52; int green = 170; int blue = 220;
        unsigned long bytesPerPixel = 0;
//            unsigned char *buffer;
        //switch
        h = CVPixelBufferGetWidth(pixelBuffer); w = CVPixelBufferGetHeight(pixelBuffer); r = CVPixelBufferGetBytesPerRow(pixelBuffer);
        bytesPerPixel = r/h;
        buffer = [self rotateBuffer:sampleBuffer];
        unsigned char *buffer;

        UIGraphicsBeginImageContext(CGSizeMake(w, h));
        CGContextRef c = UIGraphicsGetCurrentContext();
        unsigned char* data = CGBitmapContextGetData(c);
        NSLog(@"bytesPerPixel:%lu", bytesPerPixel);
        int final = 0;
        if (data != NULL) {
            
            for (int y = 0; y < h - 8; y++) {
                BOOL keyFound = NO; int xAxisKeyLength = 0;
                for (int x = 0; x < w - 8; x++) {
                    unsigned long offset = bytesPerPixel*((w*y)+x);
                    BOOL notBlack = (buffer[offset] > BLACK_THRESHOLD &&  buffer[offset+1] > BLACK_THRESHOLD &&  buffer[offset+2] > BLACK_THRESHOLD);
                    offset +=2;
                    if (!notBlack || YES) { //if black
                        if (!keyFound) keyFound = YES;
                        xAxisKeyLength++;
                    }
                    else if (keyFound) {
                        keyFound = NO;
                        int threshold = 100;
                        if (xAxisKeyLength > threshold) {
                            for (int yt = y; yt < y + xAxisKeyLength; yt++) {
                                for (int xt = x- xAxisKeyLength; xt < x; xt++) {
                                    //
                                    unsigned long tempOffset = bytesPerPixel*((w*yt)+xt);
                                    if (tempOffset < bytesPerPixel*((w*(h - 8))+(w - 8))) {
                                        buffer[tempOffset] = 235;
                                        buffer[tempOffset + 1] = 225;
                                        buffer[tempOffset + 2] = 255;
                                        buffer[tempOffset + 3] = 255;
                                    }
                                }
                            }

                            
                        }
                    }
                }
            }
            
            
        }
        if (connection == videoConnection) {
            if (self.videoType == 0) self.videoType = CMFormatDescriptionGetMediaSubType( formatDescription );
            CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
//                CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
            //        CGColorSpaceRef colorSpaceToUse = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
            CGColorSpaceRef colorSpaceRGB = CGColorSpaceCreateDeviceRGB();
            NSData *_pixelsData = [NSData dataWithBytesNoCopy:buffer length:(sizeof(unsigned char)*bytesPerPixel*w*h) freeWhenDone:YES ];
            CIImage *image = [[CIImage alloc] initWithBitmapData:_pixelsData bytesPerRow:(w*bytesPerPixel*sizeof(unsigned char)) size:CGSizeMake(w,h) format:kCIFormatARGB8 colorSpace:colorSpaceRGB];
            CGColorSpaceRelease(colorSpaceRGB);
//                if (hasOverlay && NO) {
//                    CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
//                    [filter setValue:image forKey:kCIInputImageKey]; [filter setValue:@22.0f forKey:@"inputRadius"];
//                    image = [filter valueForKey:kCIOutputImageKey];
//                }
//                CGAffineTransform transform = CGAffineTransformMakeRotation(-M_PI_2);
//                image = [image imageByApplyingTransform:transform];
            
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [coreImageContext drawImage:image inRect:CGRectMake(0, 0, screenSize.width*2, screenSize.height*2) fromRect:CGRectMake(0, -1280, 720, 1280)];
                [self.context presentRenderbuffer:GL_RENDERBUFFER];
            });
        }
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    NSLog(@"didReceiveMemoryWarning");
}


@end
