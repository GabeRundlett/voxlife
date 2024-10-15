
#include "rasterize_polygon.h"

#include <optional>
#include <vector>
#include <numeric>
#include <cmath>
#include <fstream>
#include <chrono>
#include <iostream>


using namespace voxlife::voxel;

struct varying_occupancy : public varying_base {
    std::vector<bool> grid;

    varying_occupancy() = delete;
    explicit varying_occupancy(const voxlife::voxel::grid_properties& grid_info) : varying_base(grid_info), grid(grid_info.width * grid_info.height) {}
    ~varying_occupancy() override = default;

    void interpolate_row(const interpolation_info &info) override;
};


void create_rasterizer(const grid_properties& grid_info, rasterizer_handle* handle) {
    *handle = reinterpret_cast<rasterizer_handle>(new rasterizer(grid_info));
}

void create_occupancy_varying(rasterizer_handle rasterizer, varying_handle* handle) {
    auto& rasterizer_ref = *reinterpret_cast<struct rasterizer*>(rasterizer);

    varying_base* varying = new varying_occupancy(rasterizer_ref.grid_info);
    rasterizer_ref.varyings.push_back(varying);

    *handle = reinterpret_cast<varying_handle>(varying);
}

void rasterize_polygon(rasterizer_handle rasterizer, std::span<vec2f32> points) {
    auto& rasterizer_ref = *reinterpret_cast<struct rasterizer*>(rasterizer);

    rasterizer_ref.rasterize_polygon(points);
}

/*std::span<bool> get_occupancy_varying_grid(varying_handle varying) {
    auto& varying_ref = *reinterpret_cast<struct varying_occupancy*>(varying);

    return std::span(varying_ref.grid);
}*/


struct vec2 {
    float x, y;

    vec2 operator*(float s) const {
        return vec2{x * s, y * s};
    }

    vec2 operator/(float s) const {
        return vec2{x / s, y / s};
    }

    vec2 operator+(const vec2& other) const {
        return vec2{x + other.x, y + other.y};
    }

    vec2 operator-(const vec2& other) const {
        return vec2{x - other.x, y - other.y};
    }

    vec2 operator+=(const vec2& other) {
        x += other.x;
        y += other.y;
        return *this;
    }

    vec2 operator-=(const vec2& other) {
        x -= other.x;
        y -= other.y;
        return *this;
    }
};


/// Intersects a horizontal ray with a line segment
/// \param ray_y vertical position of the ray
/// \param p1 Point 1 on the line segment
/// \param p2 Point 2 on the line segment
/// \return Horizontal position of the intersection, or std::nullopt if no intersection
std::optional<float> intersectRayWithLine(float ray_y, const voxlife::voxel::vec2f32& p1, const voxlife::voxel::vec2f32& p2) {
    if (p1.y == p2.y)
        return std::nullopt;

    float s = (ray_y - p1.y) / (p2.y - p1.y);
    float x_intersect = p1.x + s * (p2.x - p1.x);

    return x_intersect;
}


void varying_occupancy::interpolate_row(const interpolation_info &info) {
    auto line_begin = grid.begin() + info.line_y * grid_info.width;

    std::fill(line_begin + info.front_intersection_index, line_begin + info.back_intersection_index, true);
}


void rasterizer::rasterize_polygon(std::span<voxlife::voxel::vec2f32> points) {
    size_t lowest_point_index;

    {
        float min_y = std::numeric_limits<float>::max();
        size_t point_index = 0;
        for (auto &point: points) {
            if (point.y < min_y) {
                lowest_point_index = point_index;
                min_y = point.y;
            }

            point_index++;
        }
    }

    float min_x = grid_info.origin.x + 0.5f;
    float min_y = grid_info.origin.y + 0.5f;
    auto grid_width_float = static_cast<float>(grid_info.width - 1);
    auto grid_height_float = static_cast<float>(grid_info.height - 1);

    uint32_t point_count_minus_one = points.size() - 1;
    uint32_t front_point_1_index = lowest_point_index;
    uint32_t front_point_2_index = lowest_point_index == point_count_minus_one ? 0 : lowest_point_index + 1;
    uint32_t back_point_1_index = lowest_point_index;
    uint32_t back_point_2_index = lowest_point_index == 0 ? point_count_minus_one : lowest_point_index - 1;
    float front_length_y = points[front_point_2_index].y - points[front_point_1_index].y;
    float back_length_y = points[back_point_2_index].y - points[back_point_1_index].y;
    for (uint32_t y = 0; y < grid_info.height; ++y) {
        float absolute_y = static_cast<float>(y) + min_y;
        if (absolute_y > points[front_point_2_index].y) {
            front_point_1_index = front_point_2_index;
            front_point_2_index = front_point_2_index == point_count_minus_one ? 0 : front_point_2_index + 1;
            front_length_y = points[front_point_2_index].y - points[front_point_1_index].y;
        }

        if (absolute_y > points[back_point_2_index].y) {
            back_point_1_index = back_point_2_index;
            back_point_2_index = back_point_2_index == 0 ? point_count_minus_one : back_point_2_index - 1;
            back_length_y = points[back_point_2_index].y - points[back_point_1_index].y;
        }

        auto font_intersection = intersectRayWithLine(absolute_y, points[front_point_1_index], points[front_point_2_index]);
        auto back_intersection = intersectRayWithLine(absolute_y, points[back_point_1_index],  points[back_point_2_index]);
        if (!font_intersection || !back_intersection)
            continue;

        float line_front = font_intersection.value() - min_x;
        float line_back = back_intersection.value() - min_x;

        auto line_min = static_cast<uint32_t>(std::min(std::max(std::round(line_front), 0.0f), grid_width_float));
        auto line_max = static_cast<uint32_t>(std::min(std::max(std::round(line_back), 0.0f), grid_width_float));

        if (line_min > line_max) [[unlikely]]  // This should never happen in a convex polygon
            throw std::runtime_error("Line min is greater than line max");

        interpolation_info info{};
        info.front_point_1_index = front_point_1_index;
        info.front_point_2_index = front_point_2_index;
        info.back_point_1_index = back_point_1_index;
        info.back_point_2_index = back_point_2_index;
        info.line_y = y;
        info.relative_front_y = (absolute_y - points[front_point_1_index].y) / front_length_y;
        info.relative_back_y = (absolute_y - points[back_point_1_index].y) / back_length_y;
        info.front_intersection = line_front;
        info.back_intersection = line_back;
        info.front_intersection_index = line_min;
        info.back_intersection_index = line_max;

        for (auto& varying : varyings)
            varying->interpolate_row(info);
    }
}

