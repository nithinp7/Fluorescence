#include "Project.h"

#include "Audio.h"

#include <Althea/BufferUtilities.h>
#include <Althea/DescriptorSet.h>
#include <Althea/Gui.h>
#include <Althea/Parser.h>
#include <Althea/ResourcesAssignment.h>
#include <Althea/SingleTimeCommandBuffer.h>
#include <stdio.h>
#include <string.h>

#include <filesystem>
#include <fstream>
#include <iostream>
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
    : m_parsed(app, projPath),
      m_buffers(),
      m_images(),
      m_computePipelines(),
      m_drawPasses(),
      m_descriptorSets(),
      m_dynamicUniforms(),
      m_dynamicDataBuffer(),
      m_cameraController(),
      m_perspectiveCamera(),
      m_audioInput(),
      m_pAudio(nullptr),
      m_displayPassIdx(0),
      m_bHasDynamicData(false),
      m_failedShaderCompile(false),
      m_shaderCompileErrMsg() {
  // TODO: split out resource creation vs code generation
  if (m_parsed.m_failed)
    return;

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
        VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        allocInfo));
    vkCmdFillBuffer(
        commandBuffer,
        m_buffers.back().getBuffer(),
        0,
        structdef.size * desc.elemCount,
        0);
  }

  m_images.reserve(m_parsed.m_images.size());
  for (const ParsedFlr::ImageDesc& desc : m_parsed.m_images) {
    ImageResource& rsc = m_images.emplace_back();

    rsc.image = Image(app, desc.createOptions);

    ImageViewOptions viewOptions{};
    rsc.view = ImageView(app, rsc.image, viewOptions);

    SamplerOptions samplerOptions{};
    rsc.sampler = Sampler(app, samplerOptions);
  }

  m_textureFiles.reserve(m_parsed.m_textureFiles.size());
  for (ParsedFlr::TextureFile& tex : m_parsed.m_textureFiles) {
    ImageResource& rsc = m_textureFiles.emplace_back();
    
    rsc.image = Image(app, (VkCommandBuffer)commandBuffer, tex.loadedImage.data, tex.createOptions);

    ImageViewOptions viewOptions{};
    rsc.view = ImageView(app, rsc.image, viewOptions);

    SamplerOptions samplerOptions{};
    rsc.sampler = Sampler(app, samplerOptions);
  }

  m_objModels.reserve(m_parsed.m_objModels.size());
  for (const auto& m : m_parsed.m_objModels) {
    auto& obj = m_objModels.emplace_back();
    if (!SimpleObjLoader::loadObj(app, commandBuffer, m.path.c_str(), obj)) {
      m_parsed.m_failed = true;
      sprintf(m_parsed.m_errMsg, "Failed to load obj mesh %s", m.path.c_str());
      return;
    }
  }

  m_bHasDynamicData =
      !m_parsed.m_sliderUints.empty() || !m_parsed.m_sliderInts.empty() ||
      !m_parsed.m_sliderFloats.empty() || !m_parsed.m_checkboxes.empty();
  if (m_bHasDynamicData) {
    size_t size = 0;
    size += 4 * m_parsed.m_sliderUints.size();
    size += 4 * m_parsed.m_sliderInts.size();
    size += 4 * m_parsed.m_sliderFloats.size();
    size += 4 * m_parsed.m_checkboxes.size();
    if (size % 64) {
      size += 64 - (size % 64);
    }

    size_t offset = 0;

    m_dynamicDataBuffer.resize(size);
    for (auto& uslider : m_parsed.m_sliderUints) {
      uslider.pValue =
          reinterpret_cast<uint32_t*>(m_dynamicDataBuffer.data() + offset);
      *uslider.pValue = uslider.defaultValue;
      offset += 4;
    }
    for (auto& islider : m_parsed.m_sliderInts) {
      islider.pValue =
          reinterpret_cast<int*>(m_dynamicDataBuffer.data() + offset);
      *islider.pValue = islider.defaultValue;
      offset += 4;
    }
    for (auto& fslider : m_parsed.m_sliderFloats) {
      fslider.pValue =
          reinterpret_cast<float*>(m_dynamicDataBuffer.data() + offset);
      *fslider.pValue = fslider.defaultValue;
      offset += 4;
    }
    for (auto& checkbox : m_parsed.m_checkboxes) {
      checkbox.pValue =
          reinterpret_cast<uint32_t*>(m_dynamicDataBuffer.data() + offset);
      *checkbox.pValue = (uint32_t)checkbox.defaultValue;
      offset += 4; // bools are 32bit in glsl
    }

    m_dynamicUniforms =
        DynamicBuffer(app, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, size);
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
      m_dynamicUniforms.updateData(i, m_dynamicDataBuffer);
  }

  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_PERSPECTIVE_CAMERA)) {
    m_cameraController = CameraController(
        90.0f,
        (float)app.getSwapChainExtent().width /
            (float)app.getSwapChainExtent().height);
    m_perspectiveCamera = TransientUniforms<PerspectiveCamera>(app);
  }

  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_SYSTEM_AUDIO_INPUT)) {
    m_audioInput = TransientUniforms<AudioInput>(app);
  }

  DescriptorSetLayoutBuilder dsBuilder{};
  dsBuilder.addUniformBufferBinding();
  for (const BufferAllocation& b : m_buffers) {
    dsBuilder.addStorageBufferBinding(VK_SHADER_STAGE_ALL);
  }
  for (const ImageResource& rsc : m_images) {
    dsBuilder.addStorageImageBinding(VK_SHADER_STAGE_ALL);
  }
  for (const auto& t : m_parsed.m_textures) {
    dsBuilder.addTextureBinding(VK_SHADER_STAGE_ALL);
  }
  if (m_bHasDynamicData) {
    dsBuilder.addUniformBufferBinding();
  }
  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_PERSPECTIVE_CAMERA)) {
    dsBuilder.addUniformBufferBinding();
  }
  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_SYSTEM_AUDIO_INPUT)) {
    dsBuilder.addUniformBufferBinding();
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

  // constant declarations
  for (const auto& c : m_parsed.m_constInts)
    CODE_APPEND("#define %s %d\n", c.name.c_str(), c.value);
  for (const auto& c : m_parsed.m_constUints)
    CODE_APPEND("#define %s %u\n", c.name.c_str(), c.value);
  for (const auto& c : m_parsed.m_constFloats)
    CODE_APPEND("#define %s %f\n", c.name.c_str(), c.value);
  CODE_APPEND("\n");

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

    for (int i = 0; i < m_images.size(); ++i) {
      const auto& desc = m_parsed.m_images[i];
      const auto& rsc = m_images[i];

      assign.bindStorageImage(rsc.view, rsc.sampler);
      CODE_APPEND(
          "layout(set=1,binding=%u, %s) uniform image2D %s;\n",
          slot++,
          desc.format.c_str(),
          desc.name.c_str());
    }

    for (int i = 0; i < m_parsed.m_textures.size(); ++i) {
      const auto& txDesc = m_parsed.m_textures[i];

      if (txDesc.imageIdx >= 0) {
        const auto& rsc = m_images[txDesc.imageIdx];
        assign.bindTexture(rsc);
      } else if (txDesc.texFileIdx >= 0) {
        const auto& rsc = m_textureFiles[txDesc.texFileIdx];
        assign.bindTexture(rsc);
      }
      else {
        assert(false);
      }
      CODE_APPEND(
          "layout(set=1,binding=%u) uniform sampler2D %s;\n",
          slot++,
          txDesc.name.c_str());
    }

    if (m_bHasDynamicData) {
      assign.bindTransientUniforms(m_dynamicUniforms);

      CODE_APPEND(
          "\nlayout(set=1, binding=%u) uniform _UserUniforms {\n",
          slot++);

      for (const auto& uslider : m_parsed.m_sliderUints) {
        CODE_APPEND("\tuint %s;\n", uslider.name.c_str());
      }
      for (const auto& islider : m_parsed.m_sliderInts) {
        CODE_APPEND("\tint %s;\n", islider.name.c_str());
      }
      for (const auto& fslider : m_parsed.m_sliderFloats) {
        CODE_APPEND("\tfloat %s;\n", fslider.name.c_str());
      }
      for (const auto& checkbox : m_parsed.m_checkboxes) {
        CODE_APPEND("\tbool %s;\n", checkbox.name.c_str());
      }

      CODE_APPEND("};\n\n");
    }

    if (m_parsed.isFeatureEnabled(ParsedFlr::FF_PERSPECTIVE_CAMERA)) {
      assign.bindTransientUniforms(m_perspectiveCamera);
    }

    if (m_parsed.isFeatureEnabled(ParsedFlr::FF_SYSTEM_AUDIO_INPUT)) {
      assign.bindTransientUniforms(m_audioInput);
    }
  }

  // includes
  CODE_APPEND("#include <Fluorescence.glsl>\n\n");

  // camera uniforms (references included structs)
  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_PERSPECTIVE_CAMERA)) {
    CODE_APPEND(
        "layout(set=1, binding=%u) uniform _CameraUniforms { PerspectiveCamera "
        "camera; };\n\n",
        slot++);
  }

  // audio uniforms
  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_SYSTEM_AUDIO_INPUT)) {
    CODE_APPEND(
        "layout(set=1, binding=%u) uniform _AudioUniforms { AudioInput "
        "audio; };\n\n",
        slot++);
  }

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
    for (const auto& pass : m_parsed.m_renderPasses) {
      for (const auto& draw : pass.draws) {
        CODE_APPEND("#ifdef _ENTRY_POINT_%s\n", draw.vertexShader.c_str());
        CODE_APPEND("void main() { %s(); }\n", draw.vertexShader.c_str());
        CODE_APPEND("#endif // _ENTRY_POINT_%s\n", draw.vertexShader.c_str());
      }
    }
    CODE_APPEND("#endif // IS_VERTEX_SHADER\n");
  }

  // auto-gen pixel shader block
  {
    CODE_APPEND("\n\n#ifdef IS_PIXEL_SHADER\n");
    for (const auto& pass : m_parsed.m_renderPasses) {
      for (const auto& draw : pass.draws) {
        CODE_APPEND("#ifdef _ENTRY_POINT_%s\n", draw.pixelShader.c_str());
        CODE_APPEND("void main() { %s(); }\n", draw.pixelShader.c_str());
        CODE_APPEND("#endif // _ENTRY_POINT_%s\n", draw.pixelShader.c_str());
      }
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

    {
      std::string errors = builder.compileShadersGetErrors();
      if (errors.size()) {
        m_parsed.m_failed = true;
        strncpy(m_parsed.m_errMsg, errors.c_str(), errors.size());
        return;
      }
    }

    m_computePipelines.emplace_back(app, std::move(builder));
  }

  m_drawPasses.reserve(m_parsed.m_renderPasses.size());
  for (const auto& pass : m_parsed.m_renderPasses) {
    std::vector<SubpassBuilder> subpassBuilders;
    subpassBuilders.reserve(pass.draws.size());

    bool bAnyDrawsUseDepth = false;

    for (const auto& draw : pass.draws) {
      SubpassBuilder& subpass = subpassBuilders.emplace_back();
      subpass.colorAttachments = {0};

      GraphicsPipelineBuilder& builder = subpass.pipelineBuilder;

      if (!draw.bDisableDepth) {
        subpass.depthAttachment = 1;
        bAnyDrawsUseDepth = true;
      } else {
        builder.setDepthTesting(false);
      }

      if (draw.objMeshIdx >= 0) {
        builder.addVertexInputBinding<SimpleObjLoader::ObjVert>();
        builder.addVertexAttribute(
            VertexAttributeType::VEC3,
            offsetof(SimpleObjLoader::ObjVert, position));
        builder.addVertexAttribute(
            VertexAttributeType::VEC3,
            offsetof(SimpleObjLoader::ObjVert, normal));
        builder.addVertexAttribute(
            VertexAttributeType::VEC2,
            offsetof(SimpleObjLoader::ObjVert, uv));
      }

      {
        ShaderDefines defs{};
        defs.emplace("IS_VERTEX_SHADER", "");
        defs.emplace(std::string("_ENTRY_POINT_") + draw.vertexShader, "");
        builder.addVertexShader(autoGenFileName.string(), defs);
      }
      {
        ShaderDefines defs{};
        defs.emplace("IS_PIXEL_SHADER", "");
        defs.emplace(std::string("_ENTRY_POINT_") + draw.pixelShader, "");
        builder.addFragmentShader(autoGenFileName.string(), defs);
      }

      {
        std::string errors = builder.compileShadersGetErrors();
        if (errors.size()) {
          m_parsed.m_failed = true;
          strncpy(m_parsed.m_errMsg, errors.c_str(), errors.size());
          return;
        }
      }

      builder.layoutBuilder.addDescriptorSet(heap.getDescriptorSetLayout())
          .addDescriptorSet(m_descriptorSets.getLayout());
    }

    VkClearValue colorClear;
    colorClear.color = {{0.0f, 0.0f, 0.0f, 1.0f}};
    VkClearValue depthClear;
    depthClear.depthStencil = {1.0f, 0};

    VkExtent2D extent{};
    if (pass.bIsDisplayPass) {
      extent = app.getSwapChainExtent();
    } else {
      extent.width = pass.width;
      extent.height = pass.height;
    }

    // TODO: custom attachment format?
    std::vector<Attachment> attachments = {Attachment{
        ATTACHMENT_FLAG_COLOR,
        app.getSwapChainImageFormat(),
        colorClear,
        false,
        false,
        true}};

    if (bAnyDrawsUseDepth) {
      attachments.push_back(Attachment{
          ATTACHMENT_FLAG_DEPTH,
          app.getDepthImageFormat(),
          depthClear,
          false,
          false,
          false});
    }

    DrawPass& drawPass = m_drawPasses.emplace_back();
    drawPass.m_renderPass = RenderPass(
        app,
        extent,
        std::move(attachments),
        std::move(subpassBuilders));

    ImageOptions imageOptions{};
    imageOptions.format = app.getSwapChainImageFormat();
    imageOptions.width = extent.width;
    imageOptions.height = extent.height;
    imageOptions.usage =
        VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    drawPass.m_target.image = Image(app, imageOptions);

    ImageViewOptions viewOptions{};
    viewOptions.format = imageOptions.format;
    drawPass.m_target.view =
        ImageView(app, drawPass.m_target.image, viewOptions);

    drawPass.m_target.sampler = Sampler(app, {});

    if (bAnyDrawsUseDepth) {
      ImageOptions depthOptions{};
      depthOptions.format = app.getDepthImageFormat();
      depthOptions.width = extent.width;
      depthOptions.height = extent.height;
      depthOptions.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
      depthOptions.aspectMask =
          VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT;
      drawPass.m_depth.image = Image(app, depthOptions);

      ImageViewOptions depthViewOptions{};
      depthViewOptions.format = depthOptions.format;
      depthViewOptions.aspectFlags = VK_IMAGE_ASPECT_DEPTH_BIT;
      drawPass.m_depth.view =
          ImageView(app, drawPass.m_depth.image, depthViewOptions);

      drawPass.m_depth.sampler = Sampler(app, {});

      drawPass.m_frameBuffer = FrameBuffer(
          app,
          drawPass.m_renderPass,
          extent,
          {drawPass.m_target.view, drawPass.m_depth.view});
    } else {
      drawPass.m_frameBuffer = FrameBuffer(
          app,
          drawPass.m_renderPass,
          extent,
          {drawPass.m_target.view});
    }
  }

  for (int i = 0; i < m_parsed.m_renderPasses.size(); i++) {
    if (m_parsed.m_renderPasses[i].bIsDisplayPass) {
      m_displayPassIdx = i;
      m_drawPasses[i].m_target.registerToTextureHeap(heap);
      break;
    }
  }

  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_SYSTEM_AUDIO_INPUT)) {
    m_pAudio = std::make_unique<Audio>(true);
  }
}

