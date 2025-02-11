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
  glm::vec3 position;
  glm::vec3 normal;
  glm::vec2 uv;
};

struct ObjMesh {
  char name[128] = {0};
  VertexBuffer<ObjVert> m_vertices;
  int m_albedo = -1;
  int m_normal = -1;
  int m_metallicRoughness = -1;
};

struct LoadedObj {
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