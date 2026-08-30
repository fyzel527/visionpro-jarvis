#include "SpatialRenderer.h"
#include "Mesh.h"
#include "ShaderTypes.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Spatial/Spatial.h>

#include <vector>
#include <atomic>

namespace {
std::atomic<int32_t> gGesture { 0 };
std::atomic<int32_t> gPinchValid { 0 };
std::atomic<float> gPinchX { 0.0f };
std::atomic<float> gPinchY { 0.0f };
std::atomic<float> gPinchZ { 0.0f };
std::atomic<float> gOpenness { 0.0f };
std::atomic<float> gExpansion { 0.0f };
}

extern "C" void SpatialRenderer_SetHandTrackingState(
    int32_t gesture,
    float pinchX,
    float pinchY,
    float pinchZ,
    int32_t pinchValid,
    float openness,
    float expansion
) {
    gGesture.store(gesture, std::memory_order_relaxed);
    gPinchX.store(pinchX, std::memory_order_relaxed);
    gPinchY.store(pinchY, std::memory_order_relaxed);
    gPinchZ.store(pinchZ, std::memory_order_relaxed);
    gPinchValid.store(pinchValid, std::memory_order_relaxed);
    gOpenness.store(openness, std::memory_order_relaxed);
    gExpansion.store(expansion, std::memory_order_relaxed);
}

static simd_float4x4 matrix_float4x4_from_double4x4(simd_double4x4 m) {
    return simd_matrix(simd_make_float4(m.columns[0][0], m.columns[0][1], m.columns[0][2], m.columns[0][3]),
                       simd_make_float4(m.columns[1][0], m.columns[1][1], m.columns[1][2], m.columns[1][3]),
                       simd_make_float4(m.columns[2][0], m.columns[2][1], m.columns[2][2], m.columns[2][3]),
                       simd_make_float4(m.columns[3][0], m.columns[3][1], m.columns[3][2], m.columns[3][3]));
}

SpatialRenderer::SpatialRenderer(cp_layer_renderer_t layerRenderer, SRConfiguration *configuration) :
    _layerRenderer { layerRenderer },
    _configuration { configuration },
    _sceneTime(0.0),
    _lastRenderTime(CACurrentMediaTime())
{
    _device = cp_layer_renderer_get_device(layerRenderer);
    _commandQueue = [_device newCommandQueue];

    makeResources();

    makeRenderPipelines();
}

void SpatialRenderer::makeResources() {
    MTKMeshBufferAllocator *bufferAllocator = [[MTKMeshBufferAllocator alloc] initWithDevice:_device];
    MDLMesh *sphereMesh = [MDLMesh newEllipsoidWithRadii:simd_make_float3(0.34, 0.34, 0.34)
                                          radialSegments:24
                                        verticalSegments:24
                                            geometryType:MDLGeometryTypeTriangles
                                           inwardNormals:NO
                                              hemisphere:NO
                                               allocator:bufferAllocator];
    // Four ModelIO showcase meshes. They all share the Fresnel material, so the
    // silhouette can be compared across smooth, angular and mechanical forms.
    // ModelIO glTF/GLB entry point. The checked-in sample can be replaced by a
    // complete SciFiHelmet.gltf + .bin pair without changing the renderer.
    MDLMesh *externalMesh = nil;
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Materials/Models/SciFiHelmet" withExtension:@"gltf"];
    if (!modelURL) modelURL = [[NSBundle mainBundle] URLForResource:@"SciFiHelmet" withExtension:@"glb"];
    if (modelURL) {
        MDLAsset *asset = [[MDLAsset alloc] initWithURL:modelURL vertexDescriptor:nil bufferAllocator:bufferAllocator];
        for (NSUInteger i = 0; i < asset.count; ++i) {
            if ([asset objectAtIndex:i].class == [MDLMesh class]) {
                externalMesh = (MDLMesh *)[asset objectAtIndex:i];
                break;
            }
        }
    }
    // The helmet is the first hero asset for the holographic HUD. Keep the
    // procedural primitives out of the showcase so silhouette and material
    // treatment can be evaluated on a production-scale mesh.
    _modelMeshes.push_back(std::make_unique<TexturedMesh>(externalMesh ?: sphereMesh, nil, _device));

    _environmentMesh = std::make_unique<SpatialEnvironmentMesh>(@"studio.hdr", 3.0, _device);
}

