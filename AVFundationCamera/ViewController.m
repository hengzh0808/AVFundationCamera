#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>

#define kMainScreenWidth [UIScreen mainScreen].bounds.size.width
#define kMainScreenHeight  [UIScreen mainScreen].bounds.size.height

typedef NS_ENUM(NSInteger, CaptureState) {
    CaptureStateIdle,
    CaptureStateStart,
    CaptureStateCapturing,
    CaptureStateEnd
};

@interface ViewController ()<UIGestureRecognizerDelegate, AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate, AVCapturePhotoCaptureDelegate>

@property (weak, nonatomic) IBOutlet UIView *preivewView;

@property (weak, nonatomic) IBOutlet UIImageView *renderView;

@property (weak, nonatomic) IBOutlet UIView *focusView;

@property (weak, nonatomic) IBOutlet UIView *focusCircleView;

@property (weak, nonatomic) IBOutlet UILabel *logicFactorLab;

@property (weak, nonatomic) IBOutlet UILabel *physicsFactorLab;

@property (weak, nonatomic) IBOutlet UIButton *recordBtn;

@property (weak, nonatomic) IBOutlet UIButton *captureBtn;

@property (weak, nonatomic) IBOutlet UISegmentedControl *cameraTypeSegment;

@property (weak, nonatomic) IBOutlet UISegmentedControl *presetTypeSegment;

@property (weak, nonatomic) IBOutlet UISegmentedControl *previewTypeSegment;

@property (weak, nonatomic) IBOutlet UISegmentedControl *stabilizationSegment;

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *circleViewConstaintX;

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *circleViewConstaintY;

@property (weak, nonatomic) IBOutlet UISlider *zoomSlider;

@property (nonatomic) dispatch_queue_t sessionQueue;
/// AVCaptureSession对象来执行输入设备和输出设备之间的数据传递
@property (nonatomic, strong) AVCaptureSession* session;
/// 输入设备
@property (nonatomic, strong) AVCaptureDeviceInput* deviceInput;
/// 检测输出流
@property (nonatomic, strong) AVCaptureMetadataOutput *metadataOutput;
/// 视频原始数据
@property (nonatomic, strong) AVCaptureVideoDataOutput *videodataOutput;
/// 视频原始数据
@property (nonatomic, strong) AVCaptureMovieFileOutput *movefileOutput;
/// 照片
@property (nonatomic, strong) AVCapturePhotoOutput* photoOutput;

@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preivewLayer;

@property (atomic, assign) AVCaptureDeviceType deviceType;

@property (atomic, assign) AVCaptureSessionPreset sessionPreset;

@property (atomic, assign) AVCaptureDevicePosition devicePosition;

@property (nonatomic, assign) CGFloat logicZoomFactor;

@property (nonatomic, assign) CGFloat minLogicZoomFactor;

@property (nonatomic, assign) CGFloat maxLogicZoomFactor;

@property (nonatomic, assign) CGFloat physicsZoomFactor;

@property (atomic, strong) NSData *photoData;
@property (atomic) dispatch_group_t livePhotoGroup;
@property (atomic, strong) AVAssetWriter *assetWriter;
@property (atomic, strong) AVAssetWriterInput *videoInput;
@property (atomic, assign) BOOL isRecording;
@property (atomic, assign) BOOL isWriting;;
@property (atomic, assign) CaptureState captureState;
@property (atomic, copy) NSString *filename;
@property (nonatomic, assign) double startTime;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *adapter;
@property (nonatomic, strong) NSArray<AVMetadataObject *> *detectFaceObjs;

@end

@implementation ViewController


#pragma mark life circle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.focusCircleView.layer.cornerRadius = 25;
    self.focusCircleView.layer.masksToBounds = true;
    self.focusCircleView.hidden = YES;
    
    self.sessionQueue = dispatch_queue_create("com.example.serialQueue", DISPATCH_QUEUE_SERIAL);
            
    self.presetTypeSegment.selectedSegmentIndex = 1;
    self.stabilizationSegment.selectedSegmentIndex = 1;
    self.previewTypeSegment.selectedSegmentIndex = 1;
    self.cameraTypeSegment.selectedSegmentIndex = 0;
    self.previewTypeSegment.selectedSegmentIndex = 1;
    
    
    self.deviceType = [self selectDeviceType];
    self.devicePosition = AVCaptureDevicePositionBack;
    self.sessionPreset = AVCaptureSessionPreset1920x1080;
