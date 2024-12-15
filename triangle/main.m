#import <AppKit/AppKit.h>
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>


// Display settings
static const NSInteger kPreferredFPS = 60;
static const MTLClearColor kClearColor = {0.0, 0.0, 0.0, 1.0};
static const NSRect kInitialWindowFrame = {100, 100, 800, 600};

// Camera settings
static const float kInitialCameraDistance = 10.0;
static const float kMinCameraDistance = 5.0;
static const float kMaxCameraDistance = 20.0;
static const float kInitialCameraRotationX = 0.0;
static const float kInitialCameraRotationY = M_PI_4;
static const vector_float3 kInitialCameraTarget = {0, 0, 0};
static const vector_float3 kInitialLightPosition = {5.0, 10.0, 5.0};

// Camera control settings
static const float kCameraRotationSpeed = 0.01;
static const float kCameraZoomSpeed = 0.1;
static const float kCameraPanSpeed = 0.01;
static const float kMinCameraRotationY = 0.01;
static const float kMaxCameraRotationY = M_PI_2 * 0.99;

// Rendering settings
static const float kDonutRotationSpeed = 0.01;
static const float kAmbientIntensity = 0.2;
static const float kSpecularPower = 32.0;

// Torus geometry
static const int kTorusMajorSegments = 32;
static const int kTorusMinorSegments = 32;
static const float kTorusMajorRadius = 1.5;
static const float kTorusMinorRadius = 0.5;
static const float kTorusScale = 0.8;
static const float kTorusHeight = 2.0;  // Y translation
static const float kTorusDepth = -6.0;  // Z translation

// Plane geometry
static const float kPlaneSize = 20.0;


typedef struct {
    vector_float3 position;
    vector_float4 color;
    vector_float3 normal;
} Vertex;

typedef struct {
    matrix_float4x4 modelViewProjection;
    matrix_float4x4 modelView;
    vector_float3 lightPosition;
    vector_float3 cameraPosition;
    float ambientIntensity;
    float specularPower;
} Uniforms;

@class Renderer;

@interface CustomMTKView : MTKView
@property (weak) Renderer *renderer;
@end

@interface Renderer : NSObject <MTKViewDelegate>
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertices;
@property (nonatomic, strong) id<MTLBuffer> indices;
@property (nonatomic, strong) id<MTLBuffer> uniformBuffer;
@property (nonatomic, assign) NSInteger numVertices;
@property (nonatomic, assign) NSInteger numIndices;
@property (nonatomic, assign) float rotation;
@property (nonatomic, strong) id<MTLDepthStencilState> depthStencilState;
@property (nonatomic, weak) MTKView *view;

@property (nonatomic, strong) id<MTLRenderPipelineState> planePipelineState;
@property (nonatomic, strong) id<MTLDepthStencilState> planeDepthStencilState;
@property (nonatomic, strong) id<MTLBuffer> planeVertices;
@property (nonatomic, strong) id<MTLBuffer> planeIndices;
@property (nonatomic, assign) NSInteger numPlaneVertices;
@property (nonatomic, assign) NSInteger numPlaneIndices;
@property (nonatomic, assign) float cameraDistance;
@property (nonatomic, assign) float cameraRotationX;
@property (nonatomic, assign) float cameraRotationY;
@property (nonatomic, assign) vector_float3 cameraPosition;
@property (nonatomic, assign) vector_float3 lightPosition;

// Mouse event handling methods
- (void)mouseDown:(NSEvent *)event;
- (void)mouseDragged:(NSEvent *)event;
- (void)mouseUp:(NSEvent *)event;
- (void)scrollWheel:(NSEvent *)event;

// Matrix creation methods
- (matrix_float4x4)createViewMatrix;

@property (nonatomic, assign) vector_float3 cameraTarget;
@property (nonatomic, assign) BOOL isRightMouseDragging;
@end


@implementation CustomMTKView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    if (event.buttonNumber == 0) {  // Left click
        [self.renderer mouseDown:event];
    }
}

- (void)rightMouseDown:(NSEvent *)event {
    self.renderer.isRightMouseDragging = YES;
    [self.renderer mouseDown:event];
}