/*
void raster_test() {
    std::vector<vec2f32> points{};
    std::vector<float> depth;
    std::vector<vec2> uvs;

    size_t point_count = 20;
    float radius = 500.0f;
    points.reserve(point_count);
    depth.reserve(point_count);
    for (int i = 0; i < point_count; ++i) {
        float angle = static_cast<float>(i) / static_cast<float>(point_count) * 2.0f * M_PIf;
        float x = std::sin(angle) * -radius;
        float y = std::cos(angle) * -radius;
        points.emplace_back(x, y);

        depth.emplace_back(std::sin(angle * 2));
        uvs.emplace_back(std::sin(angle * 2), std::cos(angle * 2));
    }

    grid_properties grid_info{};
    grid_info.width = static_cast<uint32_t>(radius * 2);
    grid_info.height = static_cast<uint32_t>(radius * 2);
    grid_info.origin = vec2f32{-radius, -radius};

    rasterizer_handle rasterizer;
    create_rasterizer(grid_info, &rasterizer);

    //varying_handle v_occ;
    //create_occupancy_varying(rasterizer, &v_occ);
    varying_handle v_depth;
    create_smooth_varying(rasterizer, std::span(depth), &v_depth);
    varying_handle v_uv;
    create_smooth_varying(rasterizer, std::span(uvs), &v_uv);

    std::chrono::high_resolution_clock::time_point start = std::chrono::high_resolution_clock::now();
    rasterize_polygon(rasterizer, std::span(points));
    std::chrono::high_resolution_clock::time_point end = std::chrono::high_resolution_clock::now();
    std::cout << "Grid size: " << grid_info.width << " x " << grid_info.height << std::endl;
    std::chrono::duration<float, std::micro> elapsed = end - start;
    std::cout << "Rasterization took: " << elapsed << std::endl;
    std::chrono::duration<float, std::nano> elapsed_pixel = (end - start) / static_cast<float>(grid_info.width * grid_info.height);
    std::cout << "Per pixel: " << elapsed_pixel  << std::endl;

    auto depth_data = voxlife::voxel::get_smooth_varying_grid<float>(v_depth);

    auto file = std::ofstream("depth.ppm", std::ios::out);
    file << "P2\n";
    file << grid_info.width << " " << grid_info.height << "\n";
    file << "255\n";

    for (auto x = 0; x < grid_info.width; ++x) {
        for (auto y = 0; y < grid_info.height; ++y) {
            auto d = depth_data[y * grid_info.width + x];
            file << +static_cast<uint8_t>((d + 1.0f) / 2.0f * 255.0f) << ' ';
        }
        file << '\n';
    }
    file.close();

    auto uv_data = voxlife::voxel::get_smooth_varying_grid<vec2>(v_uv);

    file = std::ofstream("uv.ppm", std::ios::out);
    file << "P3\n";
    file << grid_info.width << " " << grid_info.height << "\n";
    file << "255\n";

    for (auto x = 0; x < grid_info.width; ++x) {
        for (auto y = 0; y < grid_info.height; ++y) {
            auto d = uv_data[y * grid_info.width + x];
            file << +static_cast<uint8_t>((d.x + 1.0f) / 2.0f * 255.0f) << ' ';
            file << +static_cast<uint8_t>((d.y + 1.0f) / 2.0f * 255.0f) << ' ';
            file << "0\n";
        }
    }
    file.close();
}
 */