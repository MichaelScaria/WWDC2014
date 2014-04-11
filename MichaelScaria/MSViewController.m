//
//  MSViewController.m
//  MichaelScaria
//
//  Created by Michael Scaria on 4/3/14.
//  Copyright (c) 2014 michaelscaria. All rights reserved.
//

#import "MSViewController.h"


#define BLACK_THRESHOLD 45
#define ORIGINAL_TIME .3
#define MEMORY_TIME 1.2

//typedef NS_ENUM(NSInteger, STATUS) {
//    kInstructions,
//    kMe,
//    kHackathons
//};


static inline BOOL BLACK_PIXEL (unsigned char *buffer,  unsigned long offset) {return !(buffer[offset] > BLACK_THRESHOLD &&  buffer[offset+1] > BLACK_THRESHOLD &&  buffer[offset+2] > BLACK_THRESHOLD);}

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
    blur = YES;
    //get text values
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"m" ofType:@"json"];
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    information = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
    time = ORIGINAL_TIME;
    hasOverlay = YES;
    
    //set up camera view
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
    [videoOut setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    [videoOut setSampleBufferDelegate:self queue:dispatch_queue_create("com.michaelscaria.michaelscaria Video", DISPATCH_QUEUE_SERIAL)];
    
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
    
//    _textView.text = @"This app is a series of images followed by paragraphs about different aspects of my life. To make viewing the photo a little interesting to view, the photo only appears on dark pixels pulled in from your camera. Please tap to begin.";
    index = -1;
    index = 0;
    [self setUpOverlay];
}

