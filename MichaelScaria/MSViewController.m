//
//  MSViewController.m
//  MichaelScaria
//
//  Created by Michael Scaria on 4/3/14.
//  Copyright (c) 2014 michaelscaria. All rights reserved.
//

#import "MSViewController.h"


#define BLACK_THRESHOLD 50


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
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"m" ofType:@"json"];
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    currentLetterData = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
    time = .5;
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
    
    
    currentImageBuffer = [self convertUIImageToBitmapRGBA8:[UIImage imageNamed:@"yc.png"]];
    
    
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

/*- (void)createLabelWithRect:(CGRect)rect {

    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *test = [[UILabel alloc] initWithFrame:rect];
//        test.backgroundColor = [UIColor clearColor];
        test.backgroundColor = [UIColor colorWithRed:.7 green:.4 blue:.3 alpha:.5];
        test.text = @"M";
        test.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:32];
        test.textColor = [UIColor whiteColor];
        [_overlayView addSubview:test];
    });
}
*/
/*- (NSArray*)getRGBAsFromImage:(UIImage*)image atX:(int)xx andY:(int)yy count:(int)count
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
    
    // First get the image into your data buffer
    CGImageRef imageRef = [image CGImage];
    NSUInteger width = CGImageGetWidth(imageRef);
    NSUInteger height = CGImageGetHeight(imageRef);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *rawData = (unsigned char*) calloc(height * width * 4, sizeof(unsigned char));
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                                                 bitsPerComponent, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
    CGContextRelease(context);
    
    // Now your rawData contains the image data in the RGBA8888 pixel format.
    int byteIndex = (bytesPerRow * yy) + xx * bytesPerPixel;
    for (int ii = 0 ; ii < count ; ++ii)
    {
        CGFloat red   = (rawData[byteIndex]     * 1.0) / 255.0;
        CGFloat green = (rawData[byteIndex + 1] * 1.0) / 255.0;
        CGFloat blue  = (rawData[byteIndex + 2] * 1.0) / 255.0;
        CGFloat alpha = (rawData[byteIndex + 3] * 1.0) / 255.0;
        byteIndex += 4;
        
        UIColor *acolor = [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
        [result addObject:acolor];
    }
    
    free(rawData);
    
    return result;
}*/


-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    
    if (!update) return;
    update = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        for (UIView *subview in _overlayView.subviews) {
            [subview removeFromSuperview];
        }
        update = YES;
    });
    
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    
    CVReturn lock = CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    if (lock == kCVReturnSuccess) {
        unsigned long w = 0; unsigned long h = 0; unsigned long r = 0;
//        int red = 52; int green = 170; int blue = 220;
        unsigned long bytesPerPixel = 0;
        unsigned char *buffer;
        //switch
//        h = CVPixelBufferGetWidth(pixelBuffer); w = CVPixelBufferGetHeight(pixelBuffer); r = CVPixelBufferGetBytesPerRow(pixelBuffer);
//        bytesPerPixel = r/h;
//        buffer = [self rotateBuffer:sampleBuffer];
        
        w = CVPixelBufferGetWidth(pixelBuffer);
        h = CVPixelBufferGetHeight(pixelBuffer);
        r = CVPixelBufferGetBytesPerRow(pixelBuffer);
        bytesPerPixel = r/w;
        buffer = CVPixelBufferGetBaseAddress(pixelBuffer);
        
        UIGraphicsBeginImageContext(CGSizeMake(w, h));
        CGContextRef c = UIGraphicsGetCurrentContext();
//        unsigned char* data = CGBitmapContextGetData(c);
        if (buffer != NULL) {
            for (int y = 0; y < h - 8; y++) {
                for (int x = 0; x < w - 8; x++) {
                    unsigned long offset = bytesPerPixel*((w*y)+x);
                    if (BLACK_PIXEL(buffer, offset)) { //is black
                        NSLog(@"%d %d %d", )
                        buffer[offset] = currentImageBuffer[offset];
                        buffer[offset + 1] = currentImageBuffer[offset + 1];
                        buffer[offset + 2] = currentImageBuffer[offset + 2];
                        buffer[offset + 3] = currentImageBuffer[offset + 3];
//                        data[offset] = currentImageBuffer[offset];
//                        data[offset + 1] = currentImageBuffer[offset + 1];
//                        data[offset + 2] = currentImageBuffer[offset + 2];
//                        data[offset + 3] = currentImageBuffer[offset + 3];
                    }
                    
                }
            }
            
            
        }
        if (connection == videoConnection) {
            if (self.videoType == 0) self.videoType = CMFormatDescriptionGetMediaSubType( formatDescription );
            CGColorSpaceRef colorSpaceRGB = CGColorSpaceCreateDeviceRGB();
            NSData *_pixelsData = [NSData dataWithBytesNoCopy:buffer length:(sizeof(unsigned char)*bytesPerPixel*w*h) freeWhenDone:NO ];
            CIImage *image = [[CIImage alloc] initWithBitmapData:_pixelsData bytesPerRow:(w*bytesPerPixel*sizeof(unsigned char)) size:CGSizeMake(w,h) format:kCIFormatARGB8 colorSpace:colorSpaceRGB];

            
            
            //                if (hasOverlay && NO) {
            //                    CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
            //                    [filter setValue:image forKey:kCIInputImageKey]; [filter setValue:@22.0f forKey:@"inputRadius"];
            //                    image = [filter valueForKey:kCIOutputImageKey];
            //                }
            CGAffineTransform transform = CGAffineTransformMakeRotation(-M_PI_2);
            image = [image imageByApplyingTransform:transform];
            CGColorSpaceRelease(colorSpaceRGB);
//
            
            
            
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
    time = 1.3;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        time = .5;
    });
}