- (void)rightMouseDragged:(NSEvent *)event {
    if (self.renderer.isRightMouseDragging) {
        [self.renderer mouseDragged:event];
    }
}

- (void)rightMouseUp:(NSEvent *)event {
    self.renderer.isRightMouseDragging = NO;
    [self.renderer mouseUp:event];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.renderer.isRightMouseDragging) {  // Only handle left drag
        [self.renderer mouseDragged:event];
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (event.buttonNumber == 0) {  // Left click
        [self.renderer mouseUp:event];
    }
}

- (void)scrollWheel:(NSEvent *)event {
    [self.renderer scrollWheel:event];
}

@end



@interface Renderer () {
    BOOL _isDragging;
    NSPoint _lastMousePosition;
}
@end


@implementation Renderer

- (matrix_float4x4)createViewMatrix {
    vector_float3 up = (vector_float3){0, 1, 0};
    
    vector_float3 zAxis = simd_normalize(_cameraPosition - _cameraTarget);
    vector_float3 xAxis = simd_normalize(simd_cross(up, zAxis));
    vector_float3 yAxis = simd_cross(zAxis, xAxis);
    
    matrix_float4x4 viewMatrix = {
        .columns[0] = {xAxis.x, yAxis.x, zAxis.x, 0},
        .columns[1] = {xAxis.y, yAxis.y, zAxis.y, 0},
        .columns[2] = {xAxis.z, yAxis.z, zAxis.z, 0},
        .columns[3] = {-simd_dot(xAxis, _cameraPosition),
                      -simd_dot(yAxis, _cameraPosition),
                      -simd_dot(zAxis, _cameraPosition), 1}
    };
    
    return viewMatrix;
}

- (instancetype)initWithMetalKitView:(MTKView *)mtkView {
    self = [super init];
    if (self) {
        _device = mtkView.device;
        _view = mtkView;
        _rotation = 0.0;
        [self loadMetalWithView:mtkView];
        [self createTorus];
        [self createPlane];
        [self setupCamera];
    }
    return self;
}

- (void)loadMetalWithView:(MTKView *)mtkView {
    mtkView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    mtkView.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    
    MTLDepthStencilDescriptor *depthStencilDescriptor = [[MTLDepthStencilDescriptor alloc] init];
    depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    depthStencilDescriptor.depthWriteEnabled = YES;
    _depthStencilState = [self.device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
        
    id<MTLLibrary> defaultLibrary = [self.device newDefaultLibrary];
    id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
    id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];
    
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
    pipelineStateDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat;
    
    NSError *error;
    _pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if (!_pipelineState) {
        NSLog(@"Failed to create pipeline state: %@", error);
    }
    
    
    id<MTLFunction> planeVertexFunction = [defaultLibrary newFunctionWithName:@"planeVertexShader"];
    id<MTLFunction> planeFragmentFunction = [defaultLibrary newFunctionWithName:@"planeFragmentShader"];
    
    MTLRenderPipelineDescriptor *planePipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    planePipelineStateDescriptor.vertexFunction = planeVertexFunction;
    planePipelineStateDescriptor.fragmentFunction = planeFragmentFunction;
    planePipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
    planePipelineStateDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat;
    
    MTLDepthStencilDescriptor *planeDepthDescriptor = [[MTLDepthStencilDescriptor alloc] init];
    planeDepthDescriptor.depthCompareFunction = MTLCompareFunctionLessEqual;
    planeDepthDescriptor.depthWriteEnabled = NO;  // Disable depth write for plane
    _planeDepthStencilState = [self.device newDepthStencilStateWithDescriptor:planeDepthDescriptor];
    
    _planePipelineState = [self.device newRenderPipelineStateWithDescriptor:planePipelineStateDescriptor error:&error];
    if (!_planePipelineState) {
        NSLog(@"Failed to create plane pipeline state: %@", error);
    }
    
    _commandQueue = [self.device newCommandQueue];
    _uniformBuffer = [self.device newBufferWithLength:sizeof(Uniforms)
                                            options:MTLResourceStorageModeShared];
}


- (void)setupCamera {
    _cameraDistance = kInitialCameraDistance;
    _cameraRotationX = kInitialCameraRotationX;
    _cameraRotationY = kInitialCameraRotationY;
    _lightPosition = kInitialLightPosition;
    _cameraTarget = kInitialCameraTarget;
}