Project::~Project() {}

void Project::tick(Application& app, const FrameContext& frame) {
  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_SYSTEM_AUDIO_INPUT)) {
    AudioInput audioInput;
    m_pAudio->play();
    m_pAudio->copySamples(&audioInput.packedSamples[0][0], 512 * 4);
    // Audio::DCT2_naive(&audioInput.packedCoeffs[0][0],
    // &audioInput.packedSamples[0][0], 512 * 4);
    m_pAudio->DCT2_naive(&audioInput.packedCoeffs[0][0], 512 * 4);

    m_audioInput.updateUniforms(audioInput, frame);
  }

  if (m_bHasDynamicData && !app.getInputManager().getMouseCursorHidden()) {
    if (ImGui::Begin("Options", false)) {
      // TODO: cache UI order to avoid linear scans each time...
      uint32_t uiIdx = 0;
      char nameBuf[128];

      auto drawUiElem = [&]() -> bool {
        for (const auto& uslider : m_parsed.m_sliderUints) {
          if (uslider.uiIdx == uiIdx) {
            ImGui::Text(uslider.name.c_str());
            sprintf(nameBuf, "##%s_%u", uslider.name.c_str(), uiIdx);
            int v = static_cast<int>(*uslider.pValue);
            if (ImGui::SliderInt(nameBuf, &v, uslider.min, uslider.max)) {
              *uslider.pValue = static_cast<uint32_t>(v);
            }
            return true;
          }
        }
        for (const auto& islider : m_parsed.m_sliderInts) {
          if (islider.uiIdx == uiIdx) {
            ImGui::Text(islider.name.c_str());
            sprintf(nameBuf, "##%s_%u", islider.name.c_str(), uiIdx);
            ImGui::SliderInt(nameBuf, islider.pValue, islider.min, islider.max);
            return true;
          }
        }
        for (const auto& fslider : m_parsed.m_sliderFloats) {
          if (fslider.uiIdx == uiIdx) {
            ImGui::Text(fslider.name.c_str());
            sprintf(nameBuf, "##%s_%u", fslider.name.c_str(), uiIdx);
            ImGui::SliderFloat(
                nameBuf,
                fslider.pValue,
                fslider.min,
                fslider.max);
            return true;
          }
        }
        for (const auto& checkbox : m_parsed.m_checkboxes) {
          if (checkbox.uiIdx == uiIdx) {
            ImGui::Text(checkbox.name.c_str());
            sprintf(nameBuf, "##%s_%u", checkbox.name.c_str(), uiIdx);
            bool bValue = (bool)*checkbox.pValue;
            if (ImGui::Checkbox(nameBuf, &bValue))
              *checkbox.pValue = (uint32_t)bValue;
            return true;
          }
        }
        return false;
      };
      while (drawUiElem()) {
        uiIdx++;
      }
    }

    ImGui::End();

    m_dynamicUniforms.updateData(
        frame.frameRingBufferIndex,
        m_dynamicDataBuffer);
  }

  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_PERSPECTIVE_CAMERA)) {
    m_cameraController.tick(frame.deltaTime);
    PerspectiveCamera camera{};
    camera.view = m_cameraController.getCamera().computeView();
    camera.inverseView = glm::inverse(camera.view);
    camera.projection = m_cameraController.getCamera().getProjection();
    camera.inverseProjection = glm::inverse(camera.projection);
    m_perspectiveCamera.updateUniforms(camera, frame);
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
      const auto& parsedBarrier = m_parsed.m_barriers[task.idx];
      for (uint32_t bufferIdx : parsedBarrier.buffers) {
        const auto& parsedBuf = m_parsed.m_buffers[bufferIdx];
        const auto& parsedStruct = m_parsed.m_structDefs[parsedBuf.structIdx];
        const auto& buf = m_buffers[bufferIdx];
        BufferUtilities::rwBarrier(
            commandBuffer,
            buf.getBuffer(),
            0,
            parsedBuf.elemCount * parsedStruct.size);
      }
      break;
    }

    case ParsedFlr::TT_RENDER: {
      auto& drawPass = m_drawPasses[task.idx];

      drawPass.m_target.image.transitionLayout(
          commandBuffer,
          VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
          VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
          VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);

      if ((VkImage)drawPass.m_depth.image != VK_NULL_HANDLE) {
        drawPass.m_depth.image.transitionLayout(
            commandBuffer,
            VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
            VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT |
                VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT,
            VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT);
      }

      {
        ActiveRenderPass pass = drawPass.m_renderPass.begin(
            app,
            commandBuffer,
            frame,
            drawPass.m_frameBuffer);
        pass.setGlobalDescriptorSets(gsl::span(sets, 2));
        pass.getDrawContext().bindDescriptorSets();
        for (const auto& draw : m_parsed.m_renderPasses[task.idx].draws) {
          if (draw.objMeshIdx >= 0) {
            for (SimpleObjLoader::ObjMesh& mesh :
                 m_objModels[draw.objMeshIdx].m_meshes) {
              pass.getDrawContext().bindVertexBuffer(mesh.m_vertices);
              pass.getDrawContext().draw(mesh.m_vertices.getVertexCount(), 1);
            }
          } else {
            pass.getDrawContext().draw(draw.vertexCount, draw.instanceCount);
          }
          if (!pass.isLastSubpass())
            pass.nextSubpass();
        }
      }

      drawPass.m_target.image.transitionLayout(
          commandBuffer,
          VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
          VK_ACCESS_SHADER_READ_BIT,
          VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);

      break;
    }

    case ParsedFlr::TT_TRANSITION: {
      const auto& transition = m_parsed.m_transitions[task.idx];
      auto& rsc = m_images[transition.image];

      switch (transition.transitionTarget) {
      case ParsedFlr::LTT_TEXTURE: {
        rsc.image.transitionLayout(
            commandBuffer,
            VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL,
            VK_ACCESS_SHADER_READ_BIT,
            VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
        break;
      }
      case ParsedFlr::LTT_IMAGE_RW: {
        rsc.image.transitionLayout(
            commandBuffer,
            VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL,
            VK_ACCESS_SHADER_READ_BIT,
            VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
        break;
      }
      case ParsedFlr::LTT_ATTACHMENT: {
        rsc.image.transitionLayout(
            commandBuffer,
            VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);
        break;
      }
      }
      break;
    }
    };
  }
}