void SpatialRenderer::makeRenderPipelines() {
    NSError *error = nil;
    cp_layer_renderer_configuration_t layerConfiguration = cp_layer_renderer_get_configuration(_layerRenderer);
    cp_layer_renderer_layout layout = cp_layer_renderer_configuration_get_layout(layerConfiguration);

    MTLRenderPipelineDescriptor *pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    pipelineDescriptor.colorAttachments[0].pixelFormat = cp_layer_renderer_configuration_get_color_format(layerConfiguration);
    pipelineDescriptor.depthAttachmentPixelFormat = cp_layer_renderer_configuration_get_depth_format(layerConfiguration);

    id<MTLLibrary> library = [_device newDefaultLibrary];
    id<MTLFunction> vertexFunction, fragmentFunction;

    BOOL layoutIsDedicated = (layout == cp_layer_renderer_layout_dedicated);
    BOOL layoutIsLayered = (layout == cp_layer_renderer_layout_layered);

    MTLFunctionConstantValues *functionConstants = [MTLFunctionConstantValues new];
    [functionConstants setConstantValue:&layoutIsLayered type:MTLDataTypeBool withName:@"useLayeredRendering"];

    {
        vertexFunction = [library newFunctionWithName: layoutIsDedicated ? @"vertex_dedicated_main" : @"vertex_main"
                                       constantValues:functionConstants
                                                error:&error];
        fragmentFunction = [library newFunctionWithName:@"fragment_main"];
        pipelineDescriptor.vertexFunction = vertexFunction;
        pipelineDescriptor.fragmentFunction = fragmentFunction;
        pipelineDescriptor.vertexDescriptor = _modelMeshes.front()->vertexDescriptor();
        pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
        if (!layoutIsDedicated) {
            pipelineDescriptor.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle;
            pipelineDescriptor.maxVertexAmplificationCount = 2;
        }

        _contentRenderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
        if (_contentRenderPipelineState == nil) {
            NSLog(@"Error occurred when creating render pipeline state: %@", error);
        }
    }
    {
        vertexFunction = [library newFunctionWithName:layoutIsDedicated ? @"vertex_dedicated_environment" : @"vertex_environment"
                                       constantValues:functionConstants
                                                error:&error];
        fragmentFunction = [library newFunctionWithName:@"fragment_environment"];
        pipelineDescriptor.vertexFunction = vertexFunction;
        pipelineDescriptor.fragmentFunction = fragmentFunction;
        pipelineDescriptor.vertexDescriptor = _environmentMesh->vertexDescriptor();
        if (!layoutIsDedicated) {
            pipelineDescriptor.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle;
            pipelineDescriptor.maxVertexAmplificationCount = 2;
        }

        _environmentRenderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
        if (_environmentRenderPipelineState == nil) {
            NSLog(@"Error occurred when creating render pipeline state: %@", error);
        }
    }

    MTLDepthStencilDescriptor *depthDescriptor = [MTLDepthStencilDescriptor new];
    depthDescriptor.depthWriteEnabled = YES;
    depthDescriptor.depthCompareFunction = MTLCompareFunctionGreater;
    _contentDepthStencilState = [_device newDepthStencilStateWithDescriptor:depthDescriptor];

    depthDescriptor.depthWriteEnabled = YES;
    depthDescriptor.depthCompareFunction = MTLCompareFunctionGreater;
    _backgroundDepthStencilState = [_device newDepthStencilStateWithDescriptor:depthDescriptor];
}