- (void)mouseDown:(NSEvent *)event {
    _isDragging = YES;
    NSPoint location = [self.view convertPoint:event.locationInWindow fromView:nil];
    _lastMousePosition = location;
}

- (void)mouseDragged:(NSEvent *)event {
    if (_isDragging) {
        NSPoint location = [self.view convertPoint:event.locationInWindow fromView:nil];
        float deltaX = location.x - _lastMousePosition.x;
        float deltaY = location.y - _lastMousePosition.y;
        
        if (_isRightMouseDragging) {
            vector_float3 right = simd_normalize(simd_cross((vector_float3){0, 1, 0},
                simd_normalize(_cameraPosition - _cameraTarget)));
            vector_float3 up = (vector_float3){0, 1, 0};
            
            _cameraTarget = _cameraTarget - right * deltaX * kCameraPanSpeed;
            _cameraTarget = _cameraTarget + up * deltaY * kCameraPanSpeed;
        } else {
            _cameraRotationX += deltaX * kCameraRotationSpeed;
            _cameraRotationY = MIN(kMaxCameraRotationY,
                                 MAX(kMinCameraRotationY,
                                     _cameraRotationY + deltaY * kCameraRotationSpeed));
        }
        
        _lastMousePosition = location;
        [self.view setNeedsDisplay:YES];
    }
}

- (void)mouseUp:(NSEvent *)event {
    _isDragging = NO;
}

- (void)scrollWheel:(NSEvent *)event {
    float zoomDelta = event.deltaY * kCameraZoomSpeed;
    _cameraDistance = MAX(kMinCameraDistance,
                         MIN(kMaxCameraDistance,
                             _cameraDistance - zoomDelta));
    [self.view setNeedsDisplay:YES];
}


- (void)createPlane {
    const float size = 20.0;
    Vertex planeVertices[] = {
        {{ -size, 0,  size}, {1, 1, 1, 1}, {0, 1, 0}},
        {{  size, 0,  size}, {1, 1, 1, 1}, {0, 1, 0}},
        {{  size, 0, -size}, {1, 1, 1, 1}, {0, 1, 0}},
        {{ -size, 0, -size}, {1, 1, 1, 1}, {0, 1, 0}},
    };
    
    uint16_t planeIndices[] = {
        0, 1, 2,
        0, 2, 3,
    };
    
    _numPlaneVertices = 4;
    _numPlaneIndices = 6;
    
    _planeVertices = [self.device newBufferWithBytes:planeVertices
                                            length:sizeof(planeVertices)
                                           options:MTLResourceStorageModeShared];
    
    _planeIndices = [self.device newBufferWithBytes:planeIndices
                                           length:sizeof(planeIndices)
                                          options:MTLResourceStorageModeShared];
}



- (void)handlePanGesture:(NSPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.view];
    _cameraRotationX += translation.x * 0.01;
    _cameraRotationY = MIN(M_PI_2 * 0.99, MAX(0.01, _cameraRotationY + translation.y * 0.01));
    [gesture setTranslation:CGPointZero inView:self.view];
}

- (void)handleMagnificationGesture:(NSMagnificationGestureRecognizer *)gesture {
    _cameraDistance = MAX(5.0, MIN(20.0, _cameraDistance * (1.0 - gesture.magnification)));
    gesture.magnification = 0;
}