//    self.sessionPreset = AVCaptureSessionPresetPhoto
    
    self.preivewView.hidden = self.previewTypeSegment.selectedSegmentIndex != 0;
    self.renderView.hidden = self.previewTypeSegment.selectedSegmentIndex == 0;
    [self refreshZoomSlider];
    
    [self initAVCaptureSession];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                           selector:@selector(captureDeviceSubjectAreaDidChange:)
                               name:AVCaptureDeviceSubjectAreaDidChangeNotification
                             object:nil];
}

- (void)viewWillAppear:(BOOL)animated{
    
    [super viewWillAppear:YES];
    
    
    
    dispatch_async(self.sessionQueue, ^{
        if (self.session) {
            NSLog(@"%s", __func__);
            [self.session startRunning];
        }
    });
}

- (void)viewDidDisappear:(BOOL)animated{
    
    [super viewDidDisappear:YES];
    
    dispatch_sync(self.sessionQueue, ^{
        if (self.session) {
            [self.session stopRunning];
        }
    });
}

- (void)initAVCaptureSession {
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = self.sessionPreset;
    
    [self configDeviceWihtType:self.deviceType];
    
    self.metadataOutput = [self buildMetadataOutput];
    if ([self.session canAddOutput:self.metadataOutput]) {
        [self.session addOutput:self.metadataOutput];
    }
    
    self.videodataOutput = [self buildVideodataOutput];
    if ([self.session canAddOutput:self.videodataOutput]) {
        [self.session addOutput:self.videodataOutput];
    }
    
    self.movefileOutput = [self buildMovefileOutput];
    if ([self.session canAddOutput:self.movefileOutput]) {
        [self.session addOutput:self.movefileOutput];
    }
    
//    self.photoOutput = [self buildPhotoOutput];
//    if ([self.session canAddOutput:self.photoOutput]) {
//        [self.session addOutput:self.photoOutput];
//    }
//    self.photoOutput.depthDataDeliveryEnabled = YES;
    
    // 预览
    self.preivewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    self.preivewLayer.frame = self.preivewView.bounds;
    self.preivewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.preivewView.layer addSublayer:self.preivewLayer];
    
    [self configDefaultDevice:self.deviceInput.device];
    [self configDefaultMetaDetect];
}

#pragma mark - private
- (void)refreshZoomSlider {
    if (self.deviceType == AVCaptureDeviceTypeBuiltInDualCamera) {
        // 双摄像头单独判断
        if ([self buildDevice:self.devicePosition type:AVCaptureDeviceTypeBuiltInTelephotoCamera] != nil) {
            // 内置为长焦
            self.minLogicZoomFactor = 1.0;
        } else if ([self buildDevice:self.devicePosition type:AVCaptureDeviceTypeBuiltInUltraWideCamera] != nil) {
            // 内置为超广角
            self.minLogicZoomFactor = 0.5;
        } else {
            self.minLogicZoomFactor = 1.0;
        }
    } else if (self.deviceType == AVCaptureDeviceTypeBuiltInDualWideCamera) {
        // 双广角
        self.minLogicZoomFactor = 0.5;
    } else if (self.deviceType == AVCaptureDeviceTypeBuiltInTripleCamera) {
        // 三摄
        self.minLogicZoomFactor = 0.5;
    } else {
        self.minLogicZoomFactor = 1;
    }
    self.maxLogicZoomFactor = [self maxLogicZoomFactorWithDeviceType:self.deviceType];
    self.logicZoomFactor = 1;
    self.physicsZoomFactor = [self caculatePhysicsZoomFactorFromLogicZoomFactor:self.logicZoomFactor];
    
    self.zoomSlider.value = self.logicZoomFactor;
    self.zoomSlider.minimumValue = self.minLogicZoomFactor;
    self.zoomSlider.maximumValue = self.maxLogicZoomFactor;
}

- (void)configDeviceWihtType:(AVCaptureDeviceType)type {
    AVCaptureDevice *device = [self buildDevice:self.devicePosition type:type];
    NSLog(@"virtualDeviceSwitchOverVideoZoomFactors %@", [device virtualDeviceSwitchOverVideoZoomFactors]);
    [device addObserver:self forKeyPath:@"focusPointOfInterest" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:nil];
    [device addObserver:self forKeyPath:@"lensPosition" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:nil];
    
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];
    
    assert(device != nil && deviceInput != nil);
    
    [self.session beginConfiguration];
    [self.session removeInput:self.deviceInput];
    [self.session addInput:deviceInput];
    [self configDefaultDevice:deviceInput.device];
    [self.session commitConfiguration];
    
    self.deviceInput = deviceInput;
}

