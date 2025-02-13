#pragma once

#include <Althea/ImageResource.h>
#include <Althea/IndexBuffer.h>
#include <Althea/VertexBuffer.h>
#include <glm/glm.hpp>
#include <vulkan/vulkan.h>

#include <vector>

using namespace AltheaEngine;

namespace flr {
namespace SimpleObjLoader {

struct ObjVert {
  ObjVert() : position(0.0f), normal(0.0f), uv(0.0f) {}
  glm::vec3 position;
  glm::vec3 normal;
  glm::vec2 uv;
};

struct ObjMesh {
  char name[128] = {0};
  IndexBuffer m_indices;
  int m_albedo = -1;
  int m_normal = -1;
  int m_metallicRoughness = -1;
};

struct LoadedObj {
  VertexBuffer<ObjVert> m_vertices;
  std::vector<ImageResource> m_images;
  std::vector<ObjMesh> m_meshes;
};

bool loadObj(
    Application& app,
    VkCommandBuffer commandBuffer,
    const char* fileName,
    LoadedObj& result);

} // namespace SimpleObjLoader
} // namespace flr