#pragma mark - ImageStuff


- (unsigned char *) convertUIImageToBitmapRGBA8:(UIImage *) image {
	
	CGImageRef imageRef = image.CGImage;
	
	// Create a bitmap context to draw the uiimage into
	CGContextRef context = [self newBitmapRGBA8ContextFromImage:imageRef];
	
	if(!context) {
		return NULL;
	}
	
	size_t width = CGImageGetWidth(imageRef);
	size_t height = CGImageGetHeight(imageRef);
	
	CGRect rect = CGRectMake(0, 0, width, height);
	
	// Draw image into the context to get the raw image data
	CGContextDrawImage(context, rect, imageRef);
	
	// Get a pointer to the data
	unsigned char *bitmapData = (unsigned char *)CGBitmapContextGetData(context);
	
	// Copy the data and release the memory (return memory allocated with new)
	size_t bytesPerRow = CGBitmapContextGetBytesPerRow(context);
	size_t bufferLength = bytesPerRow * height;
	
	unsigned char *newBitmap = NULL;
	
	if(bitmapData) {
		newBitmap = (unsigned char *)malloc(sizeof(unsigned char) * bytesPerRow * height);
		
		if(newBitmap) {	// Copy the data
			for(int i = 0; i < bufferLength; ++i) {
				newBitmap[i] = bitmapData[i];
			}
		}
		
		free(bitmapData);
		
	} else {
		NSLog(@"Error getting bitmap pixel data\n");
	}
	
	CGContextRelease(context);
	
	return newBitmap;
}

- (CGContextRef) newBitmapRGBA8ContextFromImage:(CGImageRef) image {
	CGContextRef context = NULL;
	CGColorSpaceRef colorSpace;
	uint32_t *bitmapData;
	
	size_t bitsPerPixel = 32;
	size_t bitsPerComponent = 8;
	size_t bytesPerPixel = bitsPerPixel / bitsPerComponent;
	
	size_t width = CGImageGetWidth(image);
	size_t height = CGImageGetHeight(image);
	
	size_t bytesPerRow = width * bytesPerPixel;
	size_t bufferLength = bytesPerRow * height;
	
	colorSpace = CGColorSpaceCreateDeviceRGB();
	
	if(!colorSpace) {
		NSLog(@"Error allocating color space RGB\n");
		return NULL;
	}
	
	// Allocate memory for image data
	bitmapData = (uint32_t *)malloc(bufferLength);
	
	if(!bitmapData) {
		NSLog(@"Error allocating memory for bitmap\n");
		CGColorSpaceRelease(colorSpace);
		return NULL;
	}
	
	//Create bitmap context
	
	context = CGBitmapContextCreate(bitmapData,
                                    width,
                                    height,
                                    bitsPerComponent,
                                    bytesPerRow,
                                    colorSpace,
                                    kCGImageAlphaPremultipliedLast);	// RGBA
	if(!context) {
		free(bitmapData);
		NSLog(@"Bitmap context not created");
	}
	
	CGColorSpaceRelease(colorSpace);
	
	return context;
}

- (UIImage *) convertBitmapRGBA8ToUIImage:(unsigned char *) buffer
                                withWidth:(int) width
                               withHeight:(int) height {
	
	
	size_t bufferLength = width * height * 4;
	CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, buffer, bufferLength, NULL);
	size_t bitsPerComponent = 8;
	size_t bitsPerPixel = 32;
	size_t bytesPerRow = 4 * width;
	
	CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
	if(colorSpaceRef == NULL) {
		NSLog(@"Error allocating color space");
		CGDataProviderRelease(provider);
		return nil;
	}
	
	CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast;
	CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
	
	CGImageRef iref = CGImageCreate(width,
                                    height,
                                    bitsPerComponent,
                                    bitsPerPixel,
                                    bytesPerRow,
                                    colorSpaceRef,
                                    bitmapInfo,
                                    provider,	// data provider
                                    NULL,		// decode
                                    YES,			// should interpolate
                                    renderingIntent);
    
	uint32_t* pixels = (uint32_t*)malloc(bufferLength);
	
	if(pixels == NULL) {
		NSLog(@"Error: Memory not allocated for bitmap");
		CGDataProviderRelease(provider);
		CGColorSpaceRelease(colorSpaceRef);
		CGImageRelease(iref);
		return nil;
	}
	
	CGContextRef context = CGBitmapContextCreate(pixels,
                                                 width,
                                                 height,
                                                 bitsPerComponent,
                                                 bytesPerRow,
                                                 colorSpaceRef,
                                                 bitmapInfo);
	
	if(context == NULL) {
		NSLog(@"Error context not created");
		free(pixels);
	}
	
	UIImage *image = nil;
	if(context) {
		
		CGContextDrawImage(context, CGRectMake(0.0f, 0.0f, width, height), iref);
		
		CGImageRef imageRef = CGBitmapContextCreateImage(context);
		
		// Support both iPad 3.2 and iPhone 4 Retina displays with the correct scale
		if([UIImage respondsToSelector:@selector(imageWithCGImage:scale:orientation:)]) {
			float scale = [[UIScreen mainScreen] scale];
			image = [UIImage imageWithCGImage:imageRef scale:scale orientation:UIImageOrientationUp];
		} else {
			image = [UIImage imageWithCGImage:imageRef];
		}
		
		CGImageRelease(imageRef);
		CGContextRelease(context);
	}
	
	CGColorSpaceRelease(colorSpaceRef);
	CGImageRelease(iref);
	CGDataProviderRelease(provider);
	
	if(pixels) {
		free(pixels);
	}
	return image;
}



@end