- (void)configDefaultDevice:(AVCaptureDevice *)device {
    [device lockForConfiguration:nil];
    device.smoothAutoFocusEnabled = YES;
    device.videoZoomFactor = self.physicsZoomFactor;
    device.autoFocusRangeRestriction = AVCaptureAutoFocusRangeRestrictionNear;
    device.subjectAreaChangeMonitoringEnabled = true;
    device.activeVideoMinFrameDuration = CMTimeMake(1, 30);
    device.activeVideoMaxFrameDuration = CMTimeMake(1, 30);
    [device unlockForConfiguration];
}

- (void)configDefaultMetaDetect {
    if ([self.metadataOutput.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeFace]) {
        self.metadataOutput.metadataObjectTypes = @[AVMetadataObjectTypeFace];
    }
    [self.metadataOutput setMetadataObjectsDelegate:self queue:self.sessionQueue];
}

- (void)tryToResetAutoFocus {
    if (CGPointEqualToPoint(self.deviceInput.device.focusPointOfInterest, CGPointMake(0.5, 0.5)) && self.deviceInput.device.focusMode == AVCaptureFocusModeContinuousAutoFocus) {
        NSLog(@"无需再次对焦 %s", __func__);
    } else {
        NSLog(@"%s", __func__);
        NSError *error;
        [self.deviceInput.device lockForConfiguration:&error];
        self.deviceInput.device.focusPointOfInterest = CGPointMake(0.5, 0.5);
        self.deviceInput.device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        [self.deviceInput.device unlockForConfiguration];
        if (error) {
            NSLog(@"error: %@", error);
        }
    }
}

- (void)focusToPoint:(CGPoint)point {
    NSError *error;
    [self.deviceInput.device lockForConfiguration:&error];
    self.deviceInput.device.focusPointOfInterest = point;
    self.deviceInput.device.focusMode = AVCaptureFocusModeAutoFocus;
    [self.deviceInput.device unlockForConfiguration];
        
    if (error) {
        NSLog(@"error: %@", error);
    }
}

- (void)configStabilizationModeWithOutput:(AVCaptureOutput *)output device:(AVCaptureDevice *)device {
    AVCaptureVideoStabilizationMode mode = AVCaptureVideoStabilizationModeOff;
    if (self.stabilizationSegment.selectedSegmentIndex == 1) {
        mode = AVCaptureVideoStabilizationModeStandard;
    } else if (self.stabilizationSegment.selectedSegmentIndex == 2) {
        mode = AVCaptureVideoStabilizationModeAuto;
    }
    [device lockForConfiguration:nil];
    AVCaptureConnection *connection = [output connectionWithMediaType:AVMediaTypeVideo];
    if (mode != AVCaptureVideoStabilizationModeOff) {
        NSLog(@"activeFormat: %@, formats: %@", device.activeFormat, device.formats);
        if ([device.activeFormat isVideoStabilizationModeSupported:mode]) {
            NSLog(@"支持防抖");
            [connection setPreferredVideoStabilizationMode:mode];
        } else {
            NSLog(@"不支持防抖");
        }
    } else {
        NSLog(@"关闭防抖");
    }
    [device unlockForConfiguration];
    
    [connection addObserver:self forKeyPath:@"activeVideoStabilizationMode" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:nil];
}

- (void)setLogicZoomFactor:(CGFloat)logicZoomFactor {
    _logicZoomFactor = logicZoomFactor;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logicFactorLab.text = [NSString stringWithFormat:@"逻辑焦距\n%.1f", logicZoomFactor];
    });
}

- (void)setPhysicsZoomFactor:(CGFloat)physicsZoomFactor {
    _physicsZoomFactor = physicsZoomFactor;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.physicsFactorLab.text = [NSString stringWithFormat:@"物理焦距\n%.1f", physicsZoomFactor];
    });
}

