#include "Project.h"

#include <Althea/BufferUtilities.h>
#include <Althea/DescriptorSet.h>
#include <Althea/ResourcesAssignment.h>
#include <Althea/SingleTimeCommandBuffer.h>
#include <stdio.h>
#include <string.h>

#include <filesystem>
#include <fstream>
#include <optional>
#include <utility>
#include <xstring>

using namespace AltheaEngine;

namespace flr {
Project::Project(
    Application& app,
    GlobalHeap& heap,
    const TransientUniforms<FlrUniforms>& flrUniforms,
    const char* projPath)
    : m_parsed(projPath), m_displayPassIdx(0) {
  // TODO: split out resource creation vs code generation

  std::filesystem::path projPath_(projPath);
  std::filesystem::path projName = projPath_.stem();
  std::filesystem::path folder = projPath_.parent_path();

  std::filesystem::path shaderFileName = projPath_;
  shaderFileName.replace_extension(".glsl");

  SingleTimeCommandBuffer commandBuffer(app);

  m_buffers.reserve(m_parsed.m_buffers.size());
  for (const ParsedFlr::BufferDesc& desc : m_parsed.m_buffers) {
    const ParsedFlr::StructDef& structdef =
        m_parsed.m_structDefs[desc.structIdx];

    VmaAllocationCreateInfo allocInfo{};
    allocInfo.usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE;

    m_buffers.push_back(BufferUtilities::createBuffer(
        app,
        structdef.size * desc.elemCount,
        VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        allocInfo));
  }

  DescriptorSetLayoutBuilder dsBuilder{};
  dsBuilder.addUniformBufferBinding();
  for (const BufferAllocation& b : m_buffers) {
    dsBuilder.addStorageBufferBinding();
  }

  m_descriptorSets = PerFrameResources(app, dsBuilder);

  const uint32_t GEN_CODE_BUF_SIZE = 10000;
  char* autoGenCode = new char[GEN_CODE_BUF_SIZE];
  size_t autoGenCodeSize = 0;
  memset(autoGenCode, 0, GEN_CODE_BUF_SIZE);

#define CODE_APPEND(...)                                                       \
  autoGenCodeSize += sprintf(autoGenCode + autoGenCodeSize, __VA_ARGS__)

  // glsl version / common includes
  CODE_APPEND("#version 460 core\n\n");

  // struct declarations
  for (const auto& s : m_parsed.m_structDefs) {
    CODE_APPEND("%s;\n\n", s.body.c_str());
  }

  // resource declarations
  uint32_t slot = 0;
  {
    ResourcesAssignment assign = m_descriptorSets.assign();
    assign.bindTransientUniforms(flrUniforms);
    slot++;

    for (int i = 0; i < m_buffers.size(); ++i) {
      const auto& parsedBuf = m_parsed.m_buffers[i];
      const auto& structdef = m_parsed.m_structDefs[parsedBuf.structIdx];
      const auto& buf = m_buffers[i];

      assign.bindStorageBuffer(
          buf,
          structdef.size * parsedBuf.elemCount,
          false);
      CODE_APPEND(
          "layout(set=1,binding=%u) buffer BUFFER_%s {  %s %s[]; };\n",
          slot++,
          parsedBuf.name.c_str(),
          structdef.name.c_str(),
          parsedBuf.name.c_str());
    }
  }

  // constant declarations
  for (const auto& c : m_parsed.m_constInts)
    CODE_APPEND("#define %s %d\n", c.name.c_str(), c.value);
  for (const auto& c : m_parsed.m_constUints)
    CODE_APPEND("#define %s %u\n", c.name.c_str(), c.value);
  for (const auto& c : m_parsed.m_constFloats)
    CODE_APPEND("#define %s %f\n", c.name.c_str(), c.value);
  CODE_APPEND("\n");

  // includes
  CODE_APPEND("#include <Fluorescence.glsl>\n");
  std::string userShaderName = shaderFileName.filename().string();
  CODE_APPEND("#include \"%s\"\n\n", userShaderName.c_str());

  // auto-gen compute shader block
  {
    CODE_APPEND("#ifdef IS_COMP_SHADER\n");
    for (const auto& c : m_parsed.m_computeShaders) {
      CODE_APPEND("#ifdef _ENTRY_POINT_%s\n", c.name.c_str());
      CODE_APPEND(
          "layout(local_size_x = %u, local_size_y = %u, local_size_z = %u) "
          "in;\n",
          c.groupSizeX,
          c.groupSizeY,
          c.groupSizeZ);
      CODE_APPEND("void main() { %s(); }\n", c.name.c_str());
      CODE_APPEND("#endif // _ENTRY_POINT_%s\n", c.name.c_str());
    }
    CODE_APPEND("#endif // IS_COMP_SHADER\n");
  }

  // auto-gen vertex shader block
  {
    CODE_APPEND("\n\n#ifdef IS_VERTEX_SHADER\n");
    for (const auto& pass : m_parsed.m_displayPasses) {
      CODE_APPEND("#ifdef _ENTRY_POINT_%s\n", pass.vertexShader.c_str());
      CODE_APPEND("void main() { %s(); }\n", pass.vertexShader.c_str());
      CODE_APPEND("#endif // _ENTRY_POINT_%s\n", pass.vertexShader.c_str());
    }
    CODE_APPEND("#endif // IS_VERTEX_SHADER\n");
  }

  // auto-gen pixel shader block
  {
    CODE_APPEND("\n\n#ifdef IS_PIXEL_SHADER\n");
    for (const auto& pass : m_parsed.m_displayPasses) {
      CODE_APPEND("#ifdef _ENTRY_POINT_%s\n", pass.pixelShader.c_str());
      CODE_APPEND("void main() { %s(); }\n", pass.pixelShader.c_str());
      CODE_APPEND("#endif // _ENTRY_POINT_%s\n", pass.pixelShader.c_str());
    }
    CODE_APPEND("#endif // IS_PIXEL_SHADER\n");
  }
#undef CODE_APPEND

  std::filesystem::path autoGenFileName = projPath_;
  autoGenFileName.replace_extension(".gen.glsl");

  std::ofstream autoGenFile(autoGenFileName);
  if (autoGenFile.is_open()) {
    autoGenFile.write(autoGenCode, autoGenCodeSize);
    autoGenFile.close();
  }

  delete[] autoGenCode;

  m_computePipelines.reserve(m_parsed.m_computeShaders.size());
  for (const auto& c : m_parsed.m_computeShaders) {
    ShaderDefines defs{};
    defs.emplace("IS_COMP_SHADER", "");
    defs.emplace(std::string("_ENTRY_POINT_") + c.name, "");

    ComputePipelineBuilder builder{};
    builder.setComputeShader(autoGenFileName.string(), defs);
    builder.layoutBuilder.addDescriptorSet(heap.getDescriptorSetLayout())
        .addDescriptorSet(m_descriptorSets.getLayout());

    m_computePipelines.emplace_back(app, std::move(builder));
  }

  m_displayPasses.reserve(m_parsed.m_displayPasses.size());
  for (const auto& pass : m_parsed.m_displayPasses) {
    std::vector<SubpassBuilder> subpassBuilders;
    SubpassBuilder& subpass = subpassBuilders.emplace_back();
    subpass.colorAttachments = {0};

    GraphicsPipelineBuilder& builder = subpass.pipelineBuilder;
    builder.setCullMode(VK_CULL_MODE_FRONT_BIT).setDepthTesting(false);
    {
      ShaderDefines defs{};
      defs.emplace("IS_VERTEX_SHADER", "");
      defs.emplace(std::string("_ENTRY_POINT_") + pass.vertexShader, "");
      builder.addVertexShader(autoGenFileName.string(), defs);
    }
    {
      ShaderDefines defs{};
      defs.emplace("IS_PIXEL_SHADER", "");
      defs.emplace(std::string("_ENTRY_POINT_") + pass.pixelShader, "");
      builder.addFragmentShader(autoGenFileName.string(), defs);
    }

    builder.layoutBuilder.addDescriptorSet(heap.getDescriptorSetLayout())
        .addDescriptorSet(m_descriptorSets.getLayout());
    VkClearValue colorClear;
    colorClear.color = {{0.0f, 0.0f, 0.0f, 1.0f}};
    VkClearValue depthClear;
    depthClear.depthStencil = {1.0f, 0};

    std::vector<Attachment> attachments = {Attachment{
        ATTACHMENT_FLAG_COLOR,
        app.getSwapChainImageFormat(),
        colorClear,
        false,
        false,
        true}};

    DisplayPass& pass = m_displayPasses.emplace_back();
    pass.m_renderPass = RenderPass(
        app,
        app.getSwapChainExtent(),
        std::move(attachments),
        std::move(subpassBuilders));

    ImageOptions imageOptions{};
    imageOptions.format = app.getSwapChainImageFormat();
    imageOptions.width = app.getSwapChainExtent().width;
    imageOptions.height = app.getSwapChainExtent().height;
    imageOptions.usage =
        VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    pass.m_target.image = Image(app, imageOptions);

    ImageViewOptions viewOptions{};
    viewOptions.format = imageOptions.format;
    pass.m_target.view = ImageView(app, pass.m_target.image, viewOptions);

    pass.m_target.sampler = Sampler(app, {});

    pass.m_frameBuffer = FrameBuffer(
        app,
        pass.m_renderPass,
        app.getSwapChainExtent(),
        {pass.m_target.view});

    pass.m_target.registerToTextureHeap(heap);
  }
}

void Project::draw(
    Application& app,
    VkCommandBuffer commandBuffer,
    const GlobalHeap& heap,
    const FrameContext& frame) {

  VkDescriptorSet sets[] = {
      heap.getDescriptorSet(),
      m_descriptorSets.getCurrentDescriptorSet(frame)};

  for (const auto& task : m_parsed.m_taskList) {
    switch (task.type) {
    case ParsedFlr::TT_COMPUTE: {
      const auto& dispatch = m_parsed.m_computeDispatches[task.idx];
      const auto& compute =
          m_parsed.m_computeShaders[dispatch.computeShaderIndex];
      ComputePipeline& c = m_computePipelines[dispatch.computeShaderIndex];
      c.bindPipeline(commandBuffer);
      c.bindDescriptorSets(commandBuffer, sets, 2);

      uint32_t groupCountX = (dispatch.dispatchSizeX + compute.groupSizeX - 1) /
                             compute.groupSizeX;
      uint32_t groupCountY = (dispatch.dispatchSizeY + compute.groupSizeY - 1) /
                             compute.groupSizeY;
      uint32_t groupCountZ = (dispatch.dispatchSizeZ + compute.groupSizeZ - 1) /
                             compute.groupSizeZ;
      vkCmdDispatch(commandBuffer, groupCountX, groupCountY, groupCountZ);
      break;
    }

    case ParsedFlr::TT_BARRIER: {
      const auto& parsedBuf = m_parsed.m_buffers[task.idx];
      const auto& parsedStruct = m_parsed.m_structDefs[parsedBuf.structIdx];
      const auto& buf = m_buffers[task.idx];
      BufferUtilities::rwBarrier(
          commandBuffer,
          buf.getBuffer(),
          0,
          parsedBuf.elemCount * parsedStruct.size);

      break;
    }

    case ParsedFlr::TT_DISPLAY: {
      auto& displayPass = m_displayPasses[task.idx];

      displayPass.m_target.image.transitionLayout(
          commandBuffer,
          VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
          VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
          VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);

      {
        ActiveRenderPass pass = displayPass.m_renderPass.begin(
            app,
            commandBuffer,
            frame,
            displayPass.m_frameBuffer);
        pass.setGlobalDescriptorSets(gsl::span(sets, 2));
        pass.getDrawContext().bindDescriptorSets();
        pass.getDrawContext().draw(3);
      }

      displayPass.m_target.image.transitionLayout(
          commandBuffer,
          VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
          VK_ACCESS_SHADER_READ_BIT,
          VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
      break;
    }
    };
  }
}

void Project::tryRecompile(Application& app) {
  for (auto& c : m_computePipelines)
    c.tryRecompile(app);
  for (auto& p : m_displayPasses)
    p.m_renderPass.tryRecompile(app);
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

    auto parseStructRef = [&]() -> std::optional<uint32_t> {
      if (auto name = parseName()) {
        for (uint32_t i = 0; i < m_structDefs.size(); ++i) {
          const auto& s = m_structDefs[i];
          if (name->size() == s.name.size() &&
              !strncmp(name->data(), s.name.data(), s.name.size())) {
            return i;
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
    parseChar(':');
    parseWhitespace();

    switch (*instr) {
    case I_CONST_UINT: {
      if (!name)
        continue;

      auto arg0 = parseUint();
      if (!arg0)
        continue;

      m_constUints.push_back({std::string(*name), *arg0});

      break;
    }
    case I_CONST_INT: {
      if (!name)
        continue;

      auto arg0 = parseInt();
      if (!arg0)
        continue;

      m_constInts.push_back({std::string(*name), *arg0});

      break;
    }
    case I_CONST_FLOAT: {
      if (!name)
        continue;

      auto arg0 = parseFloat();
      if (!arg0)
        continue;

      m_constFloats.push_back({std::string(*name), *arg0});

      break;
    }
    case I_STRUCT: {
      if (!name)
        continue;

      std::string nameStr(*name);

      char body[1024] = {0};
      uint32_t offs = 0;
      while (true) {
        bool breakOuter = false;
        while (*c) {
          if (*c == '}') {
            ++c;
            breakOuter = true;
            break;
          }
          ++c;
        }

        offs += sprintf(body + offs, "%s", lineBuf);

        if (breakOuter)
          break;

        *(body + offs) = '\n';
        offs++;

        flrFile.getline(lineBuf, 1024);
        c = lineBuf;
      }

      m_structDefs.push_back({nameStr, std::string(body), 0});

      break;
    }
    case I_STRUCT_SIZE: {
      auto structSize = parseUintOrVar();
      if (!structSize)
        continue;

      m_structDefs.back().size = *structSize;
      break;
    }
    case I_STRUCTURED_BUFFER: {
      if (!name)
        continue;

      auto structIdx = parseStructRef();
      if (!structIdx)
        continue;
      parseWhitespace();
      auto elemCount = parseUintOrVar();
      if (!elemCount)
        continue;

      m_buffers.push_back({std::string(*name), *structIdx, *elemCount});
      break;
    }
    case I_COMPUTE_SHADER: {
      if (!name)
        continue;

      auto groupSizeX = parseUintOrVar();
      if (!groupSizeX)
        continue;
      parseWhitespace();
      auto groupSizeY = parseUintOrVar();
      if (!groupSizeY)
        continue;
      parseWhitespace();
      auto groupSizeZ = parseUintOrVar();
      if (!groupSizeZ)
        continue;

      m_computeShaders.push_back(
          {std::string(*name), *groupSizeX, *groupSizeY, *groupSizeZ});

      break;
    }
    case I_COMPUTE_DISPATCH: {
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
      for (const auto& c : m_computeShaders) {
        if (c.name.size() == name->size() &&
            !strncmp(c.name.data(), name->data(), c.name.size()))
          break;
        ++computeShaderIdx;
      }
      if (computeShaderIdx == m_computeShaders.size())
        break;

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

      m_taskList.push_back({(uint32_t)m_displayPasses.size(), TT_DISPLAY});
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