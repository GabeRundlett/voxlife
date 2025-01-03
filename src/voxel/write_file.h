
#ifndef VOXLIFE_VOXEL_WRITEFILE_H
#define VOXLIFE_VOXEL_WRITEFILE_H

#include <string_view>
#include <span>
#include <array>
#include <glm/vec3.hpp>
#include <string>

enum MaterialType : uint8_t {
    AIR,
    UN_PHYSICAL,
    HARD_MASONRY,
    HARD_METAL,
    PLASTIC,
    HEAVY_METAL,
    WEAK_METAL,
    PLASTER,
    BRICK,
    CONCRETE,
    WOOD,
    ROCK,
    DIRT,
    GRASS,
    GLASS,
    MATERIAL_ALL_TYPES,
    MATERIAL_TYPE_MAX,
};

struct Voxel {
    glm::u8vec3 color;
    MaterialType material = MaterialType::AIR;
};

struct VoxelModel {
    std::span<const Voxel> voxels;
    glm::i32vec3 pos;
    glm::u32vec3 size;
};

struct Model {
    std::string name; // the name it should have when saved as a .vox file
    glm::vec3 pos;    // relative to the scene
    glm::vec3 rot;
    glm::u32vec3 size;
};

struct Light {
    glm::vec3 pos;
    glm::u8vec3 color;
    float intensity;
};

struct Location {
    std::string name;
    glm::vec3 pos;
};

struct Trigger {
    std::string map;
    std::string landmark;
    glm::vec3 pos;
    glm::vec3 size;
};

struct Environment {
    std::string skybox;
    float brightness;
    glm::vec3 sun_color;
    glm::vec3 sun_dir; // sun rotation angles? or normalized vector??
};

struct Npc {
    std::string path_name;
    glm::vec3 pos;
    glm::vec3 rot;
};

struct LevelInfo {
    std::string_view name;
    std::span<const Model> models;
    std::span<const Light> lights;
    std::span<const Location> locations;
    std::span<const Trigger> triggers;
    std::span<const Npc> npcs;
    glm::vec3 level_pos;
    Environment environment;
    // temp
    glm::vec3 spawn_pos;
    glm::vec3 spawn_rot;
};

void write_magicavoxel_model(std::string_view filename, std::span<const VoxelModel> in_models);

void write_teardown_level(const LevelInfo &info);

#endif // VOXLIFE_VOXEL_WRITEFILE_H
