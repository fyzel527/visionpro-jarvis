#include <metal_stdlib>
using namespace metal;

struct MetalParticle {
    float2 position;
    float2 velocity;
    float4 color;
    float life;
    float maxLife;
    float size;
    uint seed;
};

struct MetalEmitter {
    float2 position;
    float2 direction;
    float4 color;
};

struct MetalParticleUniforms {
    float deltaTime;
    float time;
    uint particleCount;
    uint emitterCount;
    float aspect;
    float padding0;
    float padding1;
    float padding2;
};

static uint hashValue(uint value) {
    value ^= value >> 16;
    value *= 0x7feb352d;
    value ^= value >> 15;
    value *= 0x846ca68b;
    value ^= value >> 16;
    return value;
}

static float random01(thread uint &seed) {
    seed = hashValue(seed);
    return float(seed & 0x00ffffff) / float(0x01000000);
}

kernel void metalParticleUpdate(
    device MetalParticle *particles [[buffer(0)]],
    constant MetalEmitter *emitters [[buffer(1)]],
    constant MetalParticleUniforms &uniforms [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= uniforms.particleCount || uniforms.emitterCount == 0) {
        return;
    }

    MetalParticle particle = particles[id];
    particle.life -= uniforms.deltaTime;

    if (particle.life <= 0.0) {
        uint seed = particle.seed ^ hashValue(id + uint(uniforms.time * 1000.0));
        uint emitterIndex = id % uniforms.emitterCount;
        MetalEmitter emitter = emitters[emitterIndex];

        float2 direction = normalize(emitter.direction);
        float2 tangent = float2(-direction.y, direction.x);
        float spread = (random01(seed) - 0.5) * 0.85;
        float speed = 0.28 + random01(seed) * 0.54;
        float2 jitter = tangent * ((random01(seed) - 0.5) * 0.032);

        particle.position = emitter.position + jitter;
        particle.velocity = normalize(direction + tangent * spread) * speed;
        particle.color = emitter.color;
        particle.maxLife = 0.58 + random01(seed) * 0.62;
        particle.life = particle.maxLife;
        particle.size = 4.0 + random01(seed) * 8.0;
        particle.seed = seed;
    } else {
        float age = 1.0 - saturate(particle.life / max(particle.maxLife, 0.001));
        float2 curl = float2(
            sin(uniforms.time * 2.3 + float(id) * 0.013),
            cos(uniforms.time * 1.9 + float(id) * 0.017)
        ) * 0.055;
        particle.velocity += curl * uniforms.deltaTime;
        particle.velocity *= 1.0 - 0.18 * uniforms.deltaTime;
        particle.position += particle.velocity * uniforms.deltaTime;
        particle.size *= 1.0 + age * 0.018;
    }

    particles[id] = particle;
}

struct ParticleVertexOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
};

vertex ParticleVertexOut metalParticleVertex(
    device const MetalParticle *particles [[buffer(0)]],
    constant MetalParticleUniforms &uniforms [[buffer(1)]],
    uint vertexID [[vertex_id]]
) {
    MetalParticle particle = particles[vertexID];
    float normalizedLife = saturate(particle.life / max(particle.maxLife, 0.001));
    float fade = smoothstep(0.0, 0.22, normalizedLife) * smoothstep(1.0, 0.64, normalizedLife);

    ParticleVertexOut out;
    out.position = float4(particle.position.x, particle.position.y, 0.0, 1.0);
    out.color = float4(particle.color.rgb * fade, particle.color.a * fade);
    out.pointSize = particle.size;
    return out;
}

fragment float4 metalParticleFragment(
    ParticleVertexOut in [[stage_in]],
    float2 pointCoordinate [[point_coord]]
) {
    float2 uv = pointCoordinate * 2.0 - 1.0;
    float distanceSquared = dot(uv, uv);
    float alpha = smoothstep(1.0, 0.08, distanceSquared);
    return float4(in.color.rgb * alpha, in.color.a * alpha);
}

struct MetalImmersiveParticle {
    float3 position;
    float3 velocity;
    float4 color;
    float life;
    float maxLife;
    float size;
    uint seed;
};

struct MetalImmersiveEmitter {
    float3 position;
    float3 direction;
    float4 color;
};

struct MetalImmersiveParticleUniforms {
    float deltaTime;
    float time;
    uint particleCount;
    uint emitterCount;
    float fieldScale;
    float padding0;
    float padding1;
    float padding2;
};

struct MetalImmersiveViewProjectionArray {
    float4x4 viewProjectionMatrix[2];
};

