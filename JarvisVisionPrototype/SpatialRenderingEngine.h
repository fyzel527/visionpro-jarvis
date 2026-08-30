#pragma once

#import <Foundation/Foundation.h>
#import <CompositorServices/CompositorServices.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SRImmersionStyle) {
    SRImmersionStyleFull,
    SRImmersionStyleMixed,
};

// A type for communicating immersion style changes from SwiftUI views to the low-level rendering layer
@interface SRConfiguration : NSObject
@property (assign) SRImmersionStyle immersionStyle;
@property (assign) CGFloat portalCutoffAngle;
- (instancetype)initWithImmersionStyle:(SRImmersionStyle)immersionStyle;
@end

#if __cplusplus
extern "C" {
#endif

void SpatialRenderer_InitAndRun(cp_layer_renderer_t layerRenderer, SRConfiguration *configuration);

// Latest hand-tracking snapshot consumed by the Metal render thread.
void SpatialRenderer_SetHandTrackingState(
    int32_t gesture,
    float pinchX,
    float pinchY,
    float pinchZ,
    int32_t pinchValid,
    float openness,
    float expansion
);

#if __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
