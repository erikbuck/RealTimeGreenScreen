//
//  GSVideoProcessor.m
//  GreenScreen
//
/*
Copyright (c) 2012 Erik M. Buck

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#import <MobileCoreServices/MobileCoreServices.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "GSVideoProcessor.h"

@interface GSVideoProcessor ()

// Redeclared as readwrite 
@property (readwrite) Float64 videoFrameRate;
@property (readwrite) CMVideoDimensions videoDimensions;
@property (readwrite) CMVideoCodecType videoType;
@property (readwrite) AVCaptureVideoOrientation videoOrientation;

@end

@implementation GSVideoProcessor

@synthesize delegate;
@synthesize videoFrameRate, videoDimensions, videoType;
@synthesize referenceOrientation;
@synthesize videoOrientation;


/////////////////////////////////////////////////////////////////
// 
- (id) init
{
    if (self = [super init])
    {
        previousSecondTimestamps = [[NSMutableArray alloc] init];
        referenceOrientation = AVCaptureVideoOrientationPortrait;
    }
    return self;
}


#pragma mark Utilities

/////////////////////////////////////////////////////////////////
// 
- (void) calculateFramerateAtTimestamp:(CMTime) timestamp
{
	[previousSecondTimestamps addObject:[NSValue valueWithCMTime:timestamp]];
    
	CMTime oneSecond = CMTimeMake( 1, 1 );
	CMTime oneSecondAgo = CMTimeSubtract( timestamp, oneSecond );
    
	while( CMTIME_COMPARE_INLINE( [[previousSecondTimestamps objectAtIndex:0]
      CMTimeValue], <, oneSecondAgo ) )
   {
		[previousSecondTimestamps removeObjectAtIndex:0];
   }
   
	Float64 newRate = (Float64) [previousSecondTimestamps count];
	self.videoFrameRate = (self.videoFrameRate + newRate) / 2;
}


/////////////////////////////////////////////////////////////////
// 
- (CGFloat)angleOffsetFromPortrait:(AVCaptureVideoOrientation)orientation
{
	CGFloat angle = 0.0;
	
	switch (orientation)
   {
		case AVCaptureVideoOrientationPortrait:
			angle = 0.0;
			break;
		case AVCaptureVideoOrientationPortraitUpsideDown:
			angle = M_PI;
			break;
		case AVCaptureVideoOrientationLandscapeRight:
			angle = -M_PI_2;
			break;
		case AVCaptureVideoOrientationLandscapeLeft:
			angle = M_PI_2;
			break;
		default:
			break;
	}

	return angle;
}


/////////////////////////////////////////////////////////////////
// 
- (CGAffineTransform)transformForOrientation:(AVCaptureVideoOrientation)orientation
{
	CGAffineTransform transform = CGAffineTransformIdentity;

	// Calculate offsets from an arbitrary reference orientation (portrait)
	CGFloat orientationAngleOffset =
      [self angleOffsetFromPortrait:orientation];
	CGFloat videoOrientationAngleOffset =
      [self angleOffsetFromPortrait:self.videoOrientation];
	
	// Find the difference in angle between the passed in orientation and the
   // current video orientation
	CGFloat angleOffset = orientationAngleOffset - videoOrientationAngleOffset;
	transform = CGAffineTransformMakeRotation(angleOffset);
	
	return transform;
}


#pragma mark Video Input

/////////////////////////////////////////////////////////////////
// 
- (BOOL)setupAssetWriterVideoInput:(CMFormatDescriptionRef)currentFormatDescription
{
	float bitsPerPixel;
	CMVideoDimensions dimensions =
      CMVideoFormatDescriptionGetDimensions(currentFormatDescription);
	int numPixels = dimensions.width * dimensions.height;
	int bitsPerSecond;
	
	// Assume that lower-than-SD resolutions are intended for streaming, and use
   // a lower bitrate
	if ( numPixels < (640 * 480) )
   {
		bitsPerPixel = 4.05; // matches quality of AVCaptureSessionPresetMedium.
   }
	else
   {
		bitsPerPixel = 11.4; // matches quality of AVCaptureSessionPresetHigh.
   }
	
	bitsPerSecond = numPixels * bitsPerPixel;
	
	NSDictionary *videoCompressionSettings =
      @{AVVideoCodecKey: AVVideoCodecH264,
      AVVideoWidthKey: @(dimensions.width),
      AVVideoHeightKey: @(dimensions.height),
      AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey:
         @(bitsPerSecond),
         AVVideoMaxKeyFrameIntervalKey: @30}};
      
	if ([assetWriter canApplyOutputSettings:videoCompressionSettings
      forMediaType:AVMediaTypeVideo])
   {
		assetWriterVideoIn = [[AVAssetWriterInput alloc]
         initWithMediaType:AVMediaTypeVideo
         outputSettings:videoCompressionSettings];
		assetWriterVideoIn.expectsMediaDataInRealTime = YES;
		assetWriterVideoIn.transform =
         [self transformForOrientation:self.referenceOrientation];
         
		if ([assetWriter canAddInput:assetWriterVideoIn])
      {
			[assetWriter addInput:assetWriterVideoIn];
      }
		else
      {
			NSLog(@"Couldn't add asset writer video input.");
            return NO;
		}
	}
	else
   {
		NSLog(@"Couldn't apply video output settings.");
        return NO;
	}
    
    return YES;
}


#pragma mark Capture

/////////////////////////////////////////////////////////////////
// 
- (void)captureOutput:(AVCaptureOutput *)captureOutput
   didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
   fromConnection:(AVCaptureConnection *)connection
{	
	CMFormatDescriptionRef formatDescription =
      CMSampleBufferGetFormatDescription(sampleBuffer);
    
	if ( connection == videoConnection )
   {		
		// Get framerate
		CMTime timestamp = CMSampleBufferGetPresentationTimeStamp( sampleBuffer );
		[self calculateFramerateAtTimestamp:timestamp];
        
		// Get frame dimensions (for onscreen display)
		if (self.videoDimensions.width == 0 && self.videoDimensions.height == 0)
      {
			self.videoDimensions =
            CMVideoFormatDescriptionGetDimensions( formatDescription );
		}
      
		// Get buffer type
		if ( self.videoType == 0 )
      {
			self.videoType =
            CMFormatDescriptionGetMediaSubType( formatDescription );
      }
      
		// Enqueue it for preview.  This is a shallow queue, so if image
      // processing is taking too long, we'll drop this frame for preview (this
      // keeps preview latency low).
		OSStatus err = CMBufferQueueEnqueue(previewBufferQueue, sampleBuffer);
		if ( !err ) {        
			dispatch_async(dispatch_get_main_queue(), ^{
				CMSampleBufferRef sbuf =
               (CMSampleBufferRef)CMBufferQueueDequeueAndRetain(
                  previewBufferQueue);
                  
				if (sbuf)
            {
					CVImageBufferRef pixBuf = CMSampleBufferGetImageBuffer(sbuf);
					[self.delegate pixelBufferReadyForDisplay:pixBuf];
					CFRelease(sbuf);
				}
			});
		}
	}
    
	CFRetain(sampleBuffer);
	CFRetain(formatDescription);
	dispatch_async(movieWritingQueue,
   ^{
		if ( assetWriter )
      {
			if (connection == videoConnection)
         {				
				// Initialize the video input if this is not done yet
				if (!readyToRecordVideo)
            {
					readyToRecordVideo =
                  [self setupAssetWriterVideoInput:formatDescription];
            }
         }
		}
      
		CFRelease(sampleBuffer);
		CFRelease(formatDescription);
	});
}


/////////////////////////////////////////////////////////////////
// 
- (AVCaptureDevice *)videoDeviceWithPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices)
        if ([device position] == position)
            return device;
    
    return nil;
}


/////////////////////////////////////////////////////////////////
// 
- (BOOL) setupCaptureSession 
{
    /*
	 * Create capture session
	 */
    captureSession = [[AVCaptureSession alloc] init];
    
	/*
	 * Create video connection
	 */
   AVCaptureDeviceInput *videoIn = [[AVCaptureDeviceInput alloc]
      initWithDevice:[self videoDeviceWithPosition:AVCaptureDevicePositionBack]
      error:nil];
       
   if ([captureSession canAddInput:videoIn])
   {
      [captureSession addInput:videoIn];
   }
    
	AVCaptureVideoDataOutput *videoOut = [[AVCaptureVideoDataOutput alloc] init];
	/*
		Processing can take longer than real-time on some platforms.
		Clients whose image processing is faster than real-time should consider 
      setting AVCaptureVideoDataOutput's alwaysDiscardsLateVideoFrames property 
      to NO. 
	 */
	[videoOut setAlwaysDiscardsLateVideoFrames:YES];
	[videoOut setVideoSettings:
      @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
	dispatch_queue_t videoCaptureQueue =
      dispatch_queue_create("Video Capture Queue", DISPATCH_QUEUE_SERIAL);
	[videoOut setSampleBufferDelegate:self queue:videoCaptureQueue];
	//dispatch_release(videoCaptureQueue);
	if ([captureSession canAddOutput:videoOut])
		[captureSession addOutput:videoOut];
	videoConnection = [videoOut connectionWithMediaType:AVMediaTypeVideo];
	self.videoOrientation = [videoConnection videoOrientation];
    
	return YES;
}