kernel void metalImmersiveParticleUpdate(
    device MetalImmersiveParticle *particles [[buffer(0)]],
    constant MetalImmersiveEmitter *emitters [[buffer(1)]],
    constant MetalImmersiveParticleUniforms &uniforms [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= uniforms.particleCount || uniforms.emitterCount == 0) {
        return;
    }

    MetalImmersiveParticle particle = particles[id];
    particle.life -= uniforms.deltaTime;

    if (particle.life <= 0.0) {
        uint seed = particle.seed ^ hashValue(id + uint(uniforms.time * 1000.0));
        uint emitterIndex = id % uniforms.emitterCount;
        MetalImmersiveEmitter emitter = emitters[emitterIndex];

        float3 direction = normalize(emitter.direction);
        float3 reference = fabs(direction.y) < 0.92 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
        float3 right = normalize(cross(reference, direction));
        float3 up = normalize(cross(direction, right));

        float angle = random01(seed) * 6.28318530718;
        float spread = random01(seed) * 0.78;
        float3 spreadDirection = normalize(
            direction * (0.72 + random01(seed) * 0.45)
            + right * cos(angle) * spread
            + up * sin(angle) * spread
        );
        float3 jitter = (right * (random01(seed) - 0.5) + up * (random01(seed) - 0.5)) * 0.026;
        float speed = 0.20 + random01(seed) * 0.62;

        particle.position = emitter.position + jitter;
        particle.velocity = spreadDirection * speed;
        particle.color = emitter.color;
        particle.maxLife = 0.62 + random01(seed) * 0.75;
        particle.life = particle.maxLife;
        particle.size = 28.0 + random01(seed) * 28.0;
        particle.seed = seed;
    } else {
        float age = 1.0 - saturate(particle.life / max(particle.maxLife, 0.001));
        float idValue = float(id);
        float3 curl = float3(
            sin(uniforms.time * 2.4 + idValue * 0.011),
            cos(uniforms.time * 2.0 + idValue * 0.013),
            sin(uniforms.time * 1.7 + idValue * 0.017)
        ) * 0.075 * uniforms.fieldScale;

        particle.velocity += curl * uniforms.deltaTime;
        particle.velocity *= 1.0 - 0.16 * uniforms.deltaTime;
        particle.position += particle.velocity * uniforms.deltaTime;
        particle.size *= 1.0 + age * 0.014;
    }

    particles[id] = particle;
}

struct MetalImmersiveParticleVertexOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
    float time;
};

vertex MetalImmersiveParticleVertexOut metalImmersiveParticleVertex(
    device const MetalImmersiveParticle *particles [[buffer(0)]],
    constant MetalImmersiveViewProjectionArray &viewProjectionArray [[buffer(1)]],
    ushort amplificationID [[amplification_id]],
    uint vertexID [[vertex_id]]
) {
    MetalImmersiveParticle particle = particles[vertexID];
    float normalizedLife = saturate(particle.life / max(particle.maxLife, 0.001));
    float fade = smoothstep(0.0, 0.20, normalizedLife) * smoothstep(1.0, 0.58, normalizedLife);

    MetalImmersiveParticleVertexOut out;
    out.position = viewProjectionArray.viewProjectionMatrix[amplificationID] * float4(particle.position, 1.0);
    out.color = float4(particle.color.rgb * fade, particle.color.a * fade);
    out.pointSize = particle.size * (0.85 + fade * 0.4);
    out.time = particle.life;
    return out;
}

fragment float4 metalImmersiveParticleFragment(
    MetalImmersiveParticleVertexOut in [[stage_in]],
    float2 pointCoordinate [[point_coord]]
) {
    float2 uv = pointCoordinate * 2.0 - 1.0;
    float distanceSquared = dot(uv, uv);
    float alpha = smoothstep(1.0, 0.05, distanceSquared);
    float fresnel = pow(saturate(distanceSquared), 1.7);
    float noise = 0.86 + 0.14 * sin(in.time * 7.0 + pointCoordinate.x * 31.0 + pointCoordinate.y * 19.0);
    float scan = 0.75 + 0.25 * sin(in.time * 2.6 + pointCoordinate.y * 24.0);
    float core = smoothstep(0.30, 0.0, distanceSquared);
    float3 color = in.color.rgb * (alpha * (0.35 + fresnel * 2.0) + core * 0.9) * noise * scan;
    return float4(color, in.color.a * alpha * (0.5 + fresnel * 0.8));
}
