//
//  MSViewController.h
//  MichaelScaria
//
//  Created by Michael Scaria on 4/3/14.
//  Copyright (c) 2014 michaelscaria. All rights reserved.
//

#import <UIKit/UIKit.h>

@import GLKit; @import AVFoundation; @import CoreVideo; @import Accelerate;

@interface MSViewController : UIViewController<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate> {
    AVCaptureSession *avCaptureSession;
    CIContext *coreImageContext;
    CIImage *maskImage;
    CGSize screenSize;
    CGContextRef cgContext;
    GLuint _renderBuffer;
    
    AVCaptureConnection *videoConnection;
    AVCaptureDeviceInput *videoIn;
    
    BOOL hasOverlay;
    BOOL update;
    BOOL blur;
    BOOL queuedUpdate;
    float time;
    unsigned char*currentImageBuffer;
    NSArray *information;
    int index;
}

@property (nonatomic, strong) AVCaptureDevice *device;
@property (strong, nonatomic) EAGLContext *context;

@property (strong, nonatomic) IBOutlet UIView *alteredView;
@property (strong, nonatomic) IBOutlet GLKView *cameraView;
@property (strong, nonatomic) IBOutlet UIView *overlayView;
@property (strong, nonatomic) IBOutlet UITextView *textView;
- (IBAction)overlayTapped:(id)sender;
- (IBAction)alteredTapped:(id)sender;

@end