- (CGFloat)caculatePhysicsZoomFactorFromLogicZoomFactor:(CGFloat)logicZoomFactor {
    if (self.minLogicZoomFactor < 1.0) {
        return logicZoomFactor * 2;
    }
    return logicZoomFactor;
}

- (CGFloat)maxLogicZoomFactorWithDeviceType:(AVCaptureDeviceType)type {
    CGFloat factor = 10;
    if (type == AVCaptureDeviceTypeBuiltInTripleCamera) {
        AVCaptureDevice *device = [self buildDevice:self.devicePosition type:type];
        factor = (device.virtualDeviceSwitchOverVideoZoomFactors.lastObject.floatValue / 2) * 5;
    } else if (type == AVCaptureDeviceTypeBuiltInDualCamera) {
        if ([self buildDevice:self.devicePosition type:AVCaptureDeviceTypeBuiltInTelephotoCamera]) {
            AVCaptureDevice *device = [self buildDevice:self.devicePosition type:type];
            NSArray<NSNumber *> *factors = device.virtualDeviceSwitchOverVideoZoomFactors;
            factor = ceil(factors.lastObject.floatValue) * 5;
        }
    }
    return factor;
}

- (AVCaptureDeviceType)selectDeviceType {
    AVCaptureDeviceType deviceType;
    if (self.cameraTypeSegment.selectedSegmentIndex == 0) {
        // 内置广角摄像头
        deviceType = AVCaptureDeviceTypeBuiltInWideAngleCamera;
    } else if (self.cameraTypeSegment.selectedSegmentIndex == 1) {
        // 内置长焦摄像头
        deviceType = AVCaptureDeviceTypeBuiltInTelephotoCamera;
        self.logicZoomFactor = 1.0;
        self.minLogicZoomFactor = 1.0;
    } else if (self.cameraTypeSegment.selectedSegmentIndex == 2) {
        // 内置超广角
        deviceType = AVCaptureDeviceTypeBuiltInUltraWideCamera;
    } else if (self.cameraTypeSegment.selectedSegmentIndex == 3) {
        // 内置双摄摄像头
        deviceType = AVCaptureDeviceTypeBuiltInDualCamera;
    } else if (self.cameraTypeSegment.selectedSegmentIndex == 4) {
        // 内置双广角
        deviceType = AVCaptureDeviceTypeBuiltInDualWideCamera;
    } else if (self.cameraTypeSegment.selectedSegmentIndex == 5) {
        // 内置三摄
        deviceType = AVCaptureDeviceTypeBuiltInTripleCamera;
    } else {
        assert(false);
    }
    return deviceType;
}

- (void)captureDeviceSubjectAreaDidChange:(NSNotification *)notif {
    [self tryToResetAutoFocus];
}

- (AVCaptureDevice *)buildDevice:(AVCaptureDevicePosition )position type:(AVCaptureDeviceType)type {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:type mediaType:AVMediaTypeVideo position:position];
    return device;
}

- (AVCaptureMetadataOutput *)buildMetadataOutput {
    AVCaptureMetadataOutput *metadataOutput = [[AVCaptureMetadataOutput alloc] init];
    return metadataOutput;
}

- (AVCaptureVideoDataOutput*)buildVideodataOutput {
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    output.alwaysDiscardsLateVideoFrames = YES;
    id<AVCaptureVideoDataOutputSampleBufferDelegate> sampleDelegate = (id<AVCaptureVideoDataOutputSampleBufferDelegate>)self;
    [output setSampleBufferDelegate:sampleDelegate queue:self.sessionQueue];
    [output setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    return output;
}

- (AVCaptureMovieFileOutput *)buildMovefileOutput {
    AVCaptureMovieFileOutput *movefileOutput = [[AVCaptureMovieFileOutput alloc] init];
    return movefileOutput;
}

- (AVCapturePhotoOutput *)buildPhotoOutput {
    AVCapturePhotoOutput *photoOutPhoto = [[AVCapturePhotoOutput alloc] init];
    return photoOutPhoto;
}

- (void)startRecordingWithPath:(NSString *)outputPath {
    NSURL *outputURL = [NSURL fileURLWithPath:outputPath];
    
    NSError *error = nil;
    self.assetWriter = [AVAssetWriter assetWriterWithURL:outputURL fileType:AVFileTypeQuickTimeMovie error:&error];
    
    NSDictionary *videoSettings = @{
        AVVideoCodecKey : AVVideoCodecTypeH264,
        AVVideoWidthKey : @1920,
        AVVideoHeightKey : @1080
    };
    
    self.videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    self.videoInput.expectsMediaDataInRealTime = YES;
    
    if ([self.assetWriter canAddInput:self.videoInput]) {
        [self.assetWriter addInput:self.videoInput];
    }
    
    [self.assetWriter startWriting];
    [self.assetWriter startSessionAtSourceTime:kCMTimeZero];
}

- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!self.isRecording) {
        return;
    }
    
    if (!self.isWriting) {
        NSLog(@"startSessionAtSourceTime %s", __func__);
        self.isWriting = true;
        CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        [self.assetWriter startSessionAtSourceTime:timestamp];
    }
    
    if (self.videoInput.isReadyForMoreMediaData) {
        [self.videoInput appendSampleBuffer:sampleBuffer];
        NSLog(@"appendSampleBuffer %s", __func__);
    }
}