void SpatialRenderer::drawAndPresent(cp_frame_t frame, cp_drawable_t drawable) {
    CFTimeInterval renderTime = CACurrentMediaTime();
    CFTimeInterval timestep = MIN(renderTime - _lastRenderTime, 1.0 / 60.0);
    _sceneTime += timestep;

    cp_layer_renderer_configuration_t layerConfiguration = cp_layer_renderer_get_configuration(_layerRenderer);
    cp_layer_renderer_layout layout = cp_layer_renderer_configuration_get_layout(layerConfiguration);

#if TARGET_OS_SIMULATOR
    const float estimatedHeadHeight = 0.0;
#else
    const float estimatedHeadHeight = 1.25;
#endif

    float c = cos(_sceneTime * 0.5f);
    float s = sin(_sceneTime * 0.5f);
    const int32_t gesture = gGesture.load(std::memory_order_relaxed);
    const bool pinchValid = gPinchValid.load(std::memory_order_relaxed) != 0;
    const float pinchX = gPinchX.load(std::memory_order_relaxed);
    const float pinchY = gPinchY.load(std::memory_order_relaxed);
    const float openness = gOpenness.load(std::memory_order_relaxed);
    const float expansion = gExpansion.load(std::memory_order_relaxed);

    // Keep the Metal interaction model deliberately small and deterministic:
    // open hands expand the formation, while a pinch acts as a spatial cursor.
    const float gestureScale = fmaxf(0.72f, 1.0f + openness * 0.22f + expansion * 0.45f - (gesture == 2 ? 0.16f : 0.0f));
    const float cursorX = pinchValid ? fmaxf(-0.55f, fminf(0.55f, pinchX * 0.65f)) : 0.0f;
    const float cursorY = pinchValid ? fmaxf(-0.45f, fminf(0.45f, (pinchY - estimatedHeadHeight) * 0.55f)) : 0.0f;
    const float heroScale = 0.38f * gestureScale;
    simd_float4x4 modelTransform = simd_matrix(simd_make_float4(   c * heroScale, 0.0f,    -s * heroScale, 0.0f),
                                               simd_make_float4(0.0f, heroScale,  0.0f, 0.0f),
                                               simd_make_float4(   s * heroScale, 0.0f,     c * heroScale, 0.0f),
                                               simd_make_float4(cursorX, estimatedHeadHeight + cursorY, -1.65f, 1.0f));
    for (size_t i = 0; i < _modelMeshes.size(); ++i) {
        simd_float4x4 m = modelTransform;
        _modelMeshes[i]->setModelMatrix(m);
        _modelMeshes[i]->setSceneTime((float)_sceneTime + (float)i * 0.7f);
    }

    if (_configuration.immersionStyle == SRImmersionStyleMixed) {
        _environmentMesh->setCutoffAngle(_configuration.portalCutoffAngle);
    } else {
        _environmentMesh->setCutoffAngle(180);
    }

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    size_t viewCount = cp_drawable_get_view_count(drawable);

    std::array<MTLViewport, 2> viewports {};
    std::array<PoseConstants, 2> poseConstants {};
    std::array<PoseConstants, 2> poseConstantsForEnvironment {};
    for (int i = 0; i < viewCount; ++i) {
        viewports[i] = viewportForViewIndex(drawable, i);

        poseConstants[i] = poseConstantsForViewIndex(drawable, i);

        poseConstantsForEnvironment[i] = poseConstantsForViewIndex(drawable, i);
        // Remove the translational part of the view matrix to make the environment stay unreachably far away
        poseConstantsForEnvironment[i].viewMatrix.columns[3] = simd_make_float4(0.0, 0.0, 0.0, 1.0);
    }

    if (layout == cp_layer_renderer_layout_dedicated) {
        // When rendering with a "dedicated" layout, we draw each eye's view to a separate texture.
        // Since we can't switch render targets within a pass, we render one pass per view.
        for (int i = 0; i < viewCount; ++i) {
            MTLRenderPassDescriptor *renderPassDescriptor = createRenderPassDescriptor(drawable, i);
            id<MTLRenderCommandEncoder> renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

            [renderCommandEncoder setCullMode:MTLCullModeBack];

            [renderCommandEncoder setFrontFacingWinding:MTLWindingClockwise];
            [renderCommandEncoder setDepthStencilState:_backgroundDepthStencilState];
            [renderCommandEncoder setRenderPipelineState:_environmentRenderPipelineState];
            _environmentMesh->draw(renderCommandEncoder, &poseConstantsForEnvironment[i], 1);

            [renderCommandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
            [renderCommandEncoder setDepthStencilState:_contentDepthStencilState];
            [renderCommandEncoder setRenderPipelineState:_contentRenderPipelineState];
            for (auto &mesh : _modelMeshes) mesh->draw(renderCommandEncoder, &poseConstants[i], 1);

            [renderCommandEncoder endEncoding];
        }
    } else {
        // When rendering in a "shared" or "layered" layout, we use vertex amplification to efficiently
        // run the vertex pipeline for each view. The "shared" layout uses the viewport array to write
        // each view to a distinct region of a single render target, while the "layered" layout writes
        // each view to a separate slice of the render target array texture.
        MTLRenderPassDescriptor *renderPassDescriptor = createRenderPassDescriptor(drawable, 0);
        id<MTLRenderCommandEncoder> renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

        [renderCommandEncoder setViewports:viewports.data() count:viewCount];
        [renderCommandEncoder setVertexAmplificationCount:viewCount viewMappings:nil];

        [renderCommandEncoder setCullMode:MTLCullModeBack];

        [renderCommandEncoder setFrontFacingWinding:MTLWindingClockwise];
        [renderCommandEncoder setDepthStencilState:_backgroundDepthStencilState];
        [renderCommandEncoder setRenderPipelineState:_environmentRenderPipelineState];
        _environmentMesh->draw(renderCommandEncoder, poseConstantsForEnvironment.data(), viewCount);

        [renderCommandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderCommandEncoder setDepthStencilState:_contentDepthStencilState];
        [renderCommandEncoder setRenderPipelineState:_contentRenderPipelineState];
        for (auto &mesh : _modelMeshes) mesh->draw(renderCommandEncoder, poseConstants.data(), viewCount);

        [renderCommandEncoder endEncoding];
    }

    cp_drawable_encode_present(drawable, commandBuffer);

    [commandBuffer commit];
}

MTLRenderPassDescriptor* SpatialRenderer::createRenderPassDescriptor(cp_drawable_t drawable, size_t index) {
    cp_layer_renderer_configuration_t layerConfiguration = cp_layer_renderer_get_configuration(_layerRenderer);
    cp_layer_renderer_layout layout = cp_layer_renderer_configuration_get_layout(layerConfiguration);

    MTLRenderPassDescriptor *passDescriptor = [[MTLRenderPassDescriptor alloc] init];

    passDescriptor.colorAttachments[0].texture = cp_drawable_get_color_texture(drawable, index);
    if (_configuration.immersionStyle == SRImmersionStyleMixed) {
        passDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    }
    passDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

    passDescriptor.depthAttachment.texture = cp_drawable_get_depth_texture(drawable, index);
    passDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
    passDescriptor.depthAttachment.clearDepth = 0.0;
    passDescriptor.depthAttachment.storeAction = MTLStoreActionStore;

    switch (layout) {
        case cp_layer_renderer_layout_layered:
            passDescriptor.renderTargetArrayLength = cp_drawable_get_view_count(drawable);
            break;
        case cp_layer_renderer_layout_shared:
            // Even though we don't use an array texture as the render target in "shared" layout, we're
            // obligated to set the render target array length because the index is set by the vertex shader.
            passDescriptor.renderTargetArrayLength = 1;
            break;
        case cp_layer_renderer_layout_dedicated:
            break;
    }

    if (cp_drawable_get_rasterization_rate_map_count(drawable) > 0) {
        passDescriptor.rasterizationRateMap = cp_drawable_get_rasterization_rate_map(drawable, index);
    }

    return passDescriptor;
}

MTLViewport SpatialRenderer::viewportForViewIndex(cp_drawable_t drawable, size_t index) {
    cp_view_t view = cp_drawable_get_view(drawable, index);
    cp_view_texture_map_t texture_map = cp_view_get_view_texture_map(view);
    return cp_view_texture_map_get_viewport(texture_map);
}

PoseConstants SpatialRenderer::poseConstantsForViewIndex(cp_drawable_t drawable, size_t index) {
    PoseConstants outPose;

    ar_device_anchor_t anchor = cp_drawable_get_device_anchor(drawable);

    simd_float4x4 poseTransform = ar_anchor_get_origin_from_anchor_transform(anchor);

    cp_view_t view = cp_drawable_get_view(drawable, index);

    if (@available(visionOS 2.0, *)) {
        outPose.projectionMatrix = cp_drawable_compute_projection(drawable,
                                                                  cp_axis_direction_convention_right_up_back,
                                                                  index);
    } else {
        simd_float4 tangents = cp_view_get_tangents(view);
        simd_float2 depth_range = cp_drawable_get_depth_range(drawable);
        SPProjectiveTransform3D projectiveTransform = SPProjectiveTransform3DMakeFromTangents(tangents[0],
                                                                                              tangents[1],
                                                                                              tangents[2],
                                                                                              tangents[3],
                                                                                              depth_range[1],
                                                                                              depth_range[0],
                                                                                              true);
        outPose.projectionMatrix = matrix_float4x4_from_double4x4(projectiveTransform.matrix);
    }

    simd_float4x4 cameraMatrix = simd_mul(poseTransform, cp_view_get_transform(view));
    outPose.viewMatrix = simd_inverse(cameraMatrix);
    return outPose;
}
