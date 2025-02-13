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
    ;
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
          std::sscanf(&lineBuf[2], "%f %f %f", &pos.x, &pos.y, &pos.z);
        }
        break;
      case 't':
        // uv
        {
          glm::vec2& uv = uvs.emplace_back();
          std::sscanf(&lineBuf[2], "%f %f", &uv.x, &uv.y);
        }
        break;
      case 'n':
        // normal
        {
          glm::vec3& normal = normals.emplace_back();
          std::sscanf(&lineBuf[3], "%f %f %f", &normal.x, &normal.y, &normal.z);
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
        uint32_t v0, vt0, vn0, v1, vt1, vn1, v2, vt2, vn2, v3, vt3, vn3;
        int ret = sscanf(
            &lineBuf[2],
            "%u/%u/%u %u/%u/%u %u/%u/%u %u/%u/%u",
            &v0,
            &vt0,
            &vn0,
            &v1,
            &vt1,
            &vn1,
            &v2,
            &vt2,
            &vn2,
            &v3,
            &vt3,
            &vn3);

        // assumes the references verts have all been
        // specified earlier in the file
        if (ret == 9) {
          // triangle
          createTriangle(v0, vt0, vn0, v1, vt1, vn1, v2, vt2, vn2);
        } else if (ret == 12) {
          // quad
          createTriangle(v0, vt0, vn0, v1, vt1, vn1, v2, vt2, vn2);
          createTriangle(v0, vt0, vn0, v2, vt2, vn2, v3, vt3, vn3);
        } else {
          // try just vert / uv
          ret = sscanf(
              &lineBuf[2],
              "%u/%u %u/%u %u/%u %u/%u",
              &v0,
              &vt0,
              &v1,
              &vt1,
              &v2,
              &vt2,
              &v3,
              &vt3);
          if (ret == 6) {
            // triangle
            createTriangle(v0, vt0, 0, v1, vt1, 0, v2, vt2, 0);
          } else if (ret == 8) {
            // quad
            createTriangle(v0, vt0, 0, v1, vt1, 0, v2, vt2, 0);
            createTriangle(v0, vt0, 0, v2, vt2, 0, v3, vt3, 0);
          } else {
            assert(false);
          }
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