- (void)stopRecordingWithComplete:(void(^)(void))complete {
    self.isRecording = NO;
    [self.videoInput markAsFinished];
    
    [self.assetWriter finishWritingWithCompletionHandler:^{
        NSLog(@"Finished writing video");
        complete();
    }];
}

- (void)saveVideoToPhotoLibraryWithPath:(NSString *)path {
    NSURL *pathUrl = [NSURL fileURLWithPath:path];
    
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:pathUrl];
    } completionHandler:^(BOOL success, NSError *error) {
        if (success) {
            NSLog(@"Video saved to photo library");
        } else {
            NSLog(@"Error saving video to photo library: %@", error.localizedDescription);
        }
    }];
}

-(NSString *)documentsDirectory{
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return documentsDirectory;
}

#pragma mark - action
- (IBAction)zoomSliderAction:(id)sender {
    self.logicZoomFactor = self.zoomSlider.value;
    self.physicsZoomFactor = [self caculatePhysicsZoomFactorFromLogicZoomFactor:self.logicZoomFactor];
    dispatch_async(self.sessionQueue, ^{
        NSLog(@"logicZoomFactor: %.2f, physicsZoomFactor: %.2f", self.logicZoomFactor, self.physicsZoomFactor);
        
        [self.deviceInput.device lockForConfiguration:nil];
        [self.deviceInput.device setVideoZoomFactor:self.physicsZoomFactor];
        [self.deviceInput.device unlockForConfiguration];
    });
}

- (IBAction)chooseCameraType:(UISegmentedControl *)sender {
    self.deviceType = [self selectDeviceType];
    [self refreshZoomSlider];
    
    dispatch_async(self.sessionQueue, ^{
        [self configDeviceWihtType:self.deviceType];
        
        NSLog(@"minAvailableVideoZoomFactor = %.2f", self.deviceInput.device.minAvailableVideoZoomFactor);
        NSLog(@"maxAvailableVideoZoomFactor = %.2f", self.deviceInput.device.maxAvailableVideoZoomFactor);
    });
}

- (IBAction)previewAction:(UISegmentedControl *)sender {
    self.preivewView.hidden = self.previewTypeSegment.selectedSegmentIndex != 0;
    
    self.renderView.hidden = self.previewTypeSegment.selectedSegmentIndex == 0;
    self.renderView.contentMode = UIViewContentModeScaleAspectFill;
}

- (IBAction)presetAction:(UISegmentedControl *)sender {
    [self.session beginConfiguration];
    
    if (sender.selectedSegmentIndex == 0) {
        self.session.sessionPreset = AVCaptureSessionPresetPhoto;
    } else {
        self.session.sessionPreset = AVCaptureSessionPreset1920x1080;
    }
    
    [self.session commitConfiguration];
    [self configDefaultDevice:self.deviceInput.device];
    
    self.sessionPreset = self.session.sessionPreset;
}

- (IBAction)stabilizationAction:(UISegmentedControl *)sender {
    [self configStabilizationModeWithOutput:self.videodataOutput device:self.deviceInput.device];
}

