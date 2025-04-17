#include <daxa/daxa.inl>

#include <shared.inl>

DAXA_DECL_PUSH_CONSTANT(VoxelizeDrawPush, push)

#if DAXA_SHADER_STAGE == DAXA_SHADER_STAGE_COMPUTE

#if !defined(TEST)
#include "common.glsl"
layout(local_size_x = 128, local_size_y = 1, local_size_z = 1) in;
void main() {
    uint tri_i = gl_GlobalInvocationID.x;
    if (tri_i >= push.triangle_count)
        return;

    MyVertex verts[3];
    verts[0] = deref_i(push.vertices, tri_i * 3 + 0);
    verts[1] = deref_i(push.vertices, tri_i * 3 + 1);
    verts[2] = deref_i(push.vertices, tri_i * 3 + 2);
    daxa_BufferPtr(GpuModelManifest) manifest_ptr = advance(push.model_manifests, verts[0].model_id);

    // [[unroll]]
    // for (int i = 0; i < 3; i++) {
    //     verts[i].pos += sin(deref(push.frame_constants).time + hash31(tri_i * 3 + i)) * 5;
    //     verts[i].pos = clamp(verts[i].pos, deref(manifest_ptr).aabb_min, deref(manifest_ptr).aabb_max);
    // }

    verts[0].pos -= deref(manifest_ptr).aabb_min;
    verts[1].pos -= deref(manifest_ptr).aabb_min;
    verts[2].pos -= deref(manifest_ptr).aabb_min;

    verts[0].pos = verts[0].pos / 256.0 * 2.0 - 1.0;
    verts[1].pos = verts[1].pos / 256.0 * 2.0 - 1.0;
    verts[2].pos = verts[2].pos / 256.0 * 2.0 - 1.0;

    vec3 del_a = verts[1].pos - verts[0].pos;
    vec3 del_b = verts[2].pos - verts[0].pos;
    vec3 nrm = normalize(cross(del_a, del_b));

    float dx = abs(dot(nrm, vec3(1, 0, 0)));
    float dy = abs(dot(nrm, vec3(0, 1, 0)));
    float dz = abs(dot(nrm, vec3(0, 0, 1)));

    uint side = 0;

    if (dx > dy) {
        if (dx > dz) {
            side = 0;
        } else {
            side = 2;
        }
    } else {
        if (dy > dz) {
            side = 1;
        } else {
            side = 2;
        }
    }

    switch (side) {
    case 0:
        verts[0].pos = verts[0].pos.zyx;
        verts[1].pos = verts[1].pos.zyx;
        verts[2].pos = verts[2].pos.zyx;
        break;
    case 1:
        verts[0].pos = verts[0].pos.xzy;
        verts[1].pos = verts[1].pos.xzy;
        verts[2].pos = verts[2].pos.xzy;
        break;
    case 2:
        verts[0].pos = verts[0].pos.xyz;
        verts[1].pos = verts[1].pos.xyz;
        verts[2].pos = verts[2].pos.xyz;
        break;
    }

    verts[0].flags = side;
    verts[1].flags = side;
    verts[2].flags = side;

    deref_i(push.processed_vertices, tri_i * 3 + 0) = verts[0];
    deref_i(push.processed_vertices, tri_i * 3 + 1) = verts[1];
    deref_i(push.processed_vertices, tri_i * 3 + 2) = verts[2];
}
#else

