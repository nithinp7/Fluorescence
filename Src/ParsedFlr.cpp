
#include "ParsedFlr.h"

#include <Althea/Parser.h>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <utility>
#include <xstring>

using namespace AltheaEngine;

namespace flr {

namespace {
template <typename T, typename V, V T::*Vptr>
std::optional<V> findValueByName(const std::vector<T>& ts, std::string_view n) {
  for (const T& t : ts) {
    if (t.name.size() == n.size() &&
        !strncmp(t.name.data(), n.data(), n.size())) {
      return t.*Vptr;
    }
  }

  return std::nullopt;
}

template <typename T>
std::optional<uint32_t>
findIndexByName(const std::vector<T>& ts, std::string_view n) {
  uint32_t idx = 0;
  for (const T& t : ts) {
    if (t.name.size() == n.size() &&
        !strncmp(t.name.data(), n.data(), n.size())) {
      return idx;
    }
    idx++;
  }

  return std::nullopt;
}

template <size_t N>
std::optional<uint32_t>
findIndexByName(char* const (&names)[N], std::string_view n) {
  for (uint32_t i = 0; i < N; i++) {
    if (strlen(names[i]) == n.size() &&
        !strncmp(names[i], n.data(), n.size())) {
      return i;
    }
  }

  return std::nullopt;
}
} // namespace

ParsedFlr::ParsedFlr(Application& app, const char* flrFileName)
    : m_featureFlags(FF_NONE),
      m_displayImageIdx(-1),
      m_failed(true),
      m_errMsg() {

  m_constUints.push_back({"SCREEN_WIDTH", app.getSwapChainExtent().width});
  m_constUints.push_back({"SCREEN_HEIGHT", app.getSwapChainExtent().height});

  struct File {
    File(const char* filename) : m_filename(filename), m_stream(filename), m_lineNumber(0) {}
    std::string m_filename;
    std::ifstream m_stream;
    uint32_t m_lineNumber;
  };
  std::vector<File> flrFileStack;
  flrFileStack.emplace_back(flrFileName);
  char lineBuf[1024];

  uint32_t uiIdx = 0;

  bool bTaskBlockActive = false;

  auto emitParserError = [&](const char* msg) {
    sprintf(
      m_errMsg,
      "ERROR: %s ON LINE: %u IN FILE: %s\n",
      msg,
      flrFileStack.back().m_lineNumber,
      flrFileStack.back().m_filename.c_str());
    std::cerr << m_errMsg << std::endl;       
    while (!flrFileStack.empty()) {
      flrFileStack.back().m_stream.close();
      flrFileStack.pop_back();
    }
  };

#define PARSER_VERIFY(X, MSG)   \
  if (!(X)) {                   \
    emitParserError(MSG);       \
    return;                     \
  }

  while (!flrFileStack.empty()) {
    if (!flrFileStack.back().m_stream.getline(lineBuf, 1024)) {
      flrFileStack.back().m_stream.close();
      flrFileStack.pop_back();
      continue;
    }
    flrFileStack.back().m_lineNumber++;

    Parser p{lineBuf};

    auto constUintResolver =
        [&](std::string_view n) -> std::optional<uint32_t> {
      return findValueByName<ConstUint, uint32_t, &ConstUint::value>(
          m_constUints,
          n);
    };
    auto constIntResolver = [&](std::string_view n) -> std::optional<int32_t> {
      return findValueByName<ConstInt, int32_t, &ConstInt::value>(
          m_constInts,
          n);
    };
    auto constFloatResolver = [&](std::string_view n) -> std::optional<float> {
      if (auto f = findValueByName<ConstFloat, float, &ConstFloat::value>(
              m_constFloats,
              n))
        return f;
      if (auto u = constUintResolver(n))
        return static_cast<float>(*u);
      if (auto i = constIntResolver(n))
        return static_cast<float>(*i);
      return std::nullopt;
    };

    auto parseUintOrVar = [&]() -> std::optional<uint32_t> {
      return p.parseLiteralOrRef<uint32_t>(constUintResolver);
    };
    auto parseIntOrVar = [&]() -> std::optional<int32_t> {
      return p.parseLiteralOrRef<int32_t>(constIntResolver);
    };
    auto parseFloatOrVar = [&]() -> std::optional<float> {
      return p.parseLiteralOrRef<float>(constFloatResolver);
    };

    auto parseInstruction = [&]() -> std::optional<Instr> {
      return p.parseRef<Instr>([&](std::string_view n) -> std::optional<Instr> {
        if (auto idx = findIndexByName(INSTR_NAMES, n))
          return (Instr)*idx;
        return std::nullopt;
      });
    };

    auto parseStructRef = [&]() -> std::optional<uint32_t> {
      return p.parseRef<uint32_t>(
          [&](std::string_view n) -> std::optional<uint32_t> {
            return findIndexByName(m_structDefs, n);
          });
    };

    auto findVkFormat =
        [&](std::string_view glslFormat) -> std::optional<VkFormat> {
      for (const auto& entry : IMAGE_FORMAT_TABLE) {
        if (glslFormat.size() == strlen(entry.glslFormatName) &&
            !strncmp(
                glslFormat.data(),
                entry.glslFormatName,
                glslFormat.size()))
          return entry.vkFormat;
      }
      return std::nullopt;
    };

    auto bindAttachment = [&](std::string_view aliasName,
                              uint32_t imageIdx,
                              bool bLoad,
                              bool bStore) {
      m_renderPasses.back().attachments.push_back(
          {std::string(aliasName), (int)imageIdx, bLoad, bStore});
      m_renderPasses.back().width = m_images[imageIdx].createOptions.width;
      m_renderPasses.back().height = m_images[imageIdx].createOptions.height;

      bool bIsDepth = (m_images[imageIdx].createOptions.aspectMask &
                       VK_IMAGE_ASPECT_DEPTH_BIT) != 0;
      if (bIsDepth) {
        m_images[imageIdx].createOptions.usage |=
            VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
      } else {
        m_images[imageIdx].createOptions.usage |=
            VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
      }
    };

    auto pushTask = [&](uint32_t idx, TaskType type) {
      if (bTaskBlockActive)
        m_taskBlocks.back().tasks.push_back(Task{ idx, type });
      else
        m_taskList.push_back(Task{ idx, type });
    };

    p.parseWhitespace();

    // TODO: support comment within line
    if (p.parseChar('#') || p.parseChar(0))
      continue;

    auto instr = parseInstruction();
    PARSER_VERIFY(instr, "Could not parse instruction!");

    p.parseWhitespace();

    auto name = p.parseName();
    p.parseWhitespace();

    std::optional<uint32_t> arrayCount = std::nullopt;
    if (p.parseChar('(')) {
      p.parseWhitespace();
      arrayCount = parseUintOrVar();
      PARSER_VERIFY(arrayCount, "Encountered malformed array syntax, could not read array elem count");
      p.parseWhitespace();
      auto closingBracket = p.parseChar(')');
      PARSER_VERIFY(closingBracket, "Encountered malformed array syntax, expecting closing parenthesis");
      p.parseWhitespace();
    }
    p.parseChar(':');
    p.parseWhitespace();

    switch (*instr) {
    case I_CONST_UINT: {
      PARSER_VERIFY(name, "Could not parse name for const uint.");

      auto arg0 = p.parseExpression<uint32_t>(constUintResolver);
      PARSER_VERIFY(arg0, "Could not parse const uint.");

      m_constUints.push_back({std::string(*name), *arg0});

      break;
    }
    case I_CONST_INT: {
      PARSER_VERIFY(name, "Could not parse name for const int.");

      auto arg0 = p.parseExpression<int32_t>(constIntResolver);
      PARSER_VERIFY(arg0, "Could not parse const int.");

      m_constInts.push_back({std::string(*name), *arg0});

      break;
    }
    case I_CONST_FLOAT: {
      PARSER_VERIFY(name, "Could not parse name for const float.");

      auto arg0 = p.parseExpression<float>(constFloatResolver);
      PARSER_VERIFY(arg0, "Could not parse const float.");

      m_constFloats.push_back({std::string(*name), *arg0});

      break;
    }
    case I_SLIDER_UINT: {
      PARSER_VERIFY(name, "Could not parse name for uint slider.");

      auto value = p.parseUint();
      PARSER_VERIFY(value, "Could not parse default value for uint slider.");
      p.parseWhitespace();

      auto min = p.parseUint();
      PARSER_VERIFY(value, "Could not parse min value for uint slider.");
      p.parseWhitespace();

      auto max = p.parseUint();
      PARSER_VERIFY(value, "Could not parse max value for uint slider.");

      m_uiElements.push_back({ UET_SLIDER_UINT, (uint32_t)m_sliderUints.size() });
      m_sliderUints.push_back(
          {std::string(*name), *value, *min, *max, uiIdx++, nullptr});
      break;
    }
    case I_SLIDER_INT: {
      PARSER_VERIFY(name, "Could not parse name for int slider.");

      auto value = p.parseInt();
      PARSER_VERIFY(value, "Could not parse default value for int slider.");
      p.parseWhitespace();

      auto min = p.parseInt();
      PARSER_VERIFY(value, "Could not parse min value for int slider.");
      p.parseWhitespace();

      auto max = p.parseInt();
      PARSER_VERIFY(value, "Could not parse max value for int slider.");

      m_uiElements.push_back({ UET_SLIDER_INT, (uint32_t)m_sliderInts.size() });
      m_sliderInts.push_back(
          {std::string(*name), *value, *min, *max, uiIdx++, nullptr});
      break;
    }
    case I_SLIDER_FLOAT: {
      PARSER_VERIFY(name, "Could not parse name for float slider.");

      auto value = p.parseFloat();
      PARSER_VERIFY(value, "Could not parse default value for float slider.");
      p.parseWhitespace();

      auto min = p.parseFloat();
      PARSER_VERIFY(min, "Could not parse min value for float slider.");
      p.parseWhitespace();

      auto max = p.parseFloat();
      PARSER_VERIFY(max, "Could not parse max value for float slider.");

      m_uiElements.push_back({ UET_SLIDER_FLOAT, (uint32_t)m_sliderFloats.size() });
      m_sliderFloats.push_back(
          {std::string(*name), *value, *min, *max, uiIdx++, nullptr});
      break;
    }
    case I_COLOR_PICKER: {
      PARSER_VERIFY(name, "Could not parse name for color_picker.");

      auto r = p.parseFloat();
      PARSER_VERIFY(
          r,
          "Could not parse default color component R for color_picker.");
      p.parseWhitespace();

      auto g = p.parseFloat();
      PARSER_VERIFY(
          g,
          "Could not parse default color component G for color_picker.");
      p.parseWhitespace();

      auto b = p.parseFloat();
      PARSER_VERIFY(
          b,
          "Could not parse default color component B for color_picker.");
      p.parseWhitespace();

      auto a = p.parseFloat();
      PARSER_VERIFY(
          a,
          "Could not parse default color component A for color_picker.");

      m_uiElements.push_back({ UET_COLOR_PICKER, (uint32_t)m_colorPickers.size() });
      m_colorPickers.push_back(
          {std::string(*name), glm::vec4(*r, *g, *b, *a), uiIdx++, nullptr});

      break;
    }
    case I_CHECKBOX: {
      PARSER_VERIFY(name, "Could not parse name for checkbox.");

      auto value = p.parseBool();
      PARSER_VERIFY(value, "Could not parse default value for checkbox.");

      m_uiElements.push_back({ UET_CHECKBOX, (uint32_t)m_checkboxes.size() });
      m_checkboxes.push_back({std::string(*name), *value, uiIdx++, nullptr});

      break;
    }
    case I_SAVE_IMAGE_BUTTON: {
      auto imageName = p.parseName();
      PARSER_VERIFY(
          imageName,
          "Could not parse image name in save_image_button instruction.");
      auto imageIdx = findIndexByName(m_images, *imageName);
      PARSER_VERIFY(
          imageIdx,
          "Could not find specified image in save_image_button "
          "instruction.");

      VkFormat format = m_images[*imageIdx].createOptions.format;
      PARSER_VERIFY(
          format == VK_FORMAT_R8G8B8A8_UNORM,
          "Saving images is only supported for VK_FORMAT_R8G8B8A8_UNORM "
          "currently.");
      m_images[*imageIdx].createOptions.usage |=
          VK_IMAGE_USAGE_TRANSFER_SRC_BIT;

      m_uiElements.push_back({ UET_SAVE_IMAGE_BUTTON, (uint32_t)m_saveImageButtons.size() });
      m_saveImageButtons.push_back({*imageIdx, uiIdx++});

      break;
    }
    case I_SEPARATOR: {
      m_uiElements.push_back({ UET_SEPARATOR, ~0ul });
      break;
    }
    case I_DROPDOWN_START: {
      PARSER_VERIFY(name, "Could not parse ui dropdown name.");
      m_uiElements.push_back({ UET_DROPDOWN_START, (uint32_t)m_genericNamedElements.size() });
      m_genericNamedElements.push_back({ std::string(*name) });
      break;
    }
    case I_DROPDOWN_END: {
      m_uiElements.push_back({ UET_DROPDOWN_END, ~0ul });
      break;
    }
    case I_STRUCT: {
      PARSER_VERIFY(name, "Could not parse struct name.");

      std::string nameStr(*name);

      char body[1024] = {0};
      uint32_t offs = 0;
      uint32_t structStartLine = flrFileStack.back().m_lineNumber;
      while (true) {
        bool breakOuter = false;
        while (*p.c) {
          if (*p.c == '}') {
            ++p.c;
            breakOuter = true;
            break;
          }
          ++p.c;
        }

        offs += sprintf(body + offs, "%s", lineBuf);

        if (breakOuter)
          break;

        *(body + offs) = '\n';
        offs++;

        if (!flrFileStack.back().m_stream.getline(lineBuf, 1024)) {
          flrFileStack.back().m_lineNumber = structStartLine; // reset line to start of struct
          PARSER_VERIFY(
              false,
              "Found unterminated struct declaration, expected \'}\'.");
        }
        flrFileStack.back().m_lineNumber++;
        p.c = lineBuf;
      }

      m_structDefs.push_back({nameStr, std::string(body), 0});

      break;
    }
    case I_STRUCT_SIZE: {
      auto structSize = parseUintOrVar();
      PARSER_VERIFY(structSize, "Could not parse struct-size, expecting uint.");

      PARSER_VERIFY(
          m_structDefs.size() > 0,
          "Found struct-size without preceding struct declaration.");
      m_structDefs.back().size = *structSize;
      break;
    }
    case I_STRUCTURED_BUFFER: {
      PARSER_VERIFY(name, "Could not parse structured-buffer name.");

      auto structIdx = parseStructRef();
      PARSER_VERIFY(
          structIdx,
          "Could not find struct referenced in structured-buffer declaration.");

      p.parseWhitespace();
      auto elemCount = parseUintOrVar();
      PARSER_VERIFY(
          elemCount,
          "Could not parse element count in structured-buffer declaration.");

      m_buffers.push_back({std::string(*name), *structIdx, *elemCount, arrayCount ? *arrayCount : 1, false});
      arrayCount = std::nullopt;

      break;
    }
    case I_ENABLE_CPU_ACCESS: {
      PARSER_VERIFY(m_buffers.size(), "Instruction enable_cpu_access must be preceded by structured buffer declaration.");
      m_buffers.back().bCpuVisible = true;
      break;
    }
    case I_COMPUTE_SHADER: {
      PARSER_VERIFY(name, "Could not parse compute-shader name.");

      auto groupSizeX = parseUintOrVar();
      PARSER_VERIFY(
          groupSizeX,
          "Could not parse groupSizeX in compute-shader declaration.");

      p.parseWhitespace();
      auto groupSizeY = parseUintOrVar();
      PARSER_VERIFY(
          groupSizeY,
          "Could not parse groupSizeY in compute-shader declaration.");

      p.parseWhitespace();
      auto groupSizeZ = parseUintOrVar();
      PARSER_VERIFY(
          groupSizeZ,
          "Could not parse groupSizeZ in compute-shader declaration.");

      m_computeShaders.push_back(
          {std::string(*name), *groupSizeX, *groupSizeY, *groupSizeZ});

      break;
    }
    case I_COMPUTE_DISPATCH: {
      auto compShader = p.parseName();
      PARSER_VERIFY(
          compShader,
          "Could not parse compute-shader name in compute-dispatch "
          "declaration.");

      p.parseWhitespace();
      auto dispatchSizeX = parseUintOrVar();
      PARSER_VERIFY(
          dispatchSizeX,
          "Could not parse dispatchSizeX in compute-dispatch declaration.");
      p.parseWhitespace();
      auto dispatchSizeY = parseUintOrVar();
      PARSER_VERIFY(
          dispatchSizeY,
          "Could not parse dispatchSizeY in compute-dispatch declaration.");
      p.parseWhitespace();
      auto dispatchSizeZ = parseUintOrVar();
      PARSER_VERIFY(
          dispatchSizeZ,
          "Could not parse dispatchSizeZ in compute-dispatch declaration.");

      uint32_t computeShaderIdx = 0;
      for (const auto& c : m_computeShaders) {
        if (c.name.size() == compShader->size() &&
            !strncmp(c.name.data(), compShader->data(), c.name.size()))
          break;
        ++computeShaderIdx;
      }
      PARSER_VERIFY(
          computeShaderIdx < m_computeShaders.size(),
          "Could not find referenced compute-shader referenced in "
          "compute-dispatch declaration.");

      pushTask((uint32_t)m_computeDispatches.size(), TT_COMPUTE);
      m_computeDispatches.push_back(
          {computeShaderIdx, *dispatchSizeX, *dispatchSizeY, *dispatchSizeZ});

      break;
    }
    case I_BARRIER: {
      auto bn = p.parseName();
      PARSER_VERIFY(bn, "Expected at least one buffer in barrier declaration.");

      std::vector<uint32_t> buffers;

      while (bn) {
        uint32_t bufferIdx = 0;
        for (const BufferDesc& b : m_buffers) {
          if (bn->size() == b.name.size() &&
              !strncmp(bn->data(), b.name.data(), b.name.size())) {
            break;
          }
          ++bufferIdx;
        }

        PARSER_VERIFY(
            bufferIdx < m_buffers.size(),
            "Could not find referenced buffer in barrier declaration.");

        buffers.push_back(bufferIdx);

        p.parseWhitespace();
        bn = p.parseName();
      }

      pushTask((uint32_t)m_barriers.size(), TT_BARRIER);
      m_barriers.emplace_back().buffers = std::move(buffers);

      break;
    }
    case I_DISPLAY_IMAGE: {
      PARSER_VERIFY(
          m_displayImageIdx == -1,
          "Only one display_image is allowed.");

      PARSER_VERIFY(name, "Could not parse display_image name.");

      m_displayImageIdx = m_images.size();

      ImageDesc& desc = m_images.emplace_back();
      desc.name = std::string(*name);
      desc.format = "";
      desc.createOptions = ImageOptions{};
      desc.createOptions.width = app.getSwapChainExtent().width;
      desc.createOptions.height = app.getSwapChainExtent().height;
      desc.createOptions.format = app.getSwapChainImageFormat();
      desc.createOptions.usage =
          VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
      desc.createOptions.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;

      break;
    }
    case I_RENDER_PASS: {
      PARSER_VERIFY(name, "Could not parse render-pass name.");

      pushTask((uint32_t)m_renderPasses.size(), TT_RENDER);
      m_renderPasses.push_back({std::string(*name), {}, {}, -1, -1});

      if (auto width = parseUintOrVar()) {
        m_renderPasses.back().width = *width;
        p.parseWhitespace();
        auto height = parseUintOrVar();
        PARSER_VERIFY(height, "Could not parse render-pass target height.");
        m_renderPasses.back().height = *height;
      }

      break;
    }
    case I_DISABLE_DEPTH: {
      PARSER_VERIFY(
          m_renderPasses.size() > 0,
          "Expected render-pass or display-pass declaration to precede "
          "disable-depth.");
      PARSER_VERIFY(
          m_renderPasses.back().draws.size() > 0,
          "Expected draw-call to precede disable-depth");
      m_renderPasses.back().draws.back().bDisableDepth = true;
      break;
    }
    case I_LOAD_ATTACHMENTS: {
      PARSER_VERIFY(
          m_renderPasses.size() > 0,
          "Expected render-pass or display-pass declaratino to precede "
          "load_attachments instruction.");

      do {
        auto aliasName = p.parseName();
        PARSER_VERIFY(aliasName, "Could not parse attachment alias name.");
        PARSER_VERIFY(
            p.parseChar('='),
            "Attachments must be specified as <alias-name>=<image-name>.")

        auto imageName = p.parseName();
        PARSER_VERIFY(
            imageName,
            "Could not parse image name in load_attachments instruction.");
        auto imageIdx = findIndexByName(m_images, *imageName);
        PARSER_VERIFY(
            imageIdx,
            "Could not find specified image in load_attachments "
            "instruction.");
        p.parseWhitespace();

        bindAttachment(*aliasName, *imageIdx, true, false);
      } while (*p.c != 0);

      break;
    }
    case I_STORE_ATTACHMENTS: {
      PARSER_VERIFY(
          m_renderPasses.size() > 0,
          "Expected render-pass or display-pass declaratino to precede "
          "store_attachments instruction.");

      do {
        auto aliasName = p.parseName();
        PARSER_VERIFY(aliasName, "Could not parse attachment alias name.");
        PARSER_VERIFY(
            p.parseChar('='),
            "Attachments must be specified as <alias-name>=<image-name>.")

        auto imageName = p.parseName();
        PARSER_VERIFY(
            imageName,
            "Could not parse image name in store_attachments "
            "instruction.");
        auto imageIdx = findIndexByName(m_images, *imageName);
        PARSER_VERIFY(
            imageIdx,
            "Could not find specified image in store_attachments "
            "instruction.");
        p.parseWhitespace();

        bindAttachment(*aliasName, *imageIdx, false, true);
      } while (*p.c != 0);

      break;
    }
    case I_LOADSTORE_ATTACHMENTS: {
      PARSER_VERIFY(
          m_renderPasses.size() > 0,
          "Expected render-pass or display-pass declaratino to precede "
          "loadstore_attachments instruction.");

      do {
        auto aliasName = p.parseName();
        PARSER_VERIFY(aliasName, "Could not parse attachment alias name.");
        PARSER_VERIFY(
            p.parseChar('='),
            "Attachments must be specified as <alias-name>=<image-name>.")

        auto imageName = p.parseName();
        PARSER_VERIFY(
            imageName,
            "Could not parse image name in loadstore_attachments "
            "instruction.");
        auto imageIdx = findIndexByName(m_images, *imageName);
        PARSER_VERIFY(
            imageIdx,
            "Could not find specified image in loadstore_attachments "
            "instruction.");
        p.parseWhitespace();

        bindAttachment(*aliasName, *imageIdx, true, true);
      } while (*p.c != 0);

      break;
    }
    case I_LOAD_DEPTH: {
      PARSER_VERIFY(
          m_renderPasses.size() > 0,
          "Expected render-pass or display-pass declaratino to precede "
          "load_depth instruction.");

      auto imageName = p.parseName();
      PARSER_VERIFY(
          imageName,
          "Could not parse image name in load_depth "
          "instruction.");
      auto imageIdx = findIndexByName(m_images, *imageName);
      PARSER_VERIFY(
          imageIdx,
          "Could not find specified image in load_depth "
          "instruction.");
      PARSER_VERIFY(
          (m_images[*imageIdx].createOptions.aspectMask &
           VK_IMAGE_ASPECT_DEPTH_BIT) != 0,
          "Specified image in load_depth instruction is not a depth image.");

      bindAttachment("", *imageIdx, true, false);

      break;
    }
    case I_STORE_DEPTH: {
      PARSER_VERIFY(
          m_renderPasses.size() > 0,
          "Expected render-pass or display-pass declaratino to precede "
          "store_depth instruction.");

      auto imageName = p.parseName();
      PARSER_VERIFY(
          imageName,
          "Could not parse image name in store_depth "
          "instruction.");
      auto imageIdx = findIndexByName(m_images, *imageName);
      PARSER_VERIFY(
          imageIdx,
          "Could not find specified image in store_depth "
          "instruction.");
      PARSER_VERIFY(
          (m_images[*imageIdx].createOptions.aspectMask &
           VK_IMAGE_ASPECT_DEPTH_BIT) != 0,
          "Specified image in store_depth instruction is not a depth image.");

      bindAttachment("", *imageIdx, false, true);

      break;
    }
    case I_LOADSTORE_DEPTH: {
      PARSER_VERIFY(
          m_renderPasses.size() > 0,
          "Expected render-pass or display-pass declaratino to precede "
          "loadstore_depth instruction.");

      auto imageName = p.parseName();
      PARSER_VERIFY(
          imageName,
          "Could not parse image name in loadstore_depth "
          "instruction.");
      auto imageIdx = findIndexByName(m_images, *imageName);
      PARSER_VERIFY(
          imageIdx,
          "Could not find specified image in loadstore_depth "
          "instruction.");
      PARSER_VERIFY(
          (m_images[*imageIdx].createOptions.aspectMask &
           VK_IMAGE_ASPECT_DEPTH_BIT) != 0,
          "Specified image in loadstore_depth instruction is not a depth "
          "image.");

      bindAttachment("", *imageIdx, true, true);

      break;
    }
    case I_DRAW: {
      // TODO: have re-usable subpasses that can be drawn multiple times?
      PARSER_VERIFY(
          m_renderPasses.size(),
          "Expected render-pass or display-pass declaration to precede "
          "draw-call.");

      auto vertShader = p.parseName();
      PARSER_VERIFY(
          vertShader,
          "Could not parse vertex shader name in draw-call declaration.");
      p.parseWhitespace();
      auto pixelShader = p.parseName();
      PARSER_VERIFY(
          pixelShader,
          "Could not parse pixel shader name in draw-call declaration.");
      p.parseWhitespace();
      auto vertexCount = parseUintOrVar();
      PARSER_VERIFY(
          vertexCount,
          "Could not parse vertexCount in draw-call declaration.");
      p.parseWhitespace();
      auto instanceCount = parseUintOrVar();
      PARSER_VERIFY(
          instanceCount,
          "Could not parse instanceCount in draw-call declaration.");

      uint32_t renderPassIdx = m_renderPasses.size() - 1;
      m_renderPasses.back().draws.push_back(
          {std::string(*vertShader),
           std::string(*pixelShader),
           *vertexCount,
           *instanceCount,
           -1,
           false});
      break;
    }
    case I_DRAW_OBJ: {

      // TODO: have re-usable subpasses that can be drawn multiple times?
      PARSER_VERIFY(
          m_renderPasses.size(),
          "Expected render-pass or display-pass declaration to precede "
          "draw-call.");

      auto objName = p.parseName();
      PARSER_VERIFY(
          objName,
          "Could not parse obj name in draw-call declaration.");
      p.parseWhitespace();

      auto idx = findIndexByName(m_objModels, *objName);
      PARSER_VERIFY(
          idx,
          "Could not find referenced obj mesh specified in draw-call "
          "declaration.");

      auto vertShader = p.parseName();
      PARSER_VERIFY(
          vertShader,
          "Could not parse vertex shader name in draw-call declaration.");
      p.parseWhitespace();
      auto pixelShader = p.parseName();
      PARSER_VERIFY(
          pixelShader,
          "Could not parse pixel shader name in draw-call declaration.");

      uint32_t renderPassIdx = m_renderPasses.size() - 1;
      m_renderPasses.back().draws.push_back(
          {std::string(*vertShader),
           std::string(*pixelShader),
           0,
           1,
           (int)*idx,
           -1,
           false});
      break;
    }
    case I_VERTEX_OUTPUT: {
      PARSER_VERIFY(
          m_renderPasses.size() > 0,
          "vertex_output declaration must follow draw-call.");
      PARSER_VERIFY(
          m_renderPasses.back().draws.size() > 0,
          "vertex_output declaration must follow draw-call.");

      auto structIdx = parseStructRef();
      PARSER_VERIFY(
          structIdx,
          "Could not parse struct reference in vertex_output declaration.");

      m_renderPasses.back().draws.back().vertexOutputStructIdx = *structIdx;

      break;
    }
    case I_FEATURE: {
      auto featureName = p.parseName();
      PARSER_VERIFY(featureName, "Could not parse feature name.");

      auto featureIdx = findIndexByName(FEATURE_FLAG_NAMES, *featureName);
      PARSER_VERIFY(featureIdx, "Invalid feature flag specified.");

      m_featureFlags |= (FeatureFlag)(1 << *featureIdx);

      break;
    }
    case I_IMAGE: {
      PARSER_VERIFY(name, "Could not parse image name.");

      auto width = parseUintOrVar();
      PARSER_VERIFY(width, "Could not parse image width.");

      p.parseWhitespace();

      auto height = parseUintOrVar();
      PARSER_VERIFY(height, "Could not parse image height.");

      p.parseWhitespace();
      auto format = p.parseName();
      PARSER_VERIFY(
          format,
          "Could not parse format string for image declaration.");

      auto vkFormat = findVkFormat(*format);
      PARSER_VERIFY(
          vkFormat,
          "Could not find vulkan format for specified glsl format in image "
          "declaration.");

      ImageDesc& desc = m_images.emplace_back();
      desc.name = std::string(*name);
      desc.format = std::string(*format);
      desc.createOptions = ImageOptions{};
      desc.createOptions.width = *width;
      desc.createOptions.height = *height;
      desc.createOptions.format = *vkFormat;
      desc.createOptions.usage = VK_IMAGE_USAGE_STORAGE_BIT;

      break;
    }
    case I_DEPTH_IMAGE: {
      PARSER_VERIFY(name, "Could not parse depth image name.");

      auto width = parseUintOrVar();
      PARSER_VERIFY(width, "Could not parse image width.");

      p.parseWhitespace();

      auto height = parseUintOrVar();
      PARSER_VERIFY(height, "Could not parse image height.");

      ImageDesc& desc = m_images.emplace_back();
      desc.name = std::string(*name);
      desc.format = ""; // depth images can't be sampled as images so they don't
                        // have a format string
      desc.createOptions = ImageOptions{};
      desc.createOptions.width = *width;
      desc.createOptions.height = *height;
      desc.createOptions.format = app.getDepthImageFormat();
      desc.createOptions.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
      desc.createOptions.aspectMask =
          VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT;

      break;
    }
    case I_TEXTURE_ALIAS: {
      PARSER_VERIFY(name, "Could not parse texture name.");

      PARSER_VERIFY(
          m_images.size() > 0,
          "Could not find preceding image declaration before texture_alias "
          "declaration.");

      int imageIdx = m_images.size() - 1;
      m_images[imageIdx].createOptions.usage |= VK_IMAGE_USAGE_SAMPLED_BIT;
      m_textures.push_back({std::string(*name), imageIdx, -1});

      break;
    }
    case I_TEXTURE_FILE: {
      PARSER_VERIFY(name, "Could not parse texture name.");

      auto path = p.parseStringLiteral();
      PARSER_VERIFY(path, "Could not parse texture file path.");

      p.parseWhitespace();

      // TODO: formalize options here
      bool bSrgb = false;
      bool bHdr = false;
      if (auto option = p.parseName()) {
        if (!option->compare("srgb")) {
          bSrgb = true;
        }
        else if (!option->compare("hdr")) {
          bHdr = true;
        }
        else {
          PARSER_VERIFY(false,
            "Unknown option provided with texture_file instruction.");
        }
      }

      std::string pathStr(*path);
      PARSER_VERIFY(
          Utilities::checkFileExists(pathStr),
          "Could not find specified texture file.");

      int texFileIdx = m_textureFiles.size();
      auto& texFile = m_textureFiles.emplace_back();
      if (bHdr) {
        Utilities::loadHdri(pathStr, texFile.loadedImage);
      }
      else {
        Utilities::loadImage(pathStr, texFile.loadedImage);
      }
      PARSER_VERIFY(
          texFile.loadedImage.data.size() > 0,
          "Could not load specified texture file.");

      texFile.createOptions = ImageOptions{};
      texFile.createOptions.width = texFile.loadedImage.width;
      texFile.createOptions.height = texFile.loadedImage.height;
      if (bSrgb) {
        texFile.createOptions.format = VK_FORMAT_R8G8B8A8_SRGB;
        assert(texFile.loadedImage.bytesPerChannel == 1);
      }
      else if (bHdr) {
        texFile.createOptions.format = VK_FORMAT_R32G32B32A32_SFLOAT;
        assert(texFile.loadedImage.bytesPerChannel == 4);
      }

      assert(texFile.loadedImage.channels == 4);

      m_textures.push_back({std::string(*name), -1, texFileIdx});

      break;
    }
    case I_TRANSITION: {
      auto imageName = p.parseName();
      PARSER_VERIFY(
          imageName,
          "Could not parse image name for transition_layout declaration.");

      auto imageIdx = findIndexByName(m_images, *imageName);
      PARSER_VERIFY(
          imageIdx,
          "Could not find specified image name in transition_layout "
          "declaration.");

      p.parseWhitespace();

      auto mode = p.parseName();
      PARSER_VERIFY(
          mode,
          "Could not parse transition mode specified in transition_layout "
          "declaration.");
      auto modeIdx = findIndexByName(TRANSITION_TARGET_NAMES, *mode);
      PARSER_VERIFY(
          modeIdx,
          "Invalid transition target specified in transition_layout "
          "declaration.");

      pushTask((uint32_t)m_transitions.size(), TT_TRANSITION);
      m_transitions.push_back({*imageIdx, (LayoutTransitionTarget)*modeIdx});

      break;
    };
    case I_OBJ_MODEL: {
      PARSER_VERIFY(name, "Could not parse obj model name.");

      auto path = p.parseStringLiteral();
      PARSER_VERIFY(path, "Could not parse obj model path");

      m_objModels.push_back({std::string(*name), std::string(*path)});

      break;
    };
    case I_TASK_BLOCK_START: {
      PARSER_VERIFY(name, "Could not parse task-block name.");
      PARSER_VERIFY(!bTaskBlockActive, "Attempting to start a new task-block without ending previous task-block.");
      bTaskBlockActive = true;
      m_taskBlocks.push_back({ std::string(*name), {} });

      break;
    };
    case I_TASK_BLOCK_END: {
      PARSER_VERIFY(bTaskBlockActive, "Encountered task_block_end without corresponding task_block_start.");
      bTaskBlockActive = false;
      break;
    };
    case I_INCLUDE: {
      auto pathLiteral = p.parseStringLiteral();
      PARSER_VERIFY(pathLiteral, "Could not parse included flr header path");
      // try absolute path
      std::string path(*pathLiteral);
      if (!Utilities::checkFileExists(path)) {
        // try local relative path
        std::filesystem::path fpath(flrFileStack.back().m_filename);
        fpath.replace_filename(*pathLiteral);
        path = fpath.u8string(); 
      }

      if (!Utilities::checkFileExists(path)) {
        // try in flr shaders folder
        std::filesystem::path fpath = std::filesystem::path(GProjectDirectory + "/Shaders/")
          .replace_filename(*pathLiteral);
        path = fpath.u8string();
      }

      flrFileStack.emplace_back(path.c_str());
      if (!flrFileStack.back().m_stream.is_open()) {
        flrFileStack.pop_back();
        PARSER_VERIFY(false, "Could not open included flr header file");
      }

      break;
    };
    default:
      PARSER_VERIFY(false, "Encountered unknown instruction.");
      continue;
    }

    // the instruction needs to consume the arrayCount and set it to nullopt, if it is valid
    PARSER_VERIFY(!arrayCount, "Array syntax not valid for this instruction.");
  }

  // post-process
  PARSER_VERIFY(m_displayImageIdx >= 0, "Must specify a display_image");

  // fill in missing depth resources for any passes that are missing depth and
  // require it
  for (auto& pass : m_renderPasses) {
    bool bNeedDepth = false;
    for (const auto& draw : pass.draws) {
      if (!draw.bDisableDepth) {
        bNeedDepth = true;
        break;
      }
    }
    if (!bNeedDepth)
      break;
    bool bHasDepth = false;
    for (const auto& a : pass.attachments) {
      const auto& imageDesc = m_images[a.imageIdx];
      if ((imageDesc.createOptions.usage &
           VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) != 0) {
        bHasDepth = true;
        break;
      }
    }
    if (bHasDepth)
      break;

    AttachmentRef& ref = pass.attachments.emplace_back();
    ref.imageIdx = m_images.size();
    ref.bLoad = false;
    ref.bStore = false;

    ImageDesc& image = m_images.emplace_back();

    // depth images can't be sampled as images
    image.name = "";
    image.format = "";
    image.createOptions = ImageOptions{};
    image.createOptions.width = pass.width;
    image.createOptions.height = pass.height;
    image.createOptions.format = app.getDepthImageFormat();
    image.createOptions.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    image.createOptions.aspectMask =
        VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT;
  }

#undef PARSER_VERIFY

  m_failed = false;
}
} // namespace flr