- (IBAction)recordOut:(id)sender {
    NSString *path = [self.documentsDirectory stringByAppendingPathComponent:@"output.mov"];
    
    // 开始录制
    if (self.isRecording) {
        [self.recordBtn setTitle:@"录制" forState:UIControlStateNormal];
        [self.recordBtn setBackgroundColor:[UIColor redColor]];
        
        self.isRecording = false;
        self.isWriting = false;
        
        if (self.movefileOutput) {
            [self.movefileOutput stopRecording];
        } else {
            self.captureState = CaptureStateEnd;
        }
    } else {
        [self.recordBtn setTitle:@"停止" forState:UIControlStateNormal];
        [self.recordBtn setBackgroundColor:[UIColor yellowColor]];
           
        NSURL *outputURL = [NSURL fileURLWithPath:path];
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtURL:outputURL error:&error];
        if (error) {
            NSLog(@"error: %@", error);
        }
        
        if (self.movefileOutput) {
            [self.movefileOutput startRecordingToOutputFileURL:outputURL recordingDelegate:self];
        }
        
        self.captureState = CaptureStateStart;
        
        self.isRecording = true;
        self.isWriting = false;
    }
}

- (IBAction)livephotoAction:(id)sender {
    if (!self.photoOutput) {
        NSLog(@"photoOutput is nil");
        return;
    }
    
    // 创建并配置 AVCapturePhotoSettings 实例
    self.isRecording = YES;
    [self.captureBtn setBackgroundColor:[UIColor yellowColor]];
    NSDate *currentDate = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    // 设置日期格式（根据需要进行调整）
    [dateFormatter setDateFormat:@"yyyy-MM-dd_HH:mm:ss"];
    // 将 NSDate 转换为 NSString
    NSString *dateString = [dateFormatter stringFromDate:currentDate];
    
    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
    NSURL *fileUrl = [NSURL fileURLWithPath:[self.documentsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_livePhoto.MOV", dateString]]];;
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtURL:fileUrl error:&error];
    settings.livePhotoMovieFileURL = fileUrl;
    self.photoOutput.livePhotoCaptureEnabled = YES;
    [self.photoOutput capturePhotoWithSettings:settings delegate:self];
    
    NSString *outputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_output.MOV", dateString]];
    [self startRecordingWithPath:outputPath];

    self.livePhotoGroup = dispatch_group_create();
    dispatch_group_enter(self.livePhotoGroup);
    dispatch_group_enter(self.livePhotoGroup);
    dispatch_group_notify(self.livePhotoGroup, dispatch_get_main_queue(), ^{
        NSLog(@"%s", __func__);
        self.isRecording = false;
        [self.captureBtn setBackgroundColor:[UIColor redColor]];
        [self stopRecordingWithComplete:^{
            [self saveVideoToPhotoLibraryWithPath:outputPath];
        }];
        
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCreationRequest *creationRequest = [PHAssetCreationRequest creationRequestForAsset];
            [creationRequest addResourceWithType:PHAssetResourceTypePhoto data:self.photoData options:nil];
            [creationRequest addResourceWithType:PHAssetResourceTypePairedVideo fileURL:fileUrl options:nil];
        } completionHandler:^(BOOL success, NSError *error) {
            if (!success) {
                NSLog(@"Error saving 实况 to library: %@", error);
            } else {
                NSLog(@"success saving 实况 to library");
            }
        }];
        
        // 请求相册权限
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:fileUrl];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            if (success) {
                NSLog(@"视频已保存到相册");
            } else {
                NSLog(@"保存视频失败: %@", error.localizedDescription);
            }
        }];
    });
}