#include "common.glsl"
layout(local_size_x = 128, local_size_y = 1, local_size_z = 1) in;
void main() {
    uint voxel_index = gl_GlobalInvocationID.x;

    vec3 c = vec3(1);
    uint r = uint(sRGB_OETF(c.r) * 255);
    uint g = uint(sRGB_OETF(c.g) * 255);
    uint b = uint(sRGB_OETF(c.b) * 255);
    uint a = (voxel_index % 2) == 0 ? 255 : 0;

    uint u32_voxel = 0;
    u32_voxel = u32_voxel | (r << 0x00);
    u32_voxel = u32_voxel | (g << 0x08);
    u32_voxel = u32_voxel | (b << 0x10);
    u32_voxel = u32_voxel | (a << 0x18);

    daxa_BufferPtr(GpuModelManifest) manifest_ptr = advance(push.model_manifests, push.triangle_count);
    vec3 diff = (deref(manifest_ptr).aabb_max - deref(manifest_ptr).aabb_min);
    uvec3 volume_extent = uvec3(diff);

    if (voxel_index >= volume_extent.x * volume_extent.y * volume_extent.z)
        return;
}
#endif

#elif DAXA_SHADER_STAGE == DAXA_SHADER_STAGE_VERTEX

layout(location = 0) out daxa_f32vec2 v_uv;
layout(location = 1) out uint v_tex_id;
layout(location = 2) out uint v_model_id;
layout(location = 3) out uint v_rotation;

void main() {
    MyVertex vert = deref_i(push.processed_vertices, gl_VertexIndex);

    gl_Position = daxa_f32vec4(vert.pos * vec3(1, 1, 0.5) + vec3(0, 0, 0.5), 1);

    v_uv = vert.uv;
    v_tex_id = vert.tex_id.value;
    v_rotation = vert.flags;
    v_model_id = vert.model_id;
}

#elif DAXA_SHADER_STAGE == DAXA_SHADER_STAGE_FRAGMENT

#extension GL_EXT_shader_atomic_int64 : require

#include "common.glsl"

layout(location = 0) in daxa_f32vec2 v_uv;
layout(location = 1) in flat uint v_tex_id;
layout(location = 2) in flat uint v_model_id;
layout(location = 3) in flat uint v_rotation;

void main() {
    daxa_ImageViewId tex = daxa_ImageViewId(v_tex_id);
    vec4 tex_col = texture(daxa_sampler2D(tex, deref(push.frame_constants).sampler_llr), v_uv);
    tex_col.a = 6; // WEAK_METAL

    daxa_BufferPtr(GpuModelManifest) manifest_ptr = advance(push.model_manifests, v_model_id);
    vec3 diff = (deref(manifest_ptr).aabb_max - deref(manifest_ptr).aabb_min);
    uvec3 volume_extent = uvec3(diff);

    vec3 p = gl_FragCoord.xyz;
    p.z = p.z * 256;
    switch (v_rotation) {
    case 0: p = p.zyx; break;
    case 1: p = p.xzy; break;
    case 2: break;
    }

    uvec3 local_grid_pos = uvec3(deref(manifest_ptr).aabb_min - push.total_aabb_min);

    uvec3 local_vp = clamp(uvec3(floor(p)), uvec3(0), uvec3(volume_extent - 1));
    uint o_index = local_vp.x + local_vp.y * volume_extent.x + local_vp.z * volume_extent.x * volume_extent.y;

    vec3 total_diff = push.total_aabb_max - push.total_aabb_min;
    uvec3 total_brick_volume_extent = uvec3(floor(total_diff)) / 4;

    uvec3 world_vp = local_grid_pos + local_vp;
    uvec3 brick_pos = world_vp / 4;
    uvec3 in_brick_pos = world_vp % 4;
    uint brick_index = (brick_pos.x + brick_pos.y * total_brick_volume_extent.x + brick_pos.z * total_brick_volume_extent.x * total_brick_volume_extent.y);

    uint in_brick_index = in_brick_pos.x + in_brick_pos.y * 4 + in_brick_pos.z * 4 * 4;
    uint64_t new_bitmask = uint64_t(1) << in_brick_index;
    uint64_t old_bitmask = atomicOr(deref_i(push.voxel_bitmask, brick_index).bits, new_bitmask);

    if ((new_bitmask & old_bitmask) == 0) {
        atomicExchange(deref_i(deref(manifest_ptr).voxels, o_index).color, pack_color(tex_col));
    }
}

#endif
