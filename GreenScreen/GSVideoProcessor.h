//
//  GSVideoProcessor.h
//  GreenScreen
//
/*
Copyright (c) 2012 Erik M. Buck

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CMBufferQueue.h>

@protocol GSVideoProcessorDelegate;

@interface GSVideoProcessor : NSObject <AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate> 
{  
    id <GSVideoProcessorDelegate> __weak delegate;
	
	NSMutableArray *previousSecondTimestamps;
	Float64 videoFrameRate;
	CMVideoDimensions videoDimensions;
	CMVideoCodecType videoType;

	AVCaptureSession *captureSession;
	AVCaptureConnection *videoConnection;
	CMBufferQueueRef previewBufferQueue;
	
	AVAssetWriter *assetWriter;
	AVAssetWriterInput *assetWriterVideoIn;
	dispatch_queue_t movieWritingQueue;
    
	AVCaptureVideoOrientation referenceOrientation;
	AVCaptureVideoOrientation videoOrientation;
    
   BOOL readyToRecordVideo;
}

@property (readwrite, weak) id <GSVideoProcessorDelegate> delegate;
@property (readonly) Float64 videoFrameRate;
@property (readonly) CMVideoDimensions videoDimensions;
@property (readonly) CMVideoCodecType videoType;

@property (readwrite) AVCaptureVideoOrientation referenceOrientation;

- (CGAffineTransform)transformForOrientation:(AVCaptureVideoOrientation)orientation;

- (void) showError:(NSError*)error;

- (void) setupAndStartCaptureSession;
- (void) stopAndTearDownCaptureSession;

@end


@protocol GSVideoProcessorDelegate <NSObject>

@required
- (void)pixelBufferReadyForDisplay:(CVPixelBufferRef)pixelBuffer;	// This method is always called on the main thread.

@end