void Project::tryRecompile(Application& app) {
  m_failedShaderCompile = false;
  *m_shaderCompileErrMsg = 0;

  std::string error;
  for (auto& c : m_computePipelines) {
    c.tryRecompile(app);
    if (c.hasShaderRecompileErrors()) {
      error += c.getShaderRecompileErrors() + "\n";
    }
  }

  for (auto& p : m_drawPasses) {
    p.m_renderPass.tryRecompile(app);
    for (auto& s : p.m_renderPass.getSubpasses()) {
      GraphicsPipeline& g = s.getPipeline();
      if (g.hasShaderRecompileErrors()) {
        error += g.getShaderRecompileErrors() + "\n";
      }
    }
  }

  if (error.size() > 0) {
    strncpy(m_shaderCompileErrMsg, error.c_str(), error.size());
    m_failedShaderCompile = true;
  }
}

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

ParsedFlr::ParsedFlr(Application& app, const char* filename)
    : m_featureFlags(FF_NONE), m_failed(true), m_errMsg() {

  m_constUints.push_back({"SCREEN_WIDTH", app.getSwapChainExtent().width});
  m_constUints.push_back({"SCREEN_HEIGHT", app.getSwapChainExtent().height});

  std::ifstream flrFile(filename);
  char lineBuf[1024];

  uint32_t lineNumber = 0;
  uint32_t uiIdx = 0;

#define PARSER_VERIFY(X, MSG)                                                  \
  if (!(X)) {                                                                  \
    sprintf(                                                                   \
        m_errMsg,                                                              \
        "ERROR: " MSG " ON LINE: %u IN FILE: %s\n",                            \
        lineNumber,                                                            \
        filename);                                                             \
    std::cerr << m_errMsg << std::endl;                                        \
    flrFile.close();                                                           \
    return;                                                                    \
  }

  while (flrFile.getline(lineBuf, 1024)) {
    lineNumber++;

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

    p.parseWhitespace();

    // TODO: support comment within line
    if (p.parseChar('#') || p.parseChar(0))
      continue;

    auto instr = parseInstruction();
    PARSER_VERIFY(instr, "Could not parse instruction!");

    p.parseWhitespace();

    auto name = p.parseName();

    p.parseWhitespace();
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
      PARSER_VERIFY(value, "Could not parse min value for float slider.");
      p.parseWhitespace();

      auto max = p.parseFloat();
      PARSER_VERIFY(value, "Could not parse max value for float slider.");

      m_sliderFloats.push_back(
          {std::string(*name), *value, *min, *max, uiIdx++, nullptr});
      break;
    }
    case I_CHECKBOX: {
      PARSER_VERIFY(name, "Could not parse name for checkbox.");

      auto value = p.parseBool();
      PARSER_VERIFY(value, "Could not parse default value for checkbox.");

      m_checkboxes.push_back({std::string(*name), *value, uiIdx++, nullptr});

      break;
    }
    case I_STRUCT: {
      PARSER_VERIFY(name, "Could not parse struct name.");

      std::string nameStr(*name);

      char body[1024] = {0};
      uint32_t offs = 0;
      uint32_t structStartLine = lineNumber;
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

        if (!flrFile.getline(lineBuf, 1024)) {
          lineNumber = structStartLine; // reset line to start of struct
          PARSER_VERIFY(
              false,
              "Found unterminated struct declaration, expected \'}\'.");
        }
        lineNumber++;
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

      m_buffers.push_back({std::string(*name), *structIdx, *elemCount});
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

      m_taskList.push_back({(uint32_t)m_computeDispatches.size(), TT_COMPUTE});
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

      m_taskList.push_back({(uint32_t)m_barriers.size(), TT_BARRIER});
      m_barriers.emplace_back().buffers = std::move(buffers);

      break;
    }
    case I_DISPLAY_PASS: {
      // PARSER_VERIFY(name, "Could not parse display-pass name.");

      m_taskList.push_back({(uint32_t)m_renderPasses.size(), TT_RENDER});
      m_renderPasses.push_back({{}, 0, 0, true});
      break;
    }
    case I_RENDER_PASS: {
      // PARSER_VERIFY(name, "Could not parse render-pass name.");

      auto width = parseUintOrVar();
      PARSER_VERIFY(width, "Could not parse render-pass target width.");
      p.parseWhitespace();
      auto height = parseUintOrVar();
      PARSER_VERIFY(height, "Could not parse render-pass target height.");

      m_taskList.push_back({(uint32_t)m_renderPasses.size(), TT_RENDER});
      m_renderPasses.push_back({{}, *width, *height, false});
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
           false});
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

      ImageDesc& desc = m_images.emplace_back();
      desc.name = std::string(*name);
      desc.format = std::string(*format);
      desc.createOptions = ImageOptions{};
      desc.createOptions.width = *width;
      desc.createOptions.height = *height;
      desc.createOptions.usage = VK_IMAGE_USAGE_STORAGE_BIT;

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

      std::string pathStr(*path);
      PARSER_VERIFY(
          Utilities::checkFileExists(pathStr),
          "Could not find specified texture file.");

      int texFileIdx = m_textureFiles.size();
      auto& texFile = m_textureFiles.emplace_back();
      Utilities::loadPng(pathStr, texFile.loadedImage);
      PARSER_VERIFY(texFile.loadedImage.data.size() > 0, "Could not load specified texture file.");

      texFile.createOptions = ImageOptions{};
      texFile.createOptions.width = texFile.loadedImage.width;
      texFile.createOptions.height = texFile.loadedImage.height;

      assert(texFile.loadedImage.channels == 4);
      assert(texFile.loadedImage.bytesPerChannel == 1);

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

      m_taskList.push_back({(uint32_t)m_transitions.size(), TT_TRANSITION});
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
    default:
      PARSER_VERIFY(false, "Encountered unknown instruction.");
      continue;
    }
  }

#undef PARSER_VERIFY

  flrFile.close();
  m_failed = false;
}
} // namespace flr