- (void)setBufferWithImage:(UIImage *)image {
    CGImageRef imageRef = [image CGImage];
    NSUInteger width = CGImageGetWidth(imageRef);
    NSUInteger height = CGImageGetHeight(imageRef);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    currentImageBuffer = (unsigned char*) calloc(height * width * 4, sizeof(unsigned char));
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    CGContextRef context = CGBitmapContextCreate(currentImageBuffer, width, height,
                                                 bitsPerComponent, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
    CGContextRelease(context);
}

- (IBAction)overlayTapped:(id)sender {
    index++;
    if (index >= information.count) {
        index = 0;
    }
    index = 0;
    [self setBufferWithImage:[UIImage imageNamed:information[index][@"imageName"]]];
    for (UIView *subview in _alteredView.subviews) {
        [subview removeFromSuperview];
    }
    [UIView animateWithDuration:.5 animations:^{
        _overlayView.alpha = 0;
        _alteredView.alpha = 1;
    }completion:^(BOOL isCompleted){
        [self setUpOverlay];
        hasOverlay = NO;
    }];
}


- (IBAction)alteredTapped:(id)sender {
    hasOverlay = YES;
    for (UIView *subview in _alteredView.subviews) {
        [subview removeFromSuperview];
    }
    [UIView animateWithDuration:.5 animations:^{
        _alteredView.alpha = 0;
        _overlayView.alpha = 1;
    }completion:^(BOOL isCompleted){
    }];
}

- (void)setUpOverlay {
    for (UIView *subview in _scrollView.subviews) {
        [subview removeFromSuperview];
    }
    int yOffset = 0;
    NSArray *infoArray = information[index][@"info"];
    for (NSDictionary *info in infoArray) {
        NSString *type = info[@"type"];
        if ([type isEqualToString:@"header"]) {
            UIFont *textViewFont = [UIFont fontWithName:@"HelveticaNeue-Bold" size:25];
            CGRect textRect = [info[@"value"] boundingRectWithSize:CGSizeMake(300, MAXFLOAT) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:textViewFont} context:nil];
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, yOffset, textRect.size.width, textRect.size.height + 4)];
            label.text = info[@"value"];
            label.textColor = [UIColor whiteColor];
            label.font = textViewFont;
            label.lineBreakMode = NSLineBreakByWordWrapping;
            label.numberOfLines = 0;
            yOffset += label.frame.size.height;
            [_scrollView addSubview:label];

            
            UIView *line = [[UIView alloc] initWithFrame:CGRectMake(15, yOffset + 12, 290, .5)];
            line.backgroundColor = [UIColor whiteColor];
            yOffset += 11;
            [_scrollView addSubview:line];
        }
        else if ([type isEqualToString:@"text"]) {
            UIFont *textViewFont = [UIFont fontWithName:@"HelveticaNeue-Light" size:19];
            CGRect textRect = [info[@"value"] boundingRectWithSize:CGSizeMake(300, MAXFLOAT) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:textViewFont} context:nil];
            UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(10, yOffset, textRect.size.width, textRect.size.height + 60)];
            textView.font = textViewFont;
            textView.dataDetectorTypes = UIDataDetectorTypeLink; //fix this
            textView.text = info[@"value"];
            textView.backgroundColor = [UIColor clearColor];
            textView.scrollEnabled = NO;
            textView.editable = NO;
            textView.textColor = [UIColor whiteColor];
            yOffset += textView.frame.size.height;
            [_scrollView addSubview:textView];
        }
        else if ([type isEqualToString:@"image"]) {
            UIImage *image = [UIImage imageNamed:info[@"value"]];
            UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, yOffset, 320, image.size.height)];
            imageView.image = image;
            yOffset += imageView.frame.size.height;
            [_scrollView addSubview:imageView];
            
            if (info[@"subtitle"]) {
                UIFont *textViewFont = [UIFont fontWithName:@"HelveticaNeue-Italic" size:11];
                CGRect textRect = [info[@"subtitle"] boundingRectWithSize:CGSizeMake(300, MAXFLOAT) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:textViewFont} context:nil];
                UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, yOffset + 2, textRect.size.width, textRect.size.height + 4)];
                label.text = info[@"subtitle"];
                label.textAlignment = NSTextAlignmentCenter;
                label.textColor = [UIColor colorWithWhite:1 alpha:.9];
                label.font = textViewFont;
                label.lineBreakMode = NSLineBreakByWordWrapping;
                label.numberOfLines = 0;
                yOffset += label.frame.size.height + 2;
                [_scrollView addSubview:label];
            }
            
        }
        yOffset+=10;
    }
    _scrollView.contentSize = CGSizeMake(320, yOffset);
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
    
    if (!hasOverlay) {
        if (update) {
            update = NO;
            CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
            
            
            CVReturn lock = CVPixelBufferLockBaseAddress(pixelBuffer, 0);
            if (lock == kCVReturnSuccess) {
                unsigned long w = 0;
                unsigned long h = 0;
                unsigned long r = 0;
                unsigned long bytesPerPixel = 0;
                unsigned char *buffer;
                //switch
                h = CVPixelBufferGetWidth(pixelBuffer);
                w = CVPixelBufferGetHeight(pixelBuffer);
                r = CVPixelBufferGetBytesPerRow(pixelBuffer);
                bytesPerPixel = r/h;
                buffer = [self rotateBuffer:sampleBuffer];
                UIGraphicsBeginImageContext(CGSizeMake(w, h));
                CGContextRef c = UIGraphicsGetCurrentContext();
                unsigned char* data = CGBitmapContextGetData(c);
                if (data != NULL) {
                    
                    for (int y = 0; y < h - 4; y++) {
                        for (int x = 0; x < w - 4; x++) {
                            unsigned long offset = bytesPerPixel*((w*y)+x);
                            if (BLACK_PIXEL(buffer, offset)) {
                                data[offset] = currentImageBuffer[offset];
                                data[offset + 1] = currentImageBuffer[offset + 1];
                                data[offset + 2] = currentImageBuffer[offset + 2];
                                data[offset + 3] = currentImageBuffer[offset + 3];
                            }
                            else {
                                data[offset] = buffer[offset];
                                data[offset + 1] = buffer[offset + 1];
                                data[offset + 2] = buffer[offset + 2];
                                data[offset + 3] = buffer[offset + 3];
                            }
                            
                        }
                    }
                    
                    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
                    
                    UIGraphicsEndImageContext();
                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIImageView *imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
                        imageView.image = img;
                        [_alteredView addSubview:imageView];
                    });
                    
                }
                
            }
        }
        else if (!queuedUpdate) {
            queuedUpdate = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                queuedUpdate = NO;
                if (hasOverlay) return;
                for (UIView *subview in _alteredView.subviews) {
                    [subview removeFromSuperview];
                }
                update = YES;
            });
        }
    }
    
    if (connection == videoConnection) {
        if (self.videoType == 0) self.videoType = CMFormatDescriptionGetMediaSubType( formatDescription );
        CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
        if (hasOverlay && blur) {
            CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
            [filter setValue:image forKey:kCIInputImageKey]; [filter setValue:@18.0f forKey:@"inputRadius"];
            image = [filter valueForKey:kCIOutputImageKey];
        }
        CGAffineTransform transform = CGAffineTransformMakeRotation(-M_PI_2);
        image = [image imageByApplyingTransform:transform];
        
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [coreImageContext drawImage:image inRect:CGRectMake(0, 0, screenSize.width*2, screenSize.height*2) fromRect:CGRectMake(0, -1280, 720, 1280)];
            [self.context presentRenderbuffer:GL_RENDERBUFFER];
        });
    }
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    NSLog(@"didReceiveMemoryWarning");
    time = MEMORY_TIME;
    blur = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        time = ORIGINAL_TIME;
        blur = YES;
    });
}



@end