- (void)createTorus {
    _numVertices = (kTorusMajorSegments + 1) * (kTorusMinorSegments + 1);
    _numIndices = kTorusMajorSegments * kTorusMinorSegments * 6;
    
    Vertex *vertices = (Vertex*)malloc(sizeof(Vertex) * _numVertices);
    uint16_t *indices = (uint16_t*)malloc(sizeof(uint16_t) * _numIndices);
    
    int vertexIndex = 0;
    for (int i = 0; i <= kTorusMajorSegments; i++) {
        float majorAngle = (float)i / kTorusMajorSegments * 2.0 * M_PI;
        for (int j = 0; j <= kTorusMinorSegments; j++) {
            float minorAngle = (float)j / kTorusMinorSegments * 2.0 * M_PI;
            
            float x = (kTorusMajorRadius + kTorusMinorRadius * cos(minorAngle)) * cos(majorAngle);
            float y = (kTorusMajorRadius + kTorusMinorRadius * cos(minorAngle)) * sin(majorAngle);
            float z = kTorusMinorRadius * sin(minorAngle);
            
            // Calculate normal
            float nx = cos(minorAngle) * cos(majorAngle);
            float ny = cos(minorAngle) * sin(majorAngle);
            float nz = sin(minorAngle);
            
            vertices[vertexIndex].position = (vector_float3){x, y, z};
            vertices[vertexIndex].color = (vector_float4){
                0.5 + 0.5 * cos(majorAngle),
                0.5 + 0.5 * sin(minorAngle),
                0.5 + 0.5 * cos(minorAngle + majorAngle),
                1.0
            };
            vertices[vertexIndex].normal = (vector_float3){nx, ny, nz};
            vertexIndex++;
        }
    }
    
    int index = 0;
    for (int i = 0; i < kTorusMajorSegments; i++) {
        for (int j = 0; j < kTorusMinorSegments; j++) {
            int current = i * (kTorusMinorSegments + 1) + j;
            int next = current + (kTorusMinorSegments + 1);
            
            indices[index++] = current;
            indices[index++] = next;
            indices[index++] = current + 1;
            
            indices[index++] = current + 1;
            indices[index++] = next;
            indices[index++] = next + 1;
        }
    }
    
    _vertices = [self.device newBufferWithBytes:vertices
                                       length:sizeof(Vertex) * _numVertices
                                      options:MTLResourceStorageModeShared];
    
    _indices = [self.device newBufferWithBytes:indices
                                      length:sizeof(uint16_t) * _numIndices
                                     options:MTLResourceStorageModeShared];
    
    free(vertices);
    free(indices);
}

- (matrix_float4x4)createProjectionMatrix {
    const float aspect = self.view.drawableSize.width / self.view.drawableSize.height;
    const float fov = 65.0f * (M_PI / 180.0f);
    const float near = 0.1f;
    const float far = 100.0f;
    
    float y = 1.0f / tanf(fov * 0.5f);
    float x = y / aspect;
    float z = (far + near) / (near - far);
    float w = (2.0f * far * near) / (near - far);
    
    matrix_float4x4 matrix = {
        .columns[0] = { x,  0,  0,  0 },
        .columns[1] = { 0,  y,  0,  0 },
        .columns[2] = { 0,  0,  z, -1 },
        .columns[3] = { 0,  0,  w,  0 }
    };
    
    return matrix;
}

- (matrix_float4x4)createModelMatrix {
    float scale = 0.8;
    matrix_float4x4 scaleMatrix = {
        .columns[0] = { scale,     0,     0, 0 },
        .columns[1] = {     0, scale,     0, 0 },
        .columns[2] = {     0,     0, scale, 0 },
        .columns[3] = {     0,     0,     0, 1 }
    };
    
    matrix_float4x4 rotationMatrix = {
        .columns[0] = { cos(_rotation),  0, sin(_rotation), 0 },
        .columns[1] = {              0,  1,             0, 0 },
        .columns[2] = {-sin(_rotation),  0, cos(_rotation), 0 },
        .columns[3] = {              0,  0,             0, 1 }
    };
    
    matrix_float4x4 translationMatrix = {
        .columns[0] = { 1, 0, 0, 0 },
        .columns[1] = { 0, 1, 0, 0 },
        .columns[2] = { 0, 0, 1, 0 },
        .columns[3] = { 0, 2, -6, 1 }
    };
    
    return matrix_multiply(translationMatrix, matrix_multiply(rotationMatrix, scaleMatrix));
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
}

