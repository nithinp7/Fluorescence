#include "Project.h"

#include <stdio.h>
#include <string.h>

#include <filesystem>
#include <fstream>
#include <optional>
#include <utility>
#include <xstring>

using namespace AltheaEngine;

namespace flr {
Project::Project(const char* projPath) : m_parsed(projPath) {
  std::filesystem::path projPath_(projPath);
  std::filesystem::path projName = projPath_.stem();
  std::filesystem::path folder = projPath_.parent_path();

  char shaderPath[256];
  sprintf(shaderPath, "%ls/%ls.glsl", folder.c_str(), projName.c_str());
}

ParsedFlr::ParsedFlr(const char* filename) {

  std::ifstream flrFile(filename);
  char lineBuf[1024];
  while (flrFile.getline(lineBuf, 1024)) {
    char* c = lineBuf;

    auto parseChar = [&](char ref) -> std::optional<char> {
      if (*c == ref) {
        char cr = *c;
        c++;
        return cr;
      }
      return std::nullopt;
    };

    auto parseWhitespace = [&]() -> std::optional<std::string_view> {
      char* c0 = c;
      while (parseChar(' '))
        ;
      return c != c0 ? std::make_optional<std::string_view>(c0, c - c0)
                     : std::nullopt;
    };

    auto parseLetter = [&]() -> std::optional<char> {
      if ((*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z')) {
        char l = *c;
        c++;
        return l;
      }
      return std::nullopt;
    };

    auto parseDigit = [&]() -> std::optional<uint32_t> {
      if (*c >= '0' && *c <= '9') {
        uint32_t d = *c - '0';
        c++;
        return d;
      }
      return std::nullopt;
    };

    auto parseName = [&]() -> std::optional<std::string_view> {
      char* c0 = c;
      if (!parseChar('_') && !parseLetter())
        return std::nullopt;
      while (parseChar('_') || parseLetter() || parseDigit())
        ;
      return std::string_view(c0, c - c0);
    };

    auto parseUint = [&]() -> std::optional<uint32_t> {
      auto d = parseDigit();
      if (!d)
        return std::nullopt;
      uint32_t u = *d;
      while (d = parseDigit())
        u = 10 * u + *d;
      return u;
    };

    auto parseInt = [&]() -> std::optional<int32_t> {
      char* c0 = c;
      int sn = parseChar('-') ? -1 : 1;
      if (auto u = parseUint())
        return sn * *u;
      c = c0;
      return std::nullopt;
    };

    auto parseFloat = [&]() -> std::optional<float> {
      char* c0 = c;
      if (!parseInt())
        return std::nullopt;
      parseChar('.');
      parseUint();
      char* c1 = c;
      parseChar('f');
      parseChar('F');
      return static_cast<float>(std::atof(c0));
    };

    auto parseUintOrVar = [&]() -> std::optional<uint32_t> {
      if (auto u = parseUint())
        return u;
      if (auto name = parseName()) {
        for (const auto& v : m_constUints) {
          if (name->size() == v.name.size() &&
              !strncmp(name->data(), v.name.data(), v.name.size())) {
            return v.value;
          }
        }
      }
      return std::nullopt;
    };

    auto parseIntOrVar = [&]() -> std::optional<int> {
      if (auto i = parseInt())
        return i;
      if (auto name = parseName()) {
        for (const auto& v : m_constInts) {
          if (name->size() == v.name.size() &&
              !strncmp(name->data(), v.name.data(), v.name.size())) {
            return v.value;
          }
        }
      }
      return std::nullopt;
    };

    auto parseFloatOrVar = [&]() -> std::optional<float> {
      if (auto f = parseFloat())
        return f;
      if (auto name = parseName()) {
        for (const auto& v : m_constFloats) {
          if (name->size() == v.name.size() &&
              !strncmp(name->data(), v.name.data(), v.name.size())) {
            return v.value;
          }
        }
      }
      return std::nullopt;
    };

    auto parseInstruction = [&]() -> std::optional<Instr> {
      char* c0 = c;
      if (parseName()) {
        for (uint8_t i = 0; i < I_COUNT; ++i) {
          const char* instr = INSTR_NAMES[i];
          if (strlen(instr) == c - c0 && strcmp(instr, c0)) {
            return (Instr)i;
          }
        }

        c = c0;
      }
      return std::nullopt;
    };

    parseWhitespace();

    // TODO: support comment within line
    if (parseChar('#'))
      continue;

    auto instr = parseInstruction();
    if (!instr)
      continue;

    parseWhitespace();

    auto name = parseName();

    parseWhitespace();
    if (!parseChar(':'))
      continue;

    parseWhitespace();

    switch (*instr) {
    case I_CONST_UINT: {
      if (!name)
        continue;

      auto arg0 = parseUint();
      if (!arg0)
        continue;

      m_constUints.push_back({std::string(*name), *arg0});

      char buf[1024];
      sprintf(
          buf,
          "#define %.*s %u",
          (uint32_t)name->size(),
          name->data(),
          *arg0);
      m_extraDefines.push_back(buf);

      break;
    }
    case I_CONST_INT: {
      if (!name)
        continue;

      auto arg0 = parseInt();
      if (!arg0)
        continue;

      m_constInts.push_back({std::string(*name), *arg0});

      char buf[1024];
      sprintf(
          buf,
          "#define %.*s %d",
          (uint32_t)name->size(),
          name->data(),
          *arg0);
      m_extraDefines.push_back(buf);

      break;
    }
    case I_CONST_FLOAT: {
      if (!name)
        continue;

      auto arg0 = parseFloat();
      if (!arg0)
        continue;

      m_constFloats.push_back({std::string(*name), *arg0});

      char buf[1024];
      sprintf(
          buf,
          "#define %.*s %f",
          (uint32_t)name->size(),
          name->data(),
          *arg0);
      m_extraDefines.push_back(buf);

      break;
    }
    case I_STRUCTURED_BUFFER: {
      if (!name)
        continue;

      auto elemSize = parseUintOrVar();
      if (!elemSize)
        continue;
      parseWhitespace();
      auto elemCount = parseUintOrVar();
      if (!elemCount)
        continue;

      m_buffers.push_back({std::string(*name), *elemSize, *elemCount});
      break;
    }
    case I_COMPUTE_STAGE: {
      if (!name)
        continue;

      auto dispatchSizeX = parseUintOrVar();
      if (!dispatchSizeX)
        continue;
      parseWhitespace();
      auto dispatchSizeY = parseUintOrVar();
      if (!dispatchSizeY)
        continue;
      parseWhitespace();
      auto dispatchSizeZ = parseUintOrVar();
      if (!dispatchSizeZ)
        continue;

      uint32_t computeShaderIdx = 0;
      for (const std::string& s : m_computeShaders) {
        if (s.size() == name->size() &&
            !strncmp(s.data(), name->data(), s.size()))
          break;
        ++computeShaderIdx;
      }
      if (computeShaderIdx == m_computeShaders.size())
        m_computeShaders.push_back(std::string(*name));

      m_taskList.push_back({(uint32_t)m_computeDispatches.size(), TT_COMPUTE});
      m_computeDispatches.push_back(
          {computeShaderIdx, *dispatchSizeX, *dispatchSizeY, *dispatchSizeZ});

      break;
    }
    case I_BARRIER: {
      auto bn = parseName();
      if (!bn)
        continue;

      uint32_t bufferIdx = 0;
      for (const BufferDesc& b : m_buffers) {
        if (bn->size() == b.name.size() &&
            !strncmp(bn->data(), b.name.data(), b.name.size())) {
          m_taskList.push_back({(uint32_t)m_barriers.size(), TT_BARRIER});
          m_barriers.push_back({bufferIdx});
          break;
        }
        ++bufferIdx;
      }
      break;
    }
    case I_DISPLAY_PASS: {
      auto vertShader = parseName();
      if (!vertShader)
        continue;
      parseWhitespace();
      auto pixelShader = parseName();
      if (!pixelShader)
        continue;

      m_taskList.push_back({ (uint32_t)m_displayPasses.size(), TT_DISPLAY });
      m_displayPasses.push_back(
          {std::string(*vertShader), std::string(*pixelShader)});
      break;
    }
    default:
      continue;
    }
  }
}
} // namespace flr