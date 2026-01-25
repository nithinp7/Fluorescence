#pragma once

#include "Shared/CommonStructures.h"

#include <Althea/IndexBuffer.h>
#include <Althea/VertexBuffer.h>
#include <glm/glm.hpp>
#include <vulkan/vulkan.h>

#include <vector>

using namespace AltheaEngine;

namespace flr {
namespace SimpleObjLoader {

struct ParsedObjMesh {
  char name[128] = {0};
  std::vector<uint32_t> m_indices;
};

struct ParsedObj {
  std::vector<ObjVertex> m_vertices;
  std::vector<ParsedObjMesh> m_meshes;
};

bool parseObj(const char* fileName, ParsedObj& result);

struct LoadedObjMesh {
  IndexBuffer m_indices;
};

struct LoadedObj {
  VertexBuffer<ObjVertex> m_vertices;
  std::vector<LoadedObjMesh> m_meshes;
};

bool loadObj(
    Application& app,
    VkCommandBuffer commandBuffer,
    const ParsedObj& parsed,
    LoadedObj& result);

} // namespace SimpleObjLoader
} // namespace flr