- (void)drawInMTKView:(MTKView *)view {
    _rotation += kDonutRotationSpeed;
    
    float x = _cameraTarget.x + _cameraDistance * sin(_cameraRotationY) * cos(_cameraRotationX);
    float y = _cameraTarget.y + _cameraDistance * cos(_cameraRotationY);
    float z = _cameraTarget.z + _cameraDistance * sin(_cameraRotationY) * sin(_cameraRotationX);
    _cameraPosition = (vector_float3){x, y, z};
    
    matrix_float4x4 viewMatrix = [self createViewMatrix];
    matrix_float4x4 projectionMatrix = [self createProjectionMatrix];
    
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    
    if (renderPassDescriptor != nil) {
        renderPassDescriptor.depthAttachment.clearDepth = 1.0;
        renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
        renderPassDescriptor.depthAttachment.storeAction = MTLStoreActionStore;
        
        id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        
        // Draw torus first
        [renderEncoder setDepthStencilState:self.depthStencilState];
        
        matrix_float4x4 torusModelMatrix = [self createModelMatrix];
        matrix_float4x4 torusModelView = matrix_multiply(viewMatrix, torusModelMatrix);
        matrix_float4x4 torusMVP = matrix_multiply(projectionMatrix, torusModelView);
        
        Uniforms torusUniforms;
        torusUniforms.modelViewProjection = torusMVP;
        torusUniforms.modelView = torusModelView;
        torusUniforms.lightPosition = _lightPosition;
        torusUniforms.cameraPosition = _cameraPosition;
        torusUniforms.ambientIntensity = kAmbientIntensity;
        torusUniforms.specularPower = kSpecularPower;
        
        [renderEncoder setRenderPipelineState:self.pipelineState];
        [renderEncoder setVertexBuffer:self.vertices offset:0 atIndex:0];
        [renderEncoder setVertexBytes:&torusUniforms length:sizeof(Uniforms) atIndex:1];
        [renderEncoder setFragmentBytes:&torusUniforms length:sizeof(Uniforms) atIndex:1];
        [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                indexCount:_numIndices
                                 indexType:MTLIndexTypeUInt16
                               indexBuffer:self.indices
                         indexBufferOffset:0];
        
        // Draw plane second with different depth state
        [renderEncoder setDepthStencilState:self.planeDepthStencilState];
        
        matrix_float4x4 planeModelMatrix = matrix_identity_float4x4;
        matrix_float4x4 planeModelView = matrix_multiply(viewMatrix, planeModelMatrix);
        matrix_float4x4 planeMVP = matrix_multiply(projectionMatrix, planeModelView);
        
        Uniforms planeUniforms;
        planeUniforms.modelViewProjection = planeMVP;
        planeUniforms.modelView = planeModelView;
        planeUniforms.lightPosition = _lightPosition;
        planeUniforms.cameraPosition = _cameraPosition;
        planeUniforms.ambientIntensity = 0.2;
        planeUniforms.specularPower = 32.0;
        
        [renderEncoder setRenderPipelineState:self.planePipelineState];
        [renderEncoder setVertexBuffer:self.planeVertices offset:0 atIndex:0];
        [renderEncoder setVertexBytes:&planeUniforms length:sizeof(Uniforms) atIndex:1];
        [renderEncoder setFragmentBytes:&planeUniforms length:sizeof(Uniforms) atIndex:1];
        [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                indexCount:_numPlaneIndices
                                 indexType:MTLIndexTypeUInt16
                               indexBuffer:self.planeIndices
                         indexBufferOffset:0];
        
        [renderEncoder endEncoding];
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    
    [commandBuffer commit];
}
@end


@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) MTKView *mtkView;
@property (strong) Renderer *renderer;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
    
    self.window = [[NSWindow alloc] initWithContentRect:kInitialWindowFrame
                                            styleMask:style
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    
    self.mtkView = [[CustomMTKView alloc] initWithFrame:kInitialWindowFrame
                                               device:MTLCreateSystemDefaultDevice()];
    if (!self.mtkView.device) {
        NSLog(@"Metal is not supported on this device");
        return;
    }
    
    [self.mtkView setWantsLayer:YES];
    self.mtkView.preferredFramesPerSecond = kPreferredFPS;
    self.mtkView.clearColor = kClearColor;
    self.mtkView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    
    self.renderer = [[Renderer alloc] initWithMetalKitView:self.mtkView];
    self.mtkView.delegate = self.renderer;
    
    ((CustomMTKView *)self.mtkView).renderer = self.renderer;
    
    [self.window setContentView:self.mtkView];
    [self.window makeFirstResponder:self.mtkView];
    [self.window setTitle:@"Metal Donut"];
    [self.window makeKeyAndOrderFront:nil];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
