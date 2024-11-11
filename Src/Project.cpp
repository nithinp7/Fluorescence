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
Project::Project(const char* projPath) {
  std::filesystem::path projPath_(projPath);
  std::filesystem::path projName = projPath_.stem();
  std::filesystem::path folder = projPath_.parent_path();

  parseFlrFile(projPath);

  char shaderPath[256];
  sprintf(shaderPath, "%s/%s.glsl", folder.c_str(), projName.c_str());
}

void Project::parseFlrFile(const char* filename) {
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
    if (!parseChar(':'))
      continue;

    parseWhitespace();

    switch (*instr) {
    case I_CONST_UINT: {

      char buf[1024];
      sprintf(buf, "#define %s %u", ) break;
    }
    case I_CONST_FLOAT: {

      break;
    }
    case I_STRUCTURED_BUFFER: {

      break;
    }
    case I_COMPUTE_STAGE: {

      break;
    }
    case I_BARRIER: {

      break;
    }
    case I_DISPLAY_PASS: {

      break;
    }
    default:
      continue;
    }
  }
}
} // namespace flr