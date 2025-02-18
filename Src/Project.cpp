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
    bool bIsDepth = (rsc.image.getOptions().usage &
      VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) != 0;

    ImageViewOptions viewOptions{};
    viewOptions.format = rsc.image.getOptions().format;
    viewOptions.aspectFlags = bIsDepth ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_COLOR_BIT;
    rsc.view = ImageView(app, rsc.image, viewOptions);

    SamplerOptions samplerOptions{};
    rsc.sampler = Sampler(app, samplerOptions);
  }

  m_textureFiles.reserve(m_parsed.m_textureFiles.size());
  for (ParsedFlr::TextureFile& tex : m_parsed.m_textureFiles) {
    ImageResource& rsc = m_textureFiles.emplace_back();

    rsc.image = Image(
        app,
        (VkCommandBuffer)commandBuffer,
        tex.loadedImage.data,
        tex.createOptions);

    ImageViewOptions viewOptions{};
    viewOptions.format = rsc.image.getOptions().format;
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
        60.0f,
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
    if ((rsc.image.getOptions().usage & VK_IMAGE_USAGE_STORAGE_BIT) == 0)
      continue;

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

      if ((desc.createOptions.usage & VK_IMAGE_USAGE_STORAGE_BIT) == 0)
        continue;

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
      } else {
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


  // auto-gen pixel shader block, pre-include of user-file
  {
    CODE_APPEND("\n\n#ifdef IS_PIXEL_SHADER\n");
    for (const auto& pass : m_parsed.m_renderPasses) {
      for (const auto& draw : pass.draws) {
        CODE_APPEND("#ifdef _ENTRY_POINT_%s\n", draw.pixelShader.c_str());
        uint32_t colorAttachmentIdx = 0;
        for (const auto& attachmentRef : pass.attachments) {
          const auto& img = m_images[attachmentRef.imageIdx];
          if ((img.image.getOptions().usage &
            VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) == 0) {
            CODE_APPEND(
              "layout(location = %d) out vec4 %s;\n",
              colorAttachmentIdx++,
              attachmentRef.aliasName.c_str());
          }
        }
        CODE_APPEND("#endif // _ENTRY_POINT_%s\n", draw.pixelShader.c_str());
      }
    }
    CODE_APPEND("#endif // IS_PIXEL_SHADER\n");
  }

  std::string userShaderName = shaderFileName.filename().string();
  CODE_APPEND("#include \"%s\"\n\n", userShaderName.c_str());

  // auto-gen compute shader block, post-include of user-file
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

  // auto-gen vertex shader block, post-include of user-file
  {
    CODE_APPEND("\n\n#ifdef IS_VERTEX_SHADER\n");
    for (const auto& pass : m_parsed.m_renderPasses) {
      for (const auto& draw : pass.draws) {
        CODE_APPEND("#ifdef _ENTRY_POINT_%s\n", draw.vertexShader.c_str());
        if (draw.vertexOutputStructIdx >= 0) {
          CODE_APPEND(
              "layout(location = 0) out %s _VERTEX_OUTPUT;\n",
              m_parsed.m_structDefs[draw.vertexOutputStructIdx].name.c_str());
          CODE_APPEND(
              "void main() { _VERTEX_OUTPUT = %s(); }\n",
              draw.vertexShader.c_str());
        } else {
          CODE_APPEND("void main() { %s(); }\n", draw.vertexShader.c_str());
        }
        CODE_APPEND("#endif // _ENTRY_POINT_%s\n", draw.vertexShader.c_str());
      }
    }
    CODE_APPEND("#endif // IS_VERTEX_SHADER\n");
  }

  // auto-gen pixel shader block, post-include of user-file
  {
    CODE_APPEND("\n\n#ifdef IS_PIXEL_SHADER\n");
    for (const auto& pass : m_parsed.m_renderPasses) {
      for (const auto& draw : pass.draws) {
        CODE_APPEND("#ifdef _ENTRY_POINT_%s\n", draw.pixelShader.c_str());
        
        if (draw.vertexOutputStructIdx >= 0) {
          CODE_APPEND(
              "layout(location = 0) in %s _VERTEX_INPUT;\n",
              m_parsed.m_structDefs[draw.vertexOutputStructIdx].name.c_str());
          CODE_APPEND(
              "void main() { %s(_VERTEX_INPUT); }\n",
              draw.pixelShader.c_str());
        } else {
          CODE_APPEND("void main() { %s(); }\n", draw.pixelShader.c_str());
        }
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

    VkClearValue colorClear;
    colorClear.color = {{0.0f, 0.0f, 0.0f, 1.0f}};
    VkClearValue depthClear;
    depthClear.depthStencil = {1.0f, 0};

    std::vector<Attachment> attachments;
    std::vector<uint32_t> colorAttachments;
    std::optional<uint32_t> depthAttachment = std::nullopt;
    std::vector<VkImageView> attachmentViews;
    for (const auto& attachmentRef : pass.attachments) {
      const auto& imageDesc = m_parsed.m_images[attachmentRef.imageIdx];
      const auto& imageRsc = m_images[attachmentRef.imageIdx];

      bool bIsDepth = (imageDesc.createOptions.usage &
                       VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) != 0;
      if (bIsDepth)
        depthAttachment = (uint32_t)attachments.size();
      else
        colorAttachments.push_back(attachments.size());
      Attachment& attachment = attachments.emplace_back();
      attachment.clearValue = bIsDepth ? depthClear : colorClear;
      attachment.flags =
          bIsDepth ? ATTACHMENT_FLAG_DEPTH : ATTACHMENT_FLAG_COLOR;
      attachment.format = imageDesc.createOptions.format;
      attachment.forPresent = false;
      attachment.load = attachmentRef.bLoad;
      attachment.store = attachmentRef.bStore;

      attachmentViews.push_back(imageRsc.view);
    }

    for (const auto& draw : pass.draws) {
      SubpassBuilder& subpass = subpassBuilders.emplace_back();
      subpass.colorAttachments = colorAttachments;

      GraphicsPipelineBuilder& builder = subpass.pipelineBuilder;

      if (!draw.bDisableDepth && depthAttachment)
        subpass.depthAttachment = *depthAttachment;
      else
        builder.setDepthTesting(false);

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

    DrawPass& drawPass = m_drawPasses.emplace_back();
    drawPass.m_renderPass = RenderPass(
        app,
        {(uint32_t)pass.width, (uint32_t)pass.height},
        std::move(attachments),
        std::move(subpassBuilders));

    drawPass.m_frameBuffer = FrameBuffer(
        app,
        drawPass.m_renderPass,
        {(uint32_t)pass.width, (uint32_t)pass.height},
        std::move(attachmentViews));
  }

  m_images[m_parsed.m_displayImageIdx].registerToTextureHeap(heap);

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
      const auto& passDesc = m_parsed.m_renderPasses[task.idx];
      auto& drawPass = m_drawPasses[task.idx];

      for (const auto& attachmentRef : passDesc.attachments) {
        auto& imgRsc = m_images[attachmentRef.imageIdx];
        if ((imgRsc.image.getOptions().aspectMask & VK_IMAGE_ASPECT_DEPTH_BIT) != 0) {
          imgRsc.image.transitionLayout(
            commandBuffer,
            VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
            VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT |
            VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT,
            VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT);
        }
        else {
          imgRsc.image.transitionLayout(
            commandBuffer,
            VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);
        }
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
            SimpleObjLoader::LoadedObj& obj = m_objModels[draw.objMeshIdx];
            for (SimpleObjLoader::ObjMesh& mesh : obj.m_meshes) {
              pass.getDrawContext().bindIndexBuffer(mesh.m_indices);
              pass.getDrawContext().bindVertexBuffer(obj.m_vertices);
              pass.getDrawContext().drawIndexed(
                  mesh.m_indices.getIndexCount(),
                  1);
            }
          } else {
            pass.getDrawContext().draw(draw.vertexCount, draw.instanceCount);
          }
          if (!pass.isLastSubpass())
            pass.nextSubpass();
        }
      }

      for (const auto& attachmentRef : passDesc.attachments) {
        auto& imgRsc = m_images[attachmentRef.imageIdx];
        if ((imgRsc.image.getOptions().aspectMask & VK_IMAGE_ASPECT_DEPTH_BIT) != 0) {
          imgRsc.image.transitionLayout(
            commandBuffer,
            VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
            VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT |
            VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT,
            VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT);
        }
        else {
          imgRsc.image.transitionLayout(
            commandBuffer,
            VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            VK_ACCESS_SHADER_READ_BIT,
            VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
        }
      }

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
} // namespace flr