/////////////////////////////////////////////////////////////////
// 
- (void) setupAndStartCaptureSession
{
	// Create a shallow queue for buffers going to the display for preview.
	OSStatus err = CMBufferQueueCreate(
      kCFAllocatorDefault,
      1,
      CMBufferQueueGetCallbacksForUnsortedSampleBuffers(),
      &previewBufferQueue);
      
	if (err)
   {
		[self showError:[NSError errorWithDomain:NSOSStatusErrorDomain
         code:err
         userInfo:nil]];
   }
	
	// Create serial queue for movie writing
	movieWritingQueue =
      dispatch_queue_create("Movie Writing Queue", DISPATCH_QUEUE_SERIAL);
	
    if ( !captureSession )
    {
		 [self setupCaptureSession];
    }
	
    [[NSNotificationCenter defaultCenter]
       addObserver:self
       selector:@selector(captureSessionStoppedRunningNotification:)
       name:AVCaptureSessionDidStopRunningNotification
       object:captureSession];
	
	if ( !captureSession.isRunning )
   {
		[captureSession startRunning];
   }
}


/////////////////////////////////////////////////////////////////
// 
- (void)captureSessionStoppedRunningNotification:(NSNotification *)notification
{
	dispatch_async(movieWritingQueue, ^{
	});
}


/////////////////////////////////////////////////////////////////
// 
- (void) stopAndTearDownCaptureSession
{
   [captureSession stopRunning];
	if (captureSession)
   {
		[[NSNotificationCenter defaultCenter]
         removeObserver:self
         name:AVCaptureSessionDidStopRunningNotification
         object:captureSession];
   }
   
	captureSession = nil;
	if (previewBufferQueue)
   {
		CFRelease(previewBufferQueue);
		previewBufferQueue = NULL;	
	}
   
	if (movieWritingQueue)
   {
		//dispatch_release(movieWritingQueue);
		movieWritingQueue = NULL;
	}
}


#pragma mark Error Handling

/////////////////////////////////////////////////////////////////
// 
- (void)showError:(NSError *)error
{
    CFRunLoopPerformBlock(
       CFRunLoopGetMain(),
       kCFRunLoopCommonModes,
       ^(void)
       {
          UIAlertView *alertView =
             [[UIAlertView alloc] initWithTitle:
                [error localizedDescription]
                message:[error localizedFailureReason]
                delegate:nil
                cancelButtonTitle:@"OK"
                otherButtonTitles:nil];
        [alertView show];
    });
}

@end
