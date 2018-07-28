//
//  GSViewController.m
//  GreenScreen
//
/*
Copyright (c) 2012 Erik M. Buck

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#import "GSViewController.h"
#import "GSVideoProcessor.h"
#import "GSGreenScreenEffect.h"
#include <OpenGLES/ES2/glext.h>

@interface GSViewController ()
   <GSVideoProcessorDelegate>

@property (nonatomic, readwrite, strong) 
   GSVideoProcessor *videoProcessor;
@property (nonatomic, readwrite, assign) 
   CVOpenGLESTextureCacheRef videoTextureCache;
@property (strong, nonatomic) 
   GLKBaseEffect *baseEffect;
@property (strong, nonatomic) 
   GSGreenScreenEffect *greenScreenEffect;
@property (strong, nonatomic)
   GLKTextureInfo *background;

- (void)updateLabels;
- (UILabel *)labelWithText:(NSString *)text yPosition:(CGFloat)yPosition;

@end


@implementation GSViewController

@synthesize videoProcessor = videoProcessor_;
@synthesize videoTextureCache = videoTextureCache_;
@synthesize baseEffect = baseEffect_;


/////////////////////////////////////////////////////////////////
// 
- (void)viewDidLoad
{
   [super viewDidLoad];
	
   // Verify the type of view created automatically by the
   // Interface Builder storyboard
   GLKView *view = (GLKView *)self.view;
   NSAssert([view isKindOfClass:[GLKView class]],
      @"View controller's view is not a GLKView");
   
   // Create an OpenGL ES 2.0 context and provide it to the
   // view
   view.context = [[EAGLContext alloc] 
      initWithAPI:kEAGLRenderingAPIOpenGLES2];
   view.layer.opaque = YES;
   
   CAEAGLLayer *eaglLayer = (CAEAGLLayer *)view.layer;
   eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
      [NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking,
      kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat,
      nil];
   
   // Make the new context current
   [EAGLContext setCurrentContext:view.context];
   
   // Create a base effect that provides standard OpenGL ES 2.0
   // Shading Language programs and set constants to be used for 
   // all subsequent rendering
   self.greenScreenEffect = [[GSGreenScreenEffect alloc] init];
   
   // Create a base effect that provides standard OpenGL ES 2.0
   // Shading Language programs and set constants to be used for 
   // all subsequent rendering
   self.baseEffect = [[GLKBaseEffect alloc] init];

   if(nil == self.background)
   {
      self.background = [GLKTextureLoader textureWithCGImage:
         [[UIImage imageNamed:@"Elephant.jpg"] CGImage]
         options:nil
         error:NULL];
   }
   self.baseEffect.texture2d0.name = self.background.name;
   self.baseEffect.texture2d0.target = self.background.target;
      
   // Set the background color  
   glClearColor( 
      0.0f, // Red
      0.0f, // Green 
      0.0f, // Blue 
      0.0f);// Alpha
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
   
   //  Create a new CVOpenGLESTexture cache
   CVReturn err = CVOpenGLESTextureCacheCreate(
      kCFAllocatorDefault, 
      NULL, 
      (__bridge CVEAGLContext)((__bridge void *)view.context),
      NULL, 
      &videoTextureCache_);
      
   if (err) 
   {
      NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
   }
   
	// Keep track of changes to the device orientation so we can 
   // update the video processor
	NSNotificationCenter *notificationCenter = 
      [NSNotificationCenter defaultCenter];
	[notificationCenter addObserver:self 
      selector:@selector(deviceOrientationDidChange) 
      name:UIDeviceOrientationDidChangeNotification 
      object:nil];
	[[UIDevice currentDevice] 
      beginGeneratingDeviceOrientationNotifications];
		
   // Setup video processor
   self.videoProcessor = [[GSVideoProcessor alloc] init];
   self.videoProcessor.delegate = self;
   [self.videoProcessor setupAndStartCaptureSession];
}


/////////////////////////////////////////////////////////////////
// 
- (void)viewDidUnload
{
    NSNotificationCenter *notificationCenter = 
       [NSNotificationCenter defaultCenter];
	[notificationCenter removeObserver:self 
      name:UIDeviceOrientationDidChangeNotification 
      object:nil];
	[[UIDevice currentDevice] 
      endGeneratingDeviceOrientationNotifications];

   [super viewDidUnload];
   
   // Make the view's context current
   GLKView *view = (GLKView *)self.view;
   [EAGLContext setCurrentContext:view.context];
   
   // Stop using the context created in -viewDidLoad
   [EAGLContext setCurrentContext:nil];
   
   self.greenScreenEffect = nil;
   self.baseEffect = nil;
   [self.videoProcessor stopAndTearDownCaptureSession];
   self.videoProcessor.delegate = nil;
   self.videoProcessor = nil;
}


/////////////////////////////////////////////////////////////////
// 
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
   // Native video orientation is landscape with the button on the right.
   // The video processor rotates vide as needed, so don't autorotate also
   return (interfaceOrientation == UIInterfaceOrientationLandscapeRight);
}


/////////////////////////////////////////////////////////////////
// 
- (void)deviceOrientationDidChange
{
	UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
   
	// Don't update the reference orientation when the device orientation is
   // face up/down or unknown.
	if(UIDeviceOrientationIsPortrait(orientation))
   {
      [self.videoProcessor setReferenceOrientation:
         AVCaptureVideoOrientationPortrait];
   }
   else if(UIDeviceOrientationIsLandscape(orientation) )
   {
      [self.videoProcessor setReferenceOrientation:
         AVCaptureVideoOrientationLandscapeRight];
   }
}


#pragma mark - GLKView Delegate

/////////////////////////////////////////////////////////////////
// 
- (void)update
{
   [self updateLabels];
}


#pragma mark - Render Support

/////////////////////////////////////////////////////////////////
// 
- (CGRect)textureSamplingRectForCroppingTextureWithAspectRatio:
   (CGSize)textureAspectRatio 
   toAspectRatio:(CGSize)croppingAspectRatio
{
	CGRect normalizedSamplingRect = CGRectZero;	
	CGSize cropScaleAmount =
      CGSizeMake(croppingAspectRatio.width / textureAspectRatio.width,
         croppingAspectRatio.height / textureAspectRatio.height);
	CGFloat maxScale = fmax(cropScaleAmount.width, cropScaleAmount.height);
	CGSize scaledTextureSize =
      CGSizeMake(textureAspectRatio.width * maxScale,
         textureAspectRatio.height * maxScale);
	
	if ( cropScaleAmount.height > cropScaleAmount.width )
   {
		normalizedSamplingRect.size.width =
         croppingAspectRatio.width / scaledTextureSize.width;
		normalizedSamplingRect.size.height = 1.0;
	}
	else
   {
		normalizedSamplingRect.size.height =
         croppingAspectRatio.height / scaledTextureSize.height;
		normalizedSamplingRect.size.width = 1.0;
	}
   
	// Center crop
	normalizedSamplingRect.origin.x =
      (1.0 - normalizedSamplingRect.size.width)/2.0;
	normalizedSamplingRect.origin.y =
      (1.0 - normalizedSamplingRect.size.height)/2.0;
	
	return normalizedSamplingRect;
}


/////////////////////////////////////////////////////////////////
// 
- (void)renderWithSquareVertices:(const GLfloat*)squareVertices
   textureVertices:(const GLfloat*)textureVertices
{
    // Update attribute values.
	glVertexAttribPointer(GLKVertexAttribPosition, 
      2, 
      GL_FLOAT, 
      0, 
      0, 
      squareVertices);
	glEnableVertexAttribArray(GLKVertexAttribPosition);
	glVertexAttribPointer(GLKVertexAttribTexCoord0, 
      2, 
      GL_FLOAT, 
      0, 
      0, 
      textureVertices);
	glEnableVertexAttribArray(GLKVertexAttribTexCoord0);
    
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}


#pragma mark - GSVideoProcessorDelegate

/////////////////////////////////////////////////////////////////
// 
- (void)pixelBufferReadyForDisplay:(CVPixelBufferRef)pixelBuffer
{    
   NSParameterAssert(pixelBuffer);
   NSAssert(nil != videoTextureCache_, @"nil texture cache");
   	
   // Create a CVOpenGLESTexture from the CVImageBuffer
	size_t frameWidth = CVPixelBufferGetWidth(pixelBuffer);
	size_t frameHeight = CVPixelBufferGetHeight(pixelBuffer);
   CVOpenGLESTextureRef texture = NULL;
   CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault,
      videoTextureCache_,
      pixelBuffer,
      NULL,
      GL_TEXTURE_2D,
      GL_RGBA,
      frameWidth,
      frameHeight,
      GL_BGRA,
      GL_UNSIGNED_BYTE,
      0,
      &texture);
    
    
    if (!texture || err)
    {
        NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage (error: %d)",
           err);
        return;
    }

    static const GLfloat squareVertices[] =
    {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };

	// The texture vertices are set up such that we flip the texture vertically.
	// This is so that our top left origin buffers match OpenGL's bottom left texture coordinate system.
	CGRect textureSamplingRect =
      [self textureSamplingRectForCroppingTextureWithAspectRatio:
         CGSizeMake(frameWidth, frameHeight)
      toAspectRatio:self.view.bounds.size];
      
	GLfloat textureVertices[] =
   {
		CGRectGetMinX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
		CGRectGetMaxX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
		CGRectGetMinX(textureSamplingRect), CGRectGetMinY(textureSamplingRect),
		CGRectGetMaxX(textureSamplingRect), CGRectGetMinY(textureSamplingRect),
	};
   
	glBindTexture(
      CVOpenGLESTextureGetTarget(texture),
      CVOpenGLESTextureGetName(texture));
    
   // Set texture parameters
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);   
    	
   // Draw the texture on the screen with OpenGL ES 2
   glDisable(GL_BLEND);
   [self.greenScreenEffect prepareToDraw];
   [self renderWithSquareVertices:squareVertices
       textureVertices:textureVertices];

   glBindTexture(CVOpenGLESTextureGetTarget(texture), 0);

   // Flush the CVOpenGLESTexture cache and release the texture
   CVOpenGLESTextureCacheFlush(videoTextureCache_, 0);
   CFRelease(texture);
    
   // Draw the texture on the screen with OpenGL ES 2
   glEnable(GL_BLEND);
   glBlendFunc(GL_ONE_MINUS_DST_ALPHA, GL_DST_ALPHA);
   [self.baseEffect prepareToDraw];
   [self renderWithSquareVertices:squareVertices
      textureVertices:textureVertices];
   glFlush();
   
   // Present
   GLKView *glkView = (GLKView *)self.view;
   [glkView.context presentRenderbuffer:GL_RENDERBUFFER];
}


#pragma mark - update video statistics

/////////////////////////////////////////////////////////////////
// 
- (void)updateLabels
{
   NSString *frameRateString =
      [NSString stringWithFormat:@"%.2f FPS ",
         [self.videoProcessor videoFrameRate]];
   self.frameRateLabel.text = frameRateString;
   [self.frameRateLabel setBackgroundColor:
      [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.25]];
   
   NSString *dimensionsString =
      [NSString stringWithFormat:@"%d x %d ",
         [self.videoProcessor videoDimensions].width,
         [self.videoProcessor videoDimensions].height];
   self.dimensionsLabel.text = dimensionsString;
   [self.dimensionsLabel setBackgroundColor:
      [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.25]];
   
   CMVideoCodecType type = [self.videoProcessor videoType];
   type = OSSwapHostToBigInt32( type );
   NSString *typeString = [NSString stringWithFormat:@"%.4s ",
      (char*)&type];
   self.typeLabel.text = typeString;
   [self.typeLabel setBackgroundColor:
      [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.25]];
}


/////////////////////////////////////////////////////////////////
// 
- (UILabel *)labelWithText:(NSString *)text yPosition:(CGFloat)yPosition
{
	CGFloat labelWidth = 200.0;
	CGFloat labelHeight = 40.0;
	CGFloat xPosition = self.view.bounds.size.width - labelWidth - 10;
	CGRect labelFrame =
      CGRectMake(xPosition, yPosition, labelWidth, labelHeight);
	UILabel *label = [[UILabel alloc] initWithFrame:labelFrame];
	[label setFont:[UIFont systemFontOfSize:36]];
	[label setLineBreakMode:NSLineBreakByTruncatingMiddle];
	[label setTextAlignment:NSTextAlignmentRight];
	[label setTextColor:[UIColor whiteColor]];
	[label setBackgroundColor:
      [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.25]];
	[[label layer] setCornerRadius: 4];
	[label setText:text];
	
	return label;
}



@end
