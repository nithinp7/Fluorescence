#include "SimpleObjLoader.h"

#include <Althea/Application.h>
#include <Althea/Containers/StackVector.h>

#include <cstdint>
#include <cstdio>
#include <fstream>

namespace flr {
namespace SimpleObjLoader {

bool loadObj(
    Application& app,
    VkCommandBuffer commandBuffer,
    const char* fileName,
    LoadedObj& result) {
  std::ifstream file(fileName, std::ios::ate | std::ios::binary);

  if (!file.is_open()) {
    return false;
  }

  size_t fileSize = (size_t)file.tellg();

  file.seekg(0);

  // TODO: need to be able to fall-back if we blow this capacity...
  size_t CAPACITY = 8192;
  std::vector<glm::vec3> positions;
  positions.reserve(CAPACITY);
  std::vector<glm::vec2> uvs;
  uvs.reserve(CAPACITY);
  std::vector<glm::vec3> normals;
  normals.reserve(CAPACITY);

  ObjMesh* mesh = &result.m_meshes.emplace_back();
  uint32_t indexCounter = 0;
  std::vector<ObjVert> vertices;
  vertices.reserve(CAPACITY);
  std::vector<uint32_t> indices;
  indices.reserve(CAPACITY);

  bool bHasNormals = false;

  auto parseUint = [](char*& pBuf)
  {
    uint32_t res = 0u;
    while (*pBuf >= '0' && *pBuf <= '9') {
      res = 10u * res + (uint32_t)(*pBuf - '0');
      pBuf++;
    }
    return res;
  };

  auto consumeChar = [](char*& pBuf, char c) {
    if (*pBuf == c)
      pBuf++;
  };

  auto createTriangle = [&](uint32_t v0,
                            uint32_t vt0,
                            uint32_t vn0,
                            uint32_t v1,
                            uint32_t vt1,
                            uint32_t vn1,
                            uint32_t v2,
                            uint32_t vt2,
                            uint32_t vn2) {
    if (positions.size() > vertices.size())
      vertices.resize(positions.size());

    indices.push_back(v0 - 1);
    indices.push_back(v1 - 1);
    indices.push_back(v2 - 1);

    ObjVert& vert0 = vertices[v0 - 1];
    vert0.position = positions[v0 - 1];
    vert0.uv = (vt0 > 0) ? uvs[vt0 - 1] : glm::vec2(0.0f);

    ObjVert& vert1 = vertices[v1 - 1];
    vert1.position = positions[v1 - 1];
    vert1.uv = (vt1 > 0) ? uvs[vt1 - 1] : glm::vec2(0.0f);

    ObjVert& vert2 = vertices[v2 - 1];
    vert2.position = positions[v2 - 1];
    vert2.uv = (vt2 > 0) ? uvs[vt2 - 1] : glm::vec2(0.0f);

    if (!bHasNormals) {
      glm::vec3 normal = glm::cross(
          vert1.position - vert0.position,
          vert2.position - vert0.position);
      vert0.normal += normal;
      vert1.normal += normal;
      vert2.normal += normal;
    } else {
      vert0.normal = normals[vn0 - 1];
      vert1.normal = normals[vn1 - 1];
      vert2.normal = normals[vn2 - 1];
    }
  };

  char lineBuf[1024];
  while (true) {
    file.getline(lineBuf, 1024);
    if (file.gcount() == 0)
      break;

    switch (lineBuf[0]) {
    case 'v':
      switch (lineBuf[1]) {
      case ' ':
        // position
        {
          glm::vec3& pos = positions.emplace_back();
          int ret = std::sscanf(&lineBuf[2], "%f %f %f", &pos.x, &pos.y, &pos.z);
          assert(ret == 3);
        }
        break;
      case 't':
        // uv
        {
          glm::vec2& uv = uvs.emplace_back();
          int ret = std::sscanf(&lineBuf[2], "%f %f", &uv.x, &uv.y);
          assert(ret == 2);
        }
        break;
      case 'n':
        // normal
        {
          glm::vec3& normal = normals.emplace_back();
          int ret = std::sscanf(&lineBuf[3], "%f %f %f", &normal.x, &normal.y, &normal.z);
          assert(ret == 3);
          bHasNormals = true;
        }
        break;
      }
      break;
    case 'g':
      // start new mesh
      {
        if (indices.size() > 0) {
          // The last mesh was valid so finalize it and start a new one
          mesh->m_indices = IndexBuffer(app, commandBuffer, std::move(indices));
          indices.clear();

          mesh = &result.m_meshes.emplace_back();
        }

        std::strncpy(mesh->name, &lineBuf[2], 128);
      }
      break;
    case 'f':
      // face
      {
        // 3 or 4 verts - pos0, uv0, normal0, pos1, uv1, ... etc
        uint32_t vi[12] = { 0u };
        uint32_t offs = 2;
        char* pBuf = lineBuf + 2;
        for (int i = 0; i < 4; i++) {
          for (int j = 0; j < 3; j++) {
            vi[3 * i + j] = parseUint(pBuf);
            consumeChar(pBuf, '/');
          }
          consumeChar(pBuf, ' ');
        }

        // assumes the referenced verts have all been
        // specified earlier in the file
        assert(vi[0] > 0u && vi[3] > 0u && vi[6] > 0u);
        if (vi[9] > 0u) {
          // quad
          createTriangle(vi[0], vi[1], vi[2], vi[3], vi[4], vi[5], vi[6], vi[7], vi[8]);
          createTriangle(vi[0], vi[1], vi[2], vi[6], vi[7], vi[8], vi[9], vi[10], vi[11]);
        } else {
          // tri
          createTriangle(vi[0], vi[1], vi[2], vi[3], vi[4], vi[5], vi[6], vi[7], vi[8]);
        }
      }
      break;
    case '#':
    default:
      break;
    }
  }

  for (ObjVert& vert : vertices) {
    vert.normal = glm::normalize(vert.normal);
  }

  if (vertices.size() > 0) {
    result.m_vertices =
        VertexBuffer<ObjVert>(app, commandBuffer, std::move(vertices));
  }

  if (indices.size() > 0) {
    mesh->m_indices = IndexBuffer(app, commandBuffer, std::move(indices));
  }

  file.close();

  return true;
}

} // namespace SimpleObjLoader
} // namespace flr