- (IBAction)focusAction:(UITapGestureRecognizer *)sender {
    CGPoint touchPoint = [sender locationInView:self.focusView];
    CGAffineTransform transform = CGAffineTransformMakeScale(1.0, 1.0);
    CGSize previewSize = CGSizeApplyAffineTransform(self.focusView.bounds.size, transform);
    CGPoint adjustedPoint = CGPointApplyAffineTransform(touchPoint, transform);
    adjustedPoint = CGPointMake(adjustedPoint.y / previewSize.height, 1.0 - adjustedPoint.x / previewSize.width);
    
    [self focusToPoint:adjustedPoint];
        
    self.circleViewConstaintX.constant = touchPoint.x;
    self.circleViewConstaintY.constant = touchPoint.y;
    self.focusCircleView.hidden = false;
    
    [UIView animateWithDuration:0.4 animations:^{
        self.focusCircleView.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.focusCircleView.alpha = 1.0;
        self.focusCircleView.hidden = true;
    }];
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate Methods
- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    NSMutableArray *detectFaceObjs = [NSMutableArray array];
    for (AVMetadataObject *obj in metadataObjects) {
        if ([obj.type isEqualToString:AVMetadataObjectTypeFace]) {
            [detectFaceObjs addObject:obj];
        }
        NSLog(@"AVCaptureMetadataOutput detect %@ %@", obj.type, NSStringFromCGRect(obj.bounds));
    }
    self.detectFaceObjs = detectFaceObjs;
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate Methods
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
//    [self appendSampleBuffer:sampleBuffer];
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
    
    // 使用 CIContext 渲染图像
    CIContext *context = [CIContext contextWithOptions:nil];
    CGRect frame = CGRectMake(0, 0,
                              CVPixelBufferGetWidth(imageBuffer),
                              CVPixelBufferGetHeight(imageBuffer));
    CGImageRef cgImage = [context createCGImage:ciImage fromRect:frame];
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    
    NSArray<AVMetadataObject *> *faces = [NSArray arrayWithArray:self.detectFaceObjs];
    // 更新 UI
    dispatch_async(dispatch_get_main_queue(), ^{
        self.renderView.image = [self rotateImageRight90:image faces:faces]; // 将 imageView 替换为你的 UIImageView 实例
    });
    
    CGImageRelease(cgImage);
    
    
    
    double timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
    
    switch (self.captureState) {
        case CaptureStateStart: {
            NSLog(@"CaptureStateStart %s", __func__);
            self.filename = [[NSUUID UUID] UUIDString];
            NSURL *videoPath = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mov", self.filename]]];
            
            NSError *error = nil;
            self.assetWriter = [[AVAssetWriter alloc] initWithURL:videoPath fileType:AVFileTypeQuickTimeMovie error:&error];
            NSDictionary *settings = [self.videodataOutput recommendedVideoSettingsForAssetWriterWithOutputFileType:AVFileTypeQuickTimeMovie];
            self.videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
            self.videoInput.expectsMediaDataInRealTime = YES;
            self.videoInput.transform = CGAffineTransformMakeRotation(M_PI_2);
            
            self.adapter = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.videoInput sourcePixelBufferAttributes:nil];
            
            if ([self.assetWriter canAddInput:self.videoInput]) {
                [self.assetWriter addInput:self.videoInput];
            }
            
            [self.assetWriter startWriting];
            [self.assetWriter startSessionAtSourceTime:kCMTimeZero];
            
            self.captureState = CaptureStateCapturing;
            self.startTime = timestamp;
            break;
        }
        case CaptureStateCapturing: {
            if (self.videoInput.isReadyForMoreMediaData) {
                CMTime time = CMTimeMakeWithSeconds(timestamp - self.startTime, 600);
                [self.adapter appendPixelBuffer:CMSampleBufferGetImageBuffer(sampleBuffer) withPresentationTime:time];
            }
            break;
        }
        case CaptureStateEnd: {
            NSLog(@"CaptureStateEnd %s", __func__);
            if (self.videoInput.isReadyForMoreMediaData && self.assetWriter.status != AVAssetWriterStatusFailed) {
                NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mov", self.filename]];
                [self.videoInput markAsFinished];
                [self.assetWriter finishWritingWithCompletionHandler:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.captureState = CaptureStateIdle;
                        self.assetWriter = nil;
                        self.videoInput = nil;
                        [self saveVideoToPhotoLibraryWithPath:path];
                    });
                }];
            }
            break;
        }
        default:
            break;
    }

}

- (UIImage *)rotateImageRight90:(UIImage *)image faces:(NSArray<AVMetadataObject *> *)detectFaceObjs {
    UIImage *faceImg = ^(UIImage *image){
        CGSize size = CGSizeMake(image.size.width, image.size.height);
        UIGraphicsBeginImageContext(size);
        CGContextRef context = UIGraphicsGetCurrentContext();
        [image drawAtPoint:CGPointZero];
        // 设置边框颜色（例如红色）
        CGContextSetStrokeColorWithColor(context, [UIColor redColor].CGColor);
        // 设置边框宽度
        CGContextSetLineWidth(context, 3.0);
        // 绘制正方形
        for (AVMetadataObject *faceObj in detectFaceObjs) {
            CGRect faceRect = CGRectMake(faceObj.bounds.origin.x * image.size.width,
                                         faceObj.bounds.origin.y * image.size.height,
                                         faceObj.bounds.size.width * image.size.width,
                                         faceObj.bounds.size.height * image.size.height);
            CGContextStrokeRect(context, faceRect);
        }
        UIImage *faceImg = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return faceImg;
    }(image);

    UIImage *rotatedImage = ^(UIImage *image){
        CGSize size = CGSizeMake(image.size.height, image.size.width);
        UIGraphicsBeginImageContext(size);
        CGContextRef context = UIGraphicsGetCurrentContext();
        // 平移和旋转
        CGContextTranslateCTM(context, size.width / 2, size.height / 2);
        CGContextRotateCTM(context, M_PI_2);
        // 绘制图像
        [image drawInRect:CGRectMake(-image.size.width / 2, -image.size.height / 2, image.size.width, image.size.height)];
        UIImage *rotatedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return rotatedImage;
    }(faceImg);
    
    return rotatedImage;
}

// MARK: - AVCaptureFileOutputRecordingDelegate Methods
- (void)captureOutput:(AVCaptureFileOutput *)output didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray<AVCaptureConnection *> *)connections error:(nullable NSError *)error {
    if (error) {
        NSLog(@"录制错误: %@", error.localizedDescription);
        return;
    }
    
    // 请求相册权限
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:outputFileURL];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            NSLog(@"视频已保存到相册");
        } else {
            NSLog(@"保存视频失败: %@", error.localizedDescription);
        }
    }];
}

// MARK: - AVCapturePhotoCaptureDelegate Methods

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    if (error) {
        NSLog(@"Error capturing photo: %@", error);
    }

    self.photoData = [photo fileDataRepresentation];
    dispatch_group_leave(self.livePhotoGroup);
    NSLog(@"%s", __func__);
//    if (!self.photoData) {
//        NSLog(@"Error processing photo data");
//        return;
//    }
//
//    // 保存到照片库
//    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
//        PHAssetCreationRequest *creationRequest = [PHAssetCreationRequest creationRequestForAsset];
//        [creationRequest addResourceWithType:PHAssetResourceTypePhoto data:self.photoData options:nil];
//        NSURL *outputFileURL = [NSURL fileURLWithPath:[self.documentsDirectory stringByAppendingPathComponent:@"livePhoto.MOV"]];;
//        [creationRequest addResourceWithType:PHAssetResourceTypePairedVideo fileURL:outputFileURL options:nil];
//    } completionHandler:^(BOOL success, NSError *error) {
//        if (!success) {
//            NSLog(@"Error saving photo to library: %@", error);
//        }
//    }];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishRecordingLivePhotoMovieForEventualFileAtURL:(NSURL *)outputFileURL resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings {
//    if ([[NSFileManager defaultManager] fileExistsAtPath:[outputFileURL path]]) {
//        
//    } else {
//        NSLog(@"%s outputFileURL is empty", __func__);
//    }
//    
//    dispatch_group_leave(self.livePhotoGroup);
//    NSLog(@"%s", __func__);
//    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
//        PHAssetCreationRequest *creationRequest = [PHAssetCreationRequest creationRequestForAsset];
//        [creationRequest addResourceWithType:PHAssetResourceTypePhoto data:self.photoData options:nil];
//        [creationRequest addResourceWithType:PHAssetResourceTypePairedVideo fileURL:outputFileURL options:nil];
//    } completionHandler:^(BOOL success, NSError *error) {
//        if (!success) {
//            NSLog(@"Error saving live photo movie to library: %@", error);
//        }
//    }];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingLivePhotoToMovieFileAtURL:(NSURL *)outputFileURL duration:(CMTime)duration photoDisplayTime:(CMTime)photoDisplayTime resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings error:(NSError *)error {
    if ([[NSFileManager defaultManager] fileExistsAtPath:[outputFileURL path]]) {
        
    } else {
        NSLog(@"%s outputFileURL is empty", __func__);
    }
    
    dispatch_group_leave(self.livePhotoGroup);
    NSLog(@"%s", __func__);
    
    if (error) {
        NSLog(@"didFinishProcessingLivePhotoToMovieFileAtURL error: %@", error);
    } else {
        NSLog(@"%s", __func__);
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
//    [device addObserver:self forKeyPath:@"focusPointOfInterest" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:nil];
//    [device addObserver:self forKeyPath:@"lensPosition" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:nil];
    NSLog(@"%@, change: %@", keyPath, change);
}

@end
