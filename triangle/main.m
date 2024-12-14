#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>

typedef struct {
    vector_float3 position;
    vector_float4 color;
} Vertex;

typedef struct {
    matrix_float4x4 modelViewProjection;
} Uniforms;

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
@end

@implementation Renderer

- (instancetype)initWithMetalKitView:(MTKView *)mtkView {
    self = [super init];
    if (self) {
        _device = mtkView.device;
        _view = mtkView;
        _rotation = 0.0;
        [self loadMetalWithView:mtkView];
        [self createTorus];
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
    
    _commandQueue = [self.device newCommandQueue];
    _uniformBuffer = [self.device newBufferWithLength:sizeof(Uniforms)
                                            options:MTLResourceStorageModeShared];
}

- (void)createTorus {
    const int majorSegments = 32;
    const int minorSegments = 32;
    const float majorRadius = 1.5;
    const float minorRadius = 0.5;
    
    _numVertices = (majorSegments + 1) * (minorSegments + 1);
    _numIndices = majorSegments * minorSegments * 6;
    
    Vertex *vertices = (Vertex*)malloc(sizeof(Vertex) * _numVertices);
    uint16_t *indices = (uint16_t*)malloc(sizeof(uint16_t) * _numIndices);
    
    int vertexIndex = 0;
    for (int i = 0; i <= majorSegments; i++) {
        float majorAngle = (float)i / majorSegments * 2.0 * M_PI;
        for (int j = 0; j <= minorSegments; j++) {
            float minorAngle = (float)j / minorSegments * 2.0 * M_PI;
            
            float x = (majorRadius + minorRadius * cos(minorAngle)) * cos(majorAngle);
            float y = (majorRadius + minorRadius * cos(minorAngle)) * sin(majorAngle);
            float z = minorRadius * sin(minorAngle);
            
            vertices[vertexIndex].position = (vector_float3){x, y, z};
            vertices[vertexIndex].color = (vector_float4){
                0.5 + 0.5 * cos(majorAngle),
                0.5 + 0.5 * sin(minorAngle),
                0.5 + 0.5 * cos(minorAngle + majorAngle),
                1.0
            };
            vertexIndex++;
        }
    }
    
    int index = 0;
    for (int i = 0; i < majorSegments; i++) {
        for (int j = 0; j < minorSegments; j++) {
            int current = i * (minorSegments + 1) + j;
            int next = current + (minorSegments + 1);
            
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
        .columns[3] = { 0, 0, -6, 1 }
    };
    
    return matrix_multiply(translationMatrix, matrix_multiply(rotationMatrix, scaleMatrix));
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
}

- (void)drawInMTKView:(MTKView *)view {
    _rotation += 0.02;
    
    Uniforms uniforms;
    uniforms.modelViewProjection = matrix_multiply([self createProjectionMatrix], [self createModelMatrix]);
    memcpy([_uniformBuffer contents], &uniforms, sizeof(uniforms));
    
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    
    if (renderPassDescriptor != nil) {
        renderPassDescriptor.depthAttachment.clearDepth = 1.0;
        renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
        renderPassDescriptor.depthAttachment.storeAction = MTLStoreActionStore;
        
        id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        
        [renderEncoder setRenderPipelineState:self.pipelineState];
        [renderEncoder setDepthStencilState:self.depthStencilState];
        [renderEncoder setVertexBuffer:self.vertices offset:0 atIndex:0];
        [renderEncoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:1];
        [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                indexCount:_numIndices
                                 indexType:MTLIndexTypeUInt16
                               indexBuffer:self.indices
                         indexBufferOffset:0];
        
        [renderEncoder endEncoding];
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    
    [commandBuffer commit];
    [view setNeedsDisplay:YES];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) MTKView *mtkView;
@property (strong) Renderer *renderer;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSRect frame = NSMakeRect(100, 100, 400, 400);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
    
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:style
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    
    self.mtkView = [[MTKView alloc] initWithFrame:frame device:MTLCreateSystemDefaultDevice()];
    if (!self.mtkView.device) {
        NSLog(@"Metal is not supported on this device");
        return;
    }
    
    self.mtkView.preferredFramesPerSecond = 60;
    self.mtkView.enableSetNeedsDisplay = YES;
    self.mtkView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    
    self.renderer = [[Renderer alloc] initWithMetalKitView:self.mtkView];
    self.mtkView.delegate = self.renderer;
    
    self.window.contentView = self.mtkView;
    [self.window setTitle:@"Metal Donut"];
    [self.window makeKeyAndOrderFront:nil];
    
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
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
