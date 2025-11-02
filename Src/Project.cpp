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

#define GLFW_EXPOSE_NATIVE_WIN32
#include <GLFW/glfw3native.h>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <utility>
#include <xstring>

using namespace AltheaEngine;

namespace AltheaEngine {
extern InputManager* GInputManager;
}

namespace flr {
extern Application* GApplication;
extern GlobalHeap* GGlobalHeap;

Project::Project(
    SingleTimeCommandBuffer& commandBuffer,
    const TransientUniforms<FlrUniforms>& flrUniforms,
    const char* projPath,
    const FlrParams& params)
    : m_projPath(projPath),
      m_parsed(*GApplication, projPath, params),
      m_buffers(),
      m_images(),
      m_computePipelines(),
      m_drawPasses(),
      m_descriptorSets(),
      m_dynamicUniforms(),
      m_dynamicDataBuffer(),
      m_cameraController(),
      m_cameraArgs(),
      m_perspectiveCamera(),
      m_audioInput(),
      m_pAudio(nullptr),
      m_pendingSaveImage(std::nullopt),
      m_bHasDynamicData(false),
      m_bFirstDraw(true),
      m_failedShaderCompile(false),
      m_shaderCompileErrMsg(),
      m_pushData() {
  // TODO: split out resource creation vs code generation
  if (m_parsed.m_failed)
    return;

  std::filesystem::path projName = m_projPath.stem();
  std::filesystem::path folder = m_projPath.parent_path();

  m_buffers.reserve(m_parsed.m_buffers.size());
  for (const ParsedFlr::BufferDesc& desc : m_parsed.m_buffers) {
    const ParsedFlr::StructDef& structdef =
        m_parsed.m_structDefs[desc.structIdx];

    VmaAllocationCreateInfo allocInfo{};
    VkBufferUsageFlags usageFlags =
        VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    if (desc.bTransferSrc)
      usageFlags |= VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    if (desc.bIndirectArgs)
      usageFlags |= VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
    if (desc.bIndexBuffer)
      usageFlags |= VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
    if (desc.bCpuVisible) {
      allocInfo.flags = VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
      allocInfo.usage = VMA_MEMORY_USAGE_AUTO;
      usageFlags |= VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    } else {
      allocInfo.usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE;
    }

    auto& bufCollection = m_buffers.emplace_back();
    m_bufferResourceStates.emplace_back() =
        VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
    for (int bi = 0; bi < desc.bufferCount; bi++) {
      bufCollection.push_back(BufferUtilities::createBuffer(
          *GApplication,
          structdef.size * desc.elemCount,
          usageFlags,
          allocInfo));
      if (desc.bCpuVisible) {
        void* pMapped = bufCollection.back().mapMemory();
        memset(pMapped, 0, structdef.size * desc.elemCount);
        bufCollection.back().unmapMemory();
      } else {
        vkCmdFillBuffer(
            commandBuffer,
            bufCollection.back().getBuffer(),
            0,
            structdef.size * desc.elemCount,
            0);
      }
    }
  }

  m_images.reserve(m_parsed.m_images.size());
  for (const ParsedFlr::ImageDesc& desc : m_parsed.m_images) {
    ImageResource& rsc = m_images.emplace_back();

    rsc.image = Image(*GApplication, desc.createOptions);
    bool bIsDepth = (rsc.image.getOptions().usage &
                     VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) != 0;

    ImageViewOptions viewOptions{};
    viewOptions.format = rsc.image.getOptions().format;
    viewOptions.aspectFlags =
        bIsDepth ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_COLOR_BIT;
    rsc.view = ImageView(*GApplication, rsc.image, viewOptions);

    SamplerOptions samplerOptions{};
    rsc.sampler = Sampler(*GApplication, samplerOptions);
  }

  m_textureFiles.reserve(m_parsed.m_textureFiles.size());
  for (ParsedFlr::TextureFile& tex : m_parsed.m_textureFiles) {
    ImageResource& rsc = m_textureFiles.emplace_back();

    rsc.image = Image(
        *GApplication,
        (VkCommandBuffer)commandBuffer,
        tex.loadedImage.data,
        tex.createOptions);

    ImageViewOptions viewOptions{};
    viewOptions.format = rsc.image.getOptions().format;
    rsc.view = ImageView(*GApplication, rsc.image, viewOptions);

    SamplerOptions samplerOptions{};
    rsc.sampler = Sampler(*GApplication, samplerOptions);
  }

  m_objModels.reserve(m_parsed.m_objModels.size());
  for (const auto& m : m_parsed.m_objModels) {
    auto& obj = m_objModels.emplace_back();
    if (!SimpleObjLoader::loadObj(
            *GApplication,
            commandBuffer,
            m.path.c_str(),
            obj)) {
      m_parsed.m_failed = true;
      sprintf(m_parsed.m_errMsg, "Failed to load obj mesh %s", m.path.c_str());
      return;
    }
  }

  m_bHasDynamicData =
      !m_parsed.m_sliderUints.empty() || !m_parsed.m_sliderInts.empty() ||
      !m_parsed.m_sliderFloats.empty() || !m_parsed.m_colorPickers.empty() ||
      !m_parsed.m_checkboxes.empty();
  if (m_bHasDynamicData) {
    size_t size = 0;
    size += 16 * m_parsed.m_colorPickers.size();
    size += 4 * m_parsed.m_sliderUints.size();
    size += 4 * m_parsed.m_sliderInts.size();
    size += 4 * m_parsed.m_sliderFloats.size();
    size += 4 * m_parsed.m_checkboxes.size();
    if (size % 64) {
      size += 64 - (size % 64);
    }

    size_t offset = 0;

    m_dynamicDataBuffer.resize(size);
    for (auto& cpicker : m_parsed.m_colorPickers) {
      cpicker.pValue =
          reinterpret_cast<float*>(m_dynamicDataBuffer.data() + offset);
      cpicker.pValue[0] = cpicker.defaultValue.x;
      cpicker.pValue[1] = cpicker.defaultValue.y;
      cpicker.pValue[2] = cpicker.defaultValue.z;
      cpicker.pValue[3] = cpicker.defaultValue.w;
      offset += 16;
    }
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
        DynamicBuffer(*GApplication, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, size);
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
      m_dynamicUniforms.updateData(i, m_dynamicDataBuffer);
  }

  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_PERSPECTIVE_CAMERA)) {
    m_cameraController = CameraController(
        60.0f,
        (float)GApplication->getSwapChainExtent().width /
            (float)GApplication->getSwapChainExtent().height);
    m_perspectiveCamera = TransientUniforms<PerspectiveCamera>(*GApplication);
  }

  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_SYSTEM_AUDIO_INPUT)) {
    m_audioInput = TransientUniforms<AudioInput>(*GApplication);
  }

  DescriptorSetLayoutBuilder dsBuilder{};
  dsBuilder.addUniformBufferBinding();
  for (const auto& b : m_buffers) {
    if (b.size() == 1)
      dsBuilder.addStorageBufferBinding(VK_SHADER_STAGE_ALL);
    else
      dsBuilder.addBufferHeapBinding(b.size(), VK_SHADER_STAGE_ALL);
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

  m_descriptorSets = PerFrameResources(*GApplication, dsBuilder);

  struct HeapBinder {
    std::vector<VkDescriptorBufferInfo> bufferInfos;
    const std::vector<VkDescriptorBufferInfo>& getBufferInfos() const {
      return bufferInfos;
    }
  };
  std::vector<HeapBinder> heapBinders;

  // resource declarations
  {
    ResourcesAssignment assign = m_descriptorSets.assign();
    assign.bindTransientUniforms(flrUniforms);

    for (int i = 0; i < m_buffers.size(); ++i) {
      const auto& parsedBuf = m_parsed.m_buffers[i];
      const auto& structdef = m_parsed.m_structDefs[parsedBuf.structIdx];
      const auto& bufCollection = m_buffers[i];

      if (parsedBuf.bufferCount == 1) {
        assign.bindStorageBuffer(
            bufCollection[0],
            structdef.size * parsedBuf.elemCount,
            false);
      } else {
        auto& binder = heapBinders.emplace_back();
        binder.bufferInfos.reserve(parsedBuf.bufferCount);
        for (auto& buf : bufCollection) {
          VkDescriptorBufferInfo& info = binder.bufferInfos.emplace_back();
          info.buffer = buf.getBuffer();
          info.offset = 0;
          info.range = structdef.size * parsedBuf.elemCount;
        }

        assign.bindBufferHeap(binder);
      }
    }

    for (int i = 0; i < m_images.size(); ++i) {
      const auto& desc = m_parsed.m_images[i];
      const auto& rsc = m_images[i];

      if ((desc.createOptions.usage & VK_IMAGE_USAGE_STORAGE_BIT) == 0)
        continue;

      assign.bindStorageImage(rsc.view, rsc.sampler);
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
    }

    if (m_bHasDynamicData)
      assign.bindTransientUniforms(m_dynamicUniforms);

    if (m_parsed.isFeatureEnabled(ParsedFlr::FF_PERSPECTIVE_CAMERA))
      assign.bindTransientUniforms(m_perspectiveCamera);

    if (m_parsed.isFeatureEnabled(ParsedFlr::FF_SYSTEM_AUDIO_INPUT))
      assign.bindTransientUniforms(m_audioInput);
  }

  std::filesystem::path autoGenFileName = m_projPath;
  if (m_parsed.m_language == SHADER_LANGUAGE_GLSL) {
    autoGenFileName.replace_extension(".gen.glsl");
    codeGenGlsl(autoGenFileName);
  } else {
    autoGenFileName.replace_extension(".gen.hlsl");
    codeGenHlsl(autoGenFileName);
  }

  m_computePipelines.reserve(m_parsed.m_computeShaders.size());
  for (const auto& c : m_parsed.m_computeShaders) {
    ShaderDefines defs{};
    defs.emplace("IS_COMP_SHADER", "");
    if (m_parsed.m_language == SHADER_LANGUAGE_HLSL) {
      /* char buf[128];
       sprintf(buf, "__hack(){}\n[numthreads(%u,%u,%u)]\nvoid main", c.groupSizeX, c.groupSizeY, c.groupSizeZ);
       defs.emplace(c.name, std::string(buf));*/
      defs.emplace(c.name, "main");
    }
    defs.emplace(std::string("_ENTRY_POINT_") + c.name, "");

    ComputePipelineBuilder builder{};
    builder.setComputeShader(
        autoGenFileName.string(),
        defs,
        m_parsed.m_language);
    builder.layoutBuilder
        .addDescriptorSet(GGlobalHeap->getDescriptorSetLayout())
        .addDescriptorSet(m_descriptorSets.getLayout())
        .addPushConstants<GenericPush>(VK_SHADER_STAGE_COMPUTE_BIT);

    {
      std::string errors = builder.compileShadersGetErrors();
      if (errors.size()) {
        m_parsed.m_failed = true;
        strncpy(m_parsed.m_errMsg, errors.c_str(), errors.size());
        return;
      }
    }

    m_computePipelines.emplace_back(*GApplication, std::move(builder));
  }

  m_drawPasses.reserve(m_parsed.m_renderPasses.size());
  for (const auto& pass : m_parsed.m_renderPasses) {
    std::vector<SubpassBuilder> subpassBuilders;
    subpassBuilders.reserve(pass.draws.size());

    VkClearValue colorClear;
    colorClear.color = {{0.0f, 0.0f, 0.0f, 0.0f}};
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
      subpass.pipelineBuilder.setPrimitiveType(draw.primType);
      subpass.pipelineBuilder.setLineWidth(draw.lineWidth);

      GraphicsPipelineBuilder& builder = subpass.pipelineBuilder;

      if (!draw.bDisableDepth && depthAttachment)
        subpass.depthAttachment = *depthAttachment;
      else
        builder.setDepthTesting(false);

      if (draw.bDisableBackfaceCull)
        subpass.pipelineBuilder.setCullMode(VK_CULL_MODE_NONE);

      if (draw.drawMode == ParsedFlr::DM_DRAW_OBJ) {
        assert(draw.param0 >= 0);
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
        if (m_parsed.m_language == SHADER_LANGUAGE_HLSL)
          defs.emplace(draw.vertexShader, "main");
        defs.emplace(pass.name, "");
        builder.addVertexShader(
            autoGenFileName.string(),
            defs,
            m_parsed.m_language);
      }
      {
        ShaderDefines defs{};
        defs.emplace("IS_PIXEL_SHADER", "");
        defs.emplace(std::string("_ENTRY_POINT_") + draw.pixelShader, "");
        defs.emplace(pass.name, "");
        builder.addFragmentShader(
            autoGenFileName.string(),
            defs,
            m_parsed.m_language);
      }

      {
        std::string errors = builder.compileShadersGetErrors();
        if (errors.size()) {
          m_parsed.m_failed = true;
          strncpy(m_parsed.m_errMsg, errors.c_str(), errors.size());
          return;
        }
      }

      builder.layoutBuilder
          .addDescriptorSet(GGlobalHeap->getDescriptorSetLayout())
          .addDescriptorSet(m_descriptorSets.getLayout())
          .addPushConstants<GenericPush>();
    }

    DrawPass& drawPass = m_drawPasses.emplace_back();
    drawPass.m_renderPass = RenderPass(
        *GApplication,
        {(uint32_t)pass.width, (uint32_t)pass.height},
        std::move(attachments),
        std::move(subpassBuilders));

    drawPass.m_frameBuffer = FrameBuffer(
        *GApplication,
        drawPass.m_renderPass,
        {(uint32_t)pass.width, (uint32_t)pass.height},
        std::move(attachmentViews));
  }

  m_images[m_parsed.m_displayImageIdx].registerToTextureHeap(*GGlobalHeap);

  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_SYSTEM_AUDIO_INPUT)) {
    m_pAudio = std::make_unique<Audio>(true);
  }

  loadOptions();

  GInputManager->setMouseCursorHidden(true);
}

Project::~Project() {
  if (isReady()) {
    serializeOptions();
  }
}

void Project::tick(const FrameContext& frame) {
  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_SYSTEM_AUDIO_INPUT)) {
    AudioInput audioInput;
    m_pAudio->play();
    m_pAudio->copySamples(&audioInput.packedSamples[0][0], 512 * 4);
    // Audio::DCT2_naive(&audioInput.packedCoeffs[0][0],
    // &audioInput.packedSamples[0][0], 512 * 4);
    m_pAudio->DCT2_naive(&audioInput.packedCoeffs[0][0], 512 * 4);

    m_audioInput.updateUniforms(audioInput, frame);
  }

  if (m_bHasDynamicData) {
    if (!GInputManager->getMouseCursorHidden()) {
      if (ImGui::Begin("Options", false)) {
        char nameBuf[128];

        int highestLayerOpen = 0;
        int currentLayer = 0;

        for (const auto& ui : m_parsed.m_uiElements) {
          if (ui.type == ParsedFlr::UET_DROPDOWN_START) {
            const auto& name = m_parsed.m_genericNamedElements[ui.idx].name;
            if (highestLayerOpen == currentLayer &&
                ImGui::CollapsingHeader(name.c_str()))
              highestLayerOpen++;
            currentLayer++;
          } else if (ui.type == ParsedFlr::UET_DROPDOWN_END) {
            if (highestLayerOpen == currentLayer)
              highestLayerOpen--;
            currentLayer--;
          }

          if (currentLayer > highestLayerOpen)
            continue;

          switch (ui.type) {
          case ParsedFlr::UET_SLIDER_UINT: {
            const auto& uslider = m_parsed.m_sliderUints[ui.idx];
            ImGui::Text(uslider.name.c_str());
            sprintf(nameBuf, "##%s_%u", uslider.name.c_str(), ui.idx);
            int v = static_cast<int>(*uslider.pValue);
            if (ImGui::SliderInt(nameBuf, &v, uslider.min, uslider.max)) {
              *uslider.pValue = static_cast<uint32_t>(v);
            }
            break;
          }
          case ParsedFlr::UET_SLIDER_INT: {
            const auto& islider = m_parsed.m_sliderInts[ui.idx];
            ImGui::Text(islider.name.c_str());
            sprintf(nameBuf, "##%s_%u", islider.name.c_str(), ui.idx);
            ImGui::SliderInt(nameBuf, islider.pValue, islider.min, islider.max);
            break;
          }
          case ParsedFlr::UET_SLIDER_FLOAT: {
            const auto& fslider = m_parsed.m_sliderFloats[ui.idx];
            ImGui::Text(fslider.name.c_str());
            sprintf(nameBuf, "##%s_%u", fslider.name.c_str(), ui.idx);
            ImGui::SliderFloat(
                nameBuf,
                fslider.pValue,
                fslider.min,
                fslider.max);
            break;
          }
          case ParsedFlr::UET_COLOR_PICKER: {
            const auto& cpicker = m_parsed.m_colorPickers[ui.idx];
            ImGui::Text(cpicker.name.c_str());
            sprintf(nameBuf, "##%s_%u", cpicker.name.c_str(), ui.idx);
            ImGui::ColorPicker4(nameBuf, cpicker.pValue);
            break;
          }
          case ParsedFlr::UET_CHECKBOX: {
            const auto& checkbox = m_parsed.m_checkboxes[ui.idx];
            ImGui::Text(checkbox.name.c_str());
            sprintf(nameBuf, "##%s_%u", checkbox.name.c_str(), ui.idx);
            bool bValue = (bool)*checkbox.pValue;
            if (ImGui::Checkbox(nameBuf, &bValue))
              *checkbox.pValue = (uint32_t)bValue;
            break;
          }
          case ParsedFlr::UET_SAVE_IMAGE_BUTTON: {
            const auto& saveImageButton = m_parsed.m_saveImageButtons[ui.idx];
            char buf[256];
            sprintf(
                buf,
                "Save PNG: %s",
                m_parsed.m_images[saveImageButton.imageIdx].name.c_str());
            if (ImGui::Button(buf)) {
              OPENFILENAME ofn{};
              memset(&ofn, 0, sizeof(OPENFILENAME));

              char filename[512] = {0};

              ofn.lStructSize = sizeof(ofn);
              ofn.hwndOwner = glfwGetWin32Window(GApplication->getWindow());
              ofn.lpstrFile = filename;
              ofn.lpstrFile[0] = '\0';
              ofn.nMaxFile = sizeof(filename);
              ofn.lpstrFilter = "PNG\0*.png\0\0";
              ofn.nFilterIndex = 1;
              ofn.lpstrFileTitle = NULL;
              ofn.nMaxFileTitle = 0;
              ofn.lpstrInitialDir = NULL;
              ofn.Flags = OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;

              if (GetSaveFileName(&ofn)) {
                m_pendingSaveImage = {
                    std::string(filename),
                    saveImageButton.imageIdx};
              }
            }

            break;
          }
          case ParsedFlr::UET_SAVE_BUFFER_BUTTON: {
            const auto& saveBufferButton = m_parsed.m_saveBufferButtons[ui.idx];
            char buf[256];
            sprintf(
                buf,
                "Save Buffer: %s",
                m_parsed.m_buffers[saveBufferButton.bufferIdx].name.c_str());
            if (ImGui::Button(buf)) {
              OPENFILENAME ofn{};
              memset(&ofn, 0, sizeof(OPENFILENAME));

              char filename[512] = {0};

              ofn.lStructSize = sizeof(ofn);
              ofn.hwndOwner = glfwGetWin32Window(GApplication->getWindow());
              ofn.lpstrFile = filename;
              ofn.lpstrFile[0] = '\0';
              ofn.nMaxFile = sizeof(filename);
              ofn.lpstrFilter = "BIN\0*.bin\0\0";
              ofn.nFilterIndex = 1;
              ofn.lpstrFileTitle = NULL;
              ofn.nMaxFileTitle = 0;
              ofn.lpstrInitialDir = NULL;
              ofn.Flags = OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;

              if (GetSaveFileName(&ofn)) {
                m_pendingSaveBuffer = {
                    std::string(filename),
                    saveBufferButton.bufferIdx};
              }
            }

            break;
          }
          case ParsedFlr::UET_TASK_BUTTON: {
            const auto& taskButton = m_parsed.m_taskButtons[ui.idx];

            char buf[256];
            sprintf(
                buf,
                "Run Task: %s",
                m_parsed.m_taskBlocks[taskButton.taskBlockIdx].name.c_str());
            if (ImGui::Button(buf))
              m_pendingTaskBlockExecs.push_back(taskButton.taskBlockIdx);

            break;
          }
          case ParsedFlr::UET_SEPARATOR: {
            ImGui::Separator();
            break;
          }

            // already handled
          case ParsedFlr::UET_DROPDOWN_START:
          case ParsedFlr::UET_DROPDOWN_END:
            break;
          };
        }
      }

      ImGui::End();
    }

    m_dynamicUniforms.updateData(
        frame.frameRingBufferIndex,
        m_dynamicDataBuffer);
  }

  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_PERSPECTIVE_CAMERA)) {
    m_cameraController.tick(frame.deltaTime);
    m_cameraArgs.prevView = m_cameraArgs.view;
    m_cameraArgs.prevInverseView = m_cameraArgs.inverseView;
    m_cameraArgs.view = m_cameraController.getCamera().computeView();
    m_cameraArgs.inverseView = glm::inverse(m_cameraArgs.view);
    m_cameraArgs.projection = m_cameraController.getCamera().getProjection();
    m_cameraArgs.inverseProjection = glm::inverse(m_cameraArgs.projection);
    m_perspectiveCamera.updateUniforms(m_cameraArgs, frame);
  }
}

void Project::dispatch(
    ComputeShaderId compShader,
    uint32_t groupCountX,
    uint32_t groupCountY,
    uint32_t groupCountZ,
    VkCommandBuffer commandBuffer,
    const FrameContext& frame) const {
  assert(compShader.isValid());

  VkDescriptorSet sets[] = {
      GGlobalHeap->getDescriptorSet(),
      m_descriptorSets.getCurrentDescriptorSet(frame)};

  const ComputePipeline& c = m_computePipelines[compShader.idx];
  c.bindPipeline(commandBuffer);
  c.bindDescriptorSets(commandBuffer, sets, 2);
  c.setPushConstants(commandBuffer, m_pushData);

  vkCmdDispatch(commandBuffer, groupCountX, groupCountY, groupCountZ);
}

void Project::dispatchThreads(
    ComputeShaderId compShader,
    uint32_t threadCountX,
    uint32_t threadCountY,
    uint32_t threadCountZ,
    VkCommandBuffer commandBuffer,
    const FrameContext& frame) const {
  assert(compShader.isValid());

  VkDescriptorSet sets[] = {
      GGlobalHeap->getDescriptorSet(),
      m_descriptorSets.getCurrentDescriptorSet(frame)};

  const auto& csInfo = m_parsed.m_computeShaders[compShader.idx];
  const ComputePipeline& c = m_computePipelines[compShader.idx];
  c.bindPipeline(commandBuffer);
  c.bindDescriptorSets(commandBuffer, sets, 2);
  c.setPushConstants(commandBuffer, m_pushData);

  uint32_t groupCountX =
      (threadCountX + csInfo.groupSizeX - 1) / csInfo.groupSizeX;
  uint32_t groupCountY =
      (threadCountY + csInfo.groupSizeY - 1) / csInfo.groupSizeY;
  uint32_t groupCountZ =
      (threadCountZ + csInfo.groupSizeZ - 1) / csInfo.groupSizeZ;
  vkCmdDispatch(commandBuffer, groupCountX, groupCountY, groupCountZ);
}

void Project::executeTaskBlock(
    TaskBlockId id,
    VkCommandBuffer commandBuffer,
    const FrameContext& frame) {
  executeTaskList(m_parsed.m_taskBlocks[id.idx].tasks, commandBuffer, frame);
}

void Project::executeTaskList(
    const std::vector<ParsedFlr::Task>& tasks,
    VkCommandBuffer commandBuffer,
    const FrameContext& frame) {
  VkDescriptorSet sets[] = {
      GGlobalHeap->getDescriptorSet(),
      m_descriptorSets.getCurrentDescriptorSet(frame)};

  for (const auto& task : tasks) {
    switch (task.type) {
    case ParsedFlr::TT_COMPUTE: {
      const auto& dispatch = m_parsed.m_computeDispatches[task.idx];
      const auto& compute =
          m_parsed.m_computeShaders[dispatch.computeShaderIndex];
      ComputePipeline& c = m_computePipelines[dispatch.computeShaderIndex];
      c.bindPipeline(commandBuffer);
      c.bindDescriptorSets(commandBuffer, sets, 2);
      c.setPushConstants(commandBuffer, m_pushData);

      if (dispatch.mode == ParsedFlr::DM_INDIRECT) {
        vkCmdDispatchIndirect(
            commandBuffer,
            m_buffers[dispatch.param0][0].getBuffer(),
            12 * dispatch.param1);
      } else {
        uint32_t groupCountX, groupCountY, groupCountZ;
        if (dispatch.mode == ParsedFlr::DM_THREADS) {
          groupCountX =
              (dispatch.param0 + compute.groupSizeX - 1) / compute.groupSizeX;
          groupCountY =
              (dispatch.param1 + compute.groupSizeY - 1) / compute.groupSizeY;
          groupCountZ =
              (dispatch.param2 + compute.groupSizeZ - 1) / compute.groupSizeZ;
        } else {
          groupCountX = dispatch.param0;
          groupCountY = dispatch.param1;
          groupCountZ = dispatch.param2;
        }

        vkCmdDispatch(commandBuffer, groupCountX, groupCountY, groupCountZ);
      }
      break;
    }

    case ParsedFlr::TT_BARRIER: {
      const auto& parsedBarrier = m_parsed.m_barriers[task.idx];
      VkAccessFlags dstAccess = parsedBarrier.accessFlags;
      for (uint32_t bufferIdx : parsedBarrier.buffers) {
        const auto& parsedBuf = m_parsed.m_buffers[bufferIdx];
        const auto& parsedStruct = m_parsed.m_structDefs[parsedBuf.structIdx];
        VkAccessFlags srcAccess = m_bufferResourceStates[bufferIdx];
        for (const auto& buf : m_buffers[bufferIdx]) {
          VkBufferMemoryBarrier barrier{};
          barrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
          barrier.buffer = buf.getBuffer();
          barrier.offset = 0;
          barrier.size = parsedBuf.elemCount * parsedStruct.size;
          barrier.srcAccessMask = srcAccess;
          barrier.dstAccessMask = dstAccess;

          vkCmdPipelineBarrier(
              commandBuffer,
              VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT,
              VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT,
              0,
              0,
              nullptr,
              1,
              &barrier,
              0,
              nullptr);
        }
        m_bufferResourceStates[bufferIdx] = dstAccess;
      }
      break;
    }

    case ParsedFlr::TT_RENDER: {
      const auto& passDesc = m_parsed.m_renderPasses[task.idx];
      auto& drawPass = m_drawPasses[task.idx];

      {
        ActiveRenderPass pass = drawPass.m_renderPass.begin(
            *GApplication,
            commandBuffer,
            frame,
            drawPass.m_frameBuffer);
        pass.setGlobalDescriptorSets(gsl::span(sets, 2));
        pass.getDrawContext().bindDescriptorSets();
        pass.getDrawContext().updatePushConstants(m_pushData, 0);
        for (const auto& draw : m_parsed.m_renderPasses[task.idx].draws) {
          switch (draw.drawMode) {
          case ParsedFlr::DM_DRAW: {
            pass.getDrawContext().draw(draw.param0, draw.param1);
            break;
          }
          case ParsedFlr::DM_DRAW_INDEXED: {
            const auto& b = m_buffers[draw.param1][draw.param2];
            uint32_t indexCount = m_parsed.m_buffers[draw.param1].elemCount;
            vkCmdBindIndexBuffer(
                commandBuffer,
                b.getBuffer(),
                0,
                VK_INDEX_TYPE_UINT32);
            vkCmdDrawIndexed(commandBuffer, indexCount, draw.param0, 0, 0, 0);
            break;
          }
          case ParsedFlr::DM_DRAW_INDIRECT: {
            const auto& b = m_buffers[draw.param0];
            assert(b.size() == 1);
            vkCmdDrawIndirect(
                commandBuffer,
                b[draw.param2].getBuffer(),
                0,
                draw.param1,
                16);
            break;
          }
          case ParsedFlr::DM_DRAW_OBJ: {
            SimpleObjLoader::LoadedObj& obj = m_objModels[draw.param0];
            for (SimpleObjLoader::ObjMesh& mesh : obj.m_meshes) {
              pass.getDrawContext().bindIndexBuffer(mesh.m_indices);
              pass.getDrawContext().bindVertexBuffer(obj.m_vertices);
              pass.getDrawContext().drawIndexed(
                  mesh.m_indices.getIndexCount(),
                  1);
            }
            break;
          }
          };

          if (!pass.isLastSubpass())
            pass.nextSubpass();
        }
      }

      for (const auto& attachmentRef : passDesc.attachments)
        m_images[attachmentRef.imageIdx].image.clearLayout();

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

    case ParsedFlr::TT_TASK: {
      // TODO: would be nice to handle this without recursion, but this should
      // be safe since it is validated during parsing
      executeTaskBlock(TaskBlockId(task.idx), commandBuffer, frame);
      break;
    }
    };
  }
}

void Project::draw(VkCommandBuffer commandBuffer, const FrameContext& frame) {

  if (m_pendingSaveImage) {
    auto& img = m_images[m_pendingSaveImage->imageIdx].image;
    // TODO: assumes r8g8b8a8_unorm, generalize
    uint32_t width = img.getOptions().width;
    uint32_t height = img.getOptions().height;
    size_t byteSize = width * height * 4;
    BufferAllocation* pStaging = new BufferAllocation(
        BufferUtilities::createStagingBufferForDownload(byteSize));

    img.copyMipToBuffer(commandBuffer, pStaging->getBuffer(), 0, 0);
    img.transitionLayout(
        commandBuffer,
        VK_IMAGE_LAYOUT_GENERAL,
        VK_ACCESS_NONE,
        VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT);

    GApplication->addDeletiontask(
        {[pStaging,
          width,
          height,
          byteSize,
          fileName = m_pendingSaveImage->m_saveFileName]() {
           const std::byte* mapped =
               reinterpret_cast<const std::byte*>(pStaging->mapMemory());
           Utilities::savePng(
               fileName,
               width,
               height,
               gsl::span(mapped, byteSize));
           pStaging->unmapMemory();
           delete pStaging;
         },
         GApplication->getCurrentFrameRingBufferIndex()});

    m_pendingSaveImage = std::nullopt;
  }

  if (m_pendingSaveBuffer) {
    auto& buf = m_buffers[m_pendingSaveBuffer->bufferIdx];
    // TODO support saving buffer heap...
    assert(buf.size() == 0);
    // TODO:
    // TODO: assumes r8g8b8a8_unorm, generalize
    const auto& desc = m_parsed.m_buffers[m_pendingSaveBuffer->bufferIdx];
    const auto& s = m_parsed.m_structDefs[desc.structIdx];
    size_t byteSize = s.size * desc.elemCount;
    BufferAllocation* pStaging = new BufferAllocation(
        BufferUtilities::createStagingBufferForDownload(byteSize));

    VkBufferCopy2 region{};
    region.sType = VK_STRUCTURE_TYPE_BUFFER_COPY_2;
    region.dstOffset = 0;
    region.srcOffset = 0;
    region.size = byteSize;
    region.pNext = nullptr;

    VkCopyBufferInfo2 copy{};
    copy.sType = VK_STRUCTURE_TYPE_COPY_BUFFER_INFO_2;
    copy.dstBuffer = pStaging->getBuffer();
    copy.srcBuffer = buf[0].getBuffer();
    copy.pRegions = &region;
    copy.regionCount = 1;
    copy.pNext = nullptr;

    // TODO: barrier src ...
    vkCmdCopyBuffer2(commandBuffer, &copy);

    // TODO: barrier dst ...

    GApplication->addDeletiontask(
        {[pStaging, byteSize, fileName = m_pendingSaveImage->m_saveFileName]() {
           void* pMapped = pStaging->mapMemory();
           Utilities::writeFile(
               fileName,
               gsl::span((const char*)pMapped, byteSize));
           pStaging->unmapMemory();
           delete pStaging;
         },
         GApplication->getCurrentFrameRingBufferIndex()});

    m_pendingSaveBuffer = std::nullopt;
  }

  if (m_bFirstDraw) {
    if (m_parsed.m_initializationTaskIdx >= 0)
      executeTaskBlock(
          TaskBlockId(m_parsed.m_initializationTaskIdx),
          commandBuffer,
          frame);
    m_bFirstDraw = false;
  }

  for (uint32_t taskBlockIdx : m_pendingTaskBlockExecs)
    executeTaskBlock(TaskBlockId(taskBlockIdx), commandBuffer, frame);
  m_pendingTaskBlockExecs.clear();

  executeTaskList(m_parsed.m_taskList, commandBuffer, frame);
}

void Project::tryRecompile() {
  m_failedShaderCompile = false;
  *m_shaderCompileErrMsg = 0;

  std::string error;
  for (auto& c : m_computePipelines) {
    c.tryRecompile(*GApplication);
    if (c.hasShaderRecompileErrors()) {
      error += c.getShaderRecompileErrors() + "\n";
    }
  }

  for (auto& p : m_drawPasses) {
    p.m_renderPass.tryRecompile(*GApplication);
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

namespace OptionsParserImpl {
enum OptionType : uint32_t {
  OT_CAMERA = 0,
  OT_SLIDER_UINT,
  OT_SLIDER_INT,
  OT_SLIDER_FLOAT,
  OT_COLOR_PICKER,
  OT_CHECKBOX,
  OT_COUNT
};
static constexpr const char* OPTION_PARSER_TOKEN_STRS[OT_COUNT] = {
    "camera",
    "slider_uint",
    "slider_int",
    "slider_float",
    "color_picker",
    "checkbox"};
} // namespace OptionsParserImpl

void Project::loadOptions() {
  // TODO make this parser error tolerant...

  using namespace OptionsParserImpl;

  // TODO fix
  std::filesystem::path optionsPath = m_projPath;
  optionsPath.replace_filename("Options");
  optionsPath.replace_extension(".ini");

  std::ifstream stream(optionsPath);
  char nameBuf[256];
  char linebuf[1024];
  while (stream.getline(linebuf, 1024)) {
    Parser p{linebuf};

    auto parseToken = [&]() {
      return p.parseToken<OptionType>(OPTION_PARSER_TOKEN_STRS, OT_COUNT);
    };
    auto parseName = [&]() {
      auto name = p.parseName();
      snprintf(
          nameBuf,
          256,
          "%.*s",
          static_cast<uint32_t>(name->size()),
          name->data());
    };

    p.parseWhitespace();
    if (auto uiType = parseToken()) {
      p.parseWhitespace();
      switch (*uiType) {
      case OT_CAMERA: {
        glm::vec3 pos;
        pos.x = *p.parseFloat();
        p.parseWhitespace();
        pos.y = *p.parseFloat();
        p.parseWhitespace();
        pos.z = *p.parseFloat();
        p.parseWhitespace();
        float yaw = *p.parseFloat();
        p.parseWhitespace();
        float pitch = *p.parseFloat();
        p.parseWhitespace();
        m_cameraController.setPosition(pos);
        m_cameraController.resetRotation(yaw, pitch);
        break;
      }
      case OT_SLIDER_UINT: {
        parseName();
        p.parseWhitespace();
        auto val = *p.parseUint();
        if (auto view = getSliderUint(nameBuf))
          *view = val;
        p.parseWhitespace();
        break;
      }
      case OT_SLIDER_INT: {
        parseName();
        p.parseWhitespace();
        auto val = *p.parseInt();
        if (auto view = getSliderInt(nameBuf))
          *view = val;
        p.parseWhitespace();
        break;
      }
      case OT_SLIDER_FLOAT: {
        parseName();
        p.parseWhitespace();
        auto val = *p.parseFloat();
        if (auto view = getSliderFloat(nameBuf))
          *view = val;
        p.parseWhitespace();
        break;
      }
      case OT_COLOR_PICKER: {
        parseName();
        p.parseWhitespace();
        glm::vec4 val;
        for (int i = 0; i < 4; i++) {
          val[i] = *p.parseFloat();
          p.parseWhitespace();
        }
        if (auto view = getColorPicker(nameBuf))
          *view = val;
        break;
      }
      case OT_CHECKBOX: {
        parseName();
        p.parseWhitespace();
        auto val = *p.parseUint() != 0u;
        if (auto view = getCheckBox(nameBuf))
          *view = val;
        p.parseWhitespace();
        break;
      }
      }
    }

    // unexpected token
    assert(p.parseChar(0));
  }

  stream.close();
}

void Project::codeGenGlsl(const std::filesystem::path& autoGenFileName) {
  assert(m_parsed.m_language == SHADER_LANGUAGE_GLSL);

  const uint32_t BUF_SIZE = 10000;
  char* codeBuf = new char[BUF_SIZE];
  size_t codeOffs = 0;
  memset(codeBuf, 0, BUF_SIZE);

#define CODE_APPEND(...)                                                       \
  codeOffs += snprintf(codeBuf + codeOffs, BUF_SIZE - codeOffs, __VA_ARGS__)

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
    if (s.body.size() > 0) // skip dummy structs
      CODE_APPEND("%s;\n\n", s.body.c_str());
  }

  // resource declarations
  uint32_t slot = 0;
  {
    slot++;

    for (int i = 0; i < m_buffers.size(); ++i) {
      const auto& parsedBuf = m_parsed.m_buffers[i];
      const auto& structdef = m_parsed.m_structDefs[parsedBuf.structIdx];

      if (parsedBuf.bufferCount == 1) {
        CODE_APPEND(
            "layout(set=1,binding=%u) buffer BUFFER_%s {  %s %s[]; };\n",
            slot++,
            parsedBuf.name.c_str(),
            structdef.name.c_str(),
            parsedBuf.name.c_str());
      } else {
        CODE_APPEND(
            "layout(set=1,binding=%u) buffer BUFFER_%s {  %s _INNER_%s[]; } "
            "_HEAP_%s [%u];\n",
            slot++,
            parsedBuf.name.c_str(),
            structdef.name.c_str(),
            parsedBuf.name.c_str(),
            parsedBuf.name.c_str(),
            parsedBuf.bufferCount);
        CODE_APPEND(
            "#define %s(IDX) _HEAP_%s[IDX]._INNER_%s\n",
            parsedBuf.name.c_str(),
            parsedBuf.name.c_str(),
            parsedBuf.name.c_str());
      }
    }

    for (int i = 0; i < m_images.size(); ++i) {
      const auto& desc = m_parsed.m_images[i];
      if ((desc.createOptions.usage & VK_IMAGE_USAGE_STORAGE_BIT) == 0)
        continue;

      CODE_APPEND(
          "layout(set=1,binding=%u, %s) uniform image2D %s;\n",
          slot++,
          desc.format.c_str(),
          desc.name.c_str());
    }

    for (int i = 0; i < m_parsed.m_textures.size(); ++i) {
      const auto& txDesc = m_parsed.m_textures[i];
      assert(txDesc.imageIdx >= 0 || txDesc.texFileIdx >= 0);
      CODE_APPEND(
          "layout(set=1,binding=%u) uniform sampler2D %s;\n",
          slot++,
          txDesc.name.c_str());
    }

    if (m_bHasDynamicData) {
      CODE_APPEND(
          "\nlayout(set=1, binding=%u) uniform _UserUniforms {\n",
          slot++);

      for (const auto& cpicker : m_parsed.m_colorPickers) {
        CODE_APPEND("\tvec4 %s;\n", cpicker.name.c_str());
      }
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
  }

  // includes
  CODE_APPEND("#include <FlrLib/Fluorescence.glsl>\n\n");

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
        CODE_APPEND(
            "#if defined(_ENTRY_POINT_%s) && "
            "!defined(_ENTRY_POINT_%s_ATTACHMENTS)\n",
            draw.pixelShader.c_str(),
            draw.pixelShader.c_str());
        CODE_APPEND(
            "#define _ENTRY_POINT_%s_ATTACHMENTS\n",
            draw.pixelShader.c_str());
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

  std::filesystem::path shaderFileName = m_projPath;
  shaderFileName.replace_extension(".glsl");

  std::string userShaderName = shaderFileName.filename().string();
  CODE_APPEND("#include \"%s\"\n\n", userShaderName.c_str());

  // auto-gen compute shader block, post-include of user-file
  {
    CODE_APPEND("#ifdef IS_COMP_SHADER\n");
    for (const auto& c : m_parsed.m_computeShaders) {
      CODE_APPEND("#ifdef _ENTRY_POINT_%s\n", c.name.c_str());
      if (c.groupSizeX > 0 && c.groupSizeY > 0 && c.groupSizeZ > 0) {
        CODE_APPEND(
            "layout(local_size_x = %u, local_size_y = %u, local_size_z = %u) "
            "in;\n",
            c.groupSizeX,
            c.groupSizeY,
            c.groupSizeZ);
        CODE_APPEND("void main() { %s(); }\n", c.name.c_str());
      } else {
        CODE_APPEND("#define %s main\n", c.name.c_str());
      }
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
        CODE_APPEND(
            "#if defined(_ENTRY_POINT_%s) && "
            "!defined(_ENTRY_POINT_%s_INTERPOLANTS)\n",
            draw.pixelShader.c_str(),
            draw.pixelShader.c_str());
        CODE_APPEND(
            "#define _ENTRY_POINT_%s_INTERPOLANTS\n",
            draw.pixelShader.c_str());

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

  std::ofstream autoGenFile(autoGenFileName);
  if (autoGenFile.is_open()) {
    autoGenFile.write(codeBuf, codeOffs);
    autoGenFile.close();
  }

  delete[] codeBuf;
}

void Project::codeGenHlsl(const std::filesystem::path& autoGenFileName) {
  assert(m_parsed.m_language == SHADER_LANGUAGE_HLSL);

  const uint32_t BUF_SIZE = 10000;
  char* codeBuf = new char[BUF_SIZE];
  size_t codeOffs = 0;
  memset(codeBuf, 0, BUF_SIZE);

#define CODE_APPEND(...)                                                       \
  codeOffs += snprintf(codeBuf + codeOffs, BUF_SIZE - codeOffs, __VA_ARGS__)

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
    if (s.body.size() > 0) // skip dummy structs
      CODE_APPEND("%s;\n\n", s.body.c_str());
  }

  // resource declarations
  uint32_t slot = 0;
  {
    slot++;

    for (int i = 0; i < m_buffers.size(); ++i) {
      const auto& parsedBuf = m_parsed.m_buffers[i];
      const auto& structdef = m_parsed.m_structDefs[parsedBuf.structIdx];

      if (parsedBuf.bufferCount == 1) {
        CODE_APPEND(
            "[[vk::binding(%u, 1)]] RWStructuredBuffer<%s> %s;\n",
            slot++,
            structdef.name.c_str(),
            parsedBuf.name.c_str());
      } else {
        assert(false); // TODO impl support for buffer heaps...
        /*  CODE_APPEND(
            "layout(set=1,binding=%u) buffer BUFFER_%s {  %s _INNER_%s[]; } _HEAP_%s [%u];\n",
            slot++,
            parsedBuf.name.c_str(),
            structdef.name.c_str(),
            parsedBuf.name.c_str(),
            parsedBuf.name.c_str(),
            parsedBuf.bufferCount);
          CODE_APPEND(
            "#define %s(IDX) _HEAP_%s[IDX]._INNER_%s\n",
            parsedBuf.name.c_str(),
            parsedBuf.name.c_str(),
            parsedBuf.name.c_str());*/
      }
    }

    for (int i = 0; i < m_images.size(); ++i) {
      const auto& desc = m_parsed.m_images[i];
      if ((desc.createOptions.usage & VK_IMAGE_USAGE_STORAGE_BIT) == 0)
        continue;

      CODE_APPEND(
          "[[vk::binding(%u, 1)]] RWTexture2D<%s> %s;\n",
          slot++,
          desc.format.c_str(),
          desc.name.c_str());
    }

    for (int i = 0; i < m_parsed.m_textures.size(); ++i) {
      const auto& txDesc = m_parsed.m_textures[i];
      assert(txDesc.imageIdx >= 0 || txDesc.texFileIdx >= 0);
      CODE_APPEND(
          "[[vk::binding(%u, 1)]] Texture2D %s;\n",
          slot++,
          txDesc.name.c_str());
    }

    if (m_bHasDynamicData) {
      CODE_APPEND("\n[[vk::binding(%u, 1)]] cbuffer _UserUniforms {\n", slot++);

      for (const auto& cpicker : m_parsed.m_colorPickers) {
        CODE_APPEND("\tfloat4 %s;\n", cpicker.name.c_str());
      }
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
  }

  // TODO - both compute shader and vertex shader entry points are compiled
  // by swapping in "main" via macros
  // Would be better to use the compiler feature that does this automatically
  for (const auto& c : m_parsed.m_computeShaders) {
    CODE_APPEND("#ifdef _ENTRY_POINT_%s\n", c.name.c_str());
    CODE_APPEND("#define %s main\n", c.name.c_str());
    CODE_APPEND("#endif // _ENTRY_POINT_%s\n\n", c.name.c_str());
  }

  {
    CODE_APPEND("\n\n#ifdef IS_VERTEX_SHADER\n");
    for (const auto& pass : m_parsed.m_renderPasses) {
      for (const auto& draw : pass.draws) {
        CODE_APPEND(
            "#if defined(_ENTRY_POINT_%s) && !defined(%s)\n",
            draw.vertexShader.c_str(),
            draw.vertexShader.c_str());
        CODE_APPEND("#define %s main\n", draw.vertexShader.c_str());
        CODE_APPEND(
            "#endif // defined(_ENTRY_POINT_%s) && !defined(%s)\n\n",
            draw.vertexShader.c_str(),
            draw.vertexShader.c_str());
      }
    }
    CODE_APPEND("#endif // IS_VERTEX_SHADER\n\n");
  }

  // TODO have a special subdir for hlsl versions of FlrLib ?
  // includes
  CODE_APPEND("#include <FlrLib/Fluorescence.hlsl>\n\n");

  // camera uniforms (references included structs)
  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_PERSPECTIVE_CAMERA)) {
    CODE_APPEND(
        "[[vk::binding(%u, 1)]] cbuffer _CameraUniforms { PerspectiveCamera "
        "camera; };\n\n",
        slot++);
  }

  // audio uniforms
  if (m_parsed.isFeatureEnabled(ParsedFlr::FF_SYSTEM_AUDIO_INPUT)) {
    CODE_APPEND(
        "[[vk::binding(%u, 1)]] cbuffer _AudioUniforms { AudioInput audio; "
        "};\n\n",
        slot++);
  }

  // auto-gen pixel shader block, pre-include of user-file
  {
    CODE_APPEND("\n\n#ifdef IS_PIXEL_SHADER\n");
    for (const auto& pass : m_parsed.m_renderPasses) {
      for (const auto& attachmentRef : pass.attachments) {
        const auto& img = m_images[attachmentRef.imageIdx];
        if ((img.image.getOptions().usage &
             VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) == 0) {
          CODE_APPEND(
              "#ifndef _ATTACHMENT_VAR_%s\n",
              attachmentRef.aliasName.c_str());
          CODE_APPEND(
              "#define _ATTACHMENT_VAR_%s\n",
              attachmentRef.aliasName.c_str());
          CODE_APPEND("static float4 %s;\n", attachmentRef.aliasName.c_str());
          CODE_APPEND(
              "#endif // _ATTACHMENT_VAR_ %s\n",
              attachmentRef.aliasName.c_str());
        }
      }
    }
    CODE_APPEND("#endif // IS_PIXEL_SHADER\n");
  }

  std::filesystem::path shaderFileName = m_projPath;
  shaderFileName.replace_extension(".hlsl");

  std::string userShaderName = shaderFileName.filename().string();
  CODE_APPEND("#include \"%s\"\n\n", userShaderName.c_str());

  {
    CODE_APPEND("\n\n#ifdef IS_PIXEL_SHADER\n");
    for (const auto& pass : m_parsed.m_renderPasses) {
      for (const auto& draw : pass.draws) {
        CODE_APPEND(
            "#if defined(_ENTRY_POINT_%s) && !defined(_PS_WRAPPER)\n",
            draw.pixelShader.c_str());
        CODE_APPEND("#define _PS_WRAPPER\n");
        CODE_APPEND("struct _PixelOutput {\n");
        uint32_t colorAttachmentIdx = 0;
        for (const auto& attachmentRef : pass.attachments) {
          const auto& img = m_images[attachmentRef.imageIdx];
          if ((img.image.getOptions().usage &
               VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) == 0) {
            CODE_APPEND(
                "\tfloat4 _%s : SV_Target%u;\n",
                attachmentRef.aliasName.c_str(),
                colorAttachmentIdx++);
          }
        }
        const auto& structdef =
            m_parsed.m_structDefs[draw.vertexOutputStructIdx];
        CODE_APPEND("}; // struct _PixelOutput\n");
        CODE_APPEND("_PixelOutput main(%s IN) {\n", structdef.name.c_str());
        CODE_APPEND("\t_PixelOutput OUT;\n");
        CODE_APPEND("\t%s(IN);\n", draw.pixelShader.c_str());
        for (const auto& attachmentRef : pass.attachments) {
          const auto& img = m_images[attachmentRef.imageIdx];
          if ((img.image.getOptions().usage &
               VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) == 0) {
            CODE_APPEND(
                "\tOUT._%s = %s;\n",
                attachmentRef.aliasName.c_str(),
                attachmentRef.aliasName.c_str());
          }
        }
        CODE_APPEND("\treturn OUT;\n");
        CODE_APPEND("}\n");
        CODE_APPEND(
            "#endif // defined(_ENTRY_POINT_%s) && !defined(_PS_WRAPPER)\n",
            draw.pixelShader.c_str());
      }
    }
    CODE_APPEND("#endif // IS_PIXEL_SHADER\n");
  }
#undef CODE_APPEND

  std::ofstream autoGenFile(autoGenFileName);
  if (autoGenFile.is_open()) {
    autoGenFile.write(codeBuf, codeOffs);
    autoGenFile.close();
  }

  delete[] codeBuf;
}

void Project::serializeOptions() {
  using namespace OptionsParserImpl;

  std::filesystem::path optionsPath = m_projPath;
  // optionsPath.remove_filename();
  // if (!std::filesystem::exists(optionsPath))
  // std::filesystem::create_directory(optionsPath);
  optionsPath.replace_filename("Options");
  optionsPath.replace_extension(".ini");

  std::ofstream optionsFile(optionsPath);
  auto writeStr = [&](const char* str) { optionsFile.write(str, strlen(str)); };

  if (optionsFile.is_open()) {
    char buf[1024];

    if (m_parsed.isFeatureEnabled(ParsedFlr::FF_PERSPECTIVE_CAMERA)) {
      const Camera& cam = m_cameraController.getCamera();
      glm::vec3 pos(cam.getTransform()[3]);
      float yaw = cam.computeYawDegrees();
      float pitch = cam.computePitchDegrees();
      snprintf(
          buf,
          1024,
          "camera %f %f %f %f %f\n",
          pos.x,
          pos.y,
          pos.z,
          yaw,
          pitch);
      writeStr(buf);
    }

    for (const auto& ui : m_parsed.m_uiElements) {
      switch (ui.type) {
      case ParsedFlr::UET_SLIDER_UINT: {
        const auto& uslider = m_parsed.m_sliderUints[ui.idx];
        snprintf(
            buf,
            1024,
            "slider_uint %s %u\n",
            uslider.name.c_str(),
            *uslider.pValue);
        writeStr(buf);
        break;
      }
      case ParsedFlr::UET_SLIDER_INT: {
        const auto& islider = m_parsed.m_sliderInts[ui.idx];
        snprintf(
            buf,
            1024,
            "slider_int %s %d\n",
            islider.name.c_str(),
            *islider.pValue);
        writeStr(buf);
        break;
      }
      case ParsedFlr::UET_SLIDER_FLOAT: {
        const auto& fslider = m_parsed.m_sliderFloats[ui.idx];
        snprintf(
            buf,
            1024,
            "slider_float %s %f\n",
            fslider.name.c_str(),
            *fslider.pValue);
        writeStr(buf);
        break;
      }
      case ParsedFlr::UET_COLOR_PICKER: {
        const auto& cpicker = m_parsed.m_colorPickers[ui.idx];
        snprintf(
            buf,
            1024,
            "color_picker %s %f %f %f %f\n",
            cpicker.name.c_str(),
            cpicker.pValue[0],
            cpicker.pValue[1],
            cpicker.pValue[2],
            cpicker.pValue[3]);
        writeStr(buf);
        break;
      }
      case ParsedFlr::UET_CHECKBOX: {
        const auto& checkbox = m_parsed.m_checkboxes[ui.idx];
        snprintf(
            buf,
            1024,
            "checkbox %s %d\n",
            checkbox.name.c_str(),
            (int)*checkbox.pValue);
        writeStr(buf);
        break;
      }
      default:
        break;
      };
    }

    optionsFile.close();
  }
}

namespace {
template <typename TElem>
const TElem* getElemByName(const char* name, const std::vector<TElem>& elems) {
  size_t nsize = strlen(name);
  for (const auto& elem : elems) {
    if (nsize == elem.name.size() && !strncmp(name, elem.name.data(), nsize))
      return &elem;
  }
  return nullptr;
}

template <typename TId, typename TElem>
TId getElemIdByName(const char* name, const std::vector<TElem>& elems) {
  size_t nsize = strlen(name);
  for (uint32_t i = 0; i < elems.size(); i++) {
    const auto& elem = elems[i];
    if (nsize == elem.name.size() && !strncmp(name, elem.name.data(), nsize))
      return TId(i);
  }
  return TId();
}
} // namespace

TaskBlockId Project::findTaskBlock(const char* name) const {
  assert(!m_parsed.m_failed);
  assert(!m_failedShaderCompile);
  return getElemIdByName<TaskBlockId>(name, m_parsed.m_taskBlocks);
}

ComputeShaderId Project::findComputeShader(const char* name) const {
  assert(!m_parsed.m_failed);
  assert(!m_failedShaderCompile);
  return getElemIdByName<ComputeShaderId>(name, m_parsed.m_computeShaders);
}

FlrUiView<bool> Project::getCheckBox(const char* name) const {
  return getUiElemByName<bool>(name, m_parsed.m_checkboxes);
}
FlrUiView<float> Project::getSliderFloat(const char* name) const {
  return getUiElemByName<float>(name, m_parsed.m_sliderFloats);
}
FlrUiView<uint32_t> Project::getSliderUint(const char* name) const {
  return getUiElemByName<uint32_t>(name, m_parsed.m_sliderUints);
}
FlrUiView<int> Project::getSliderInt(const char* name) const {
  return getUiElemByName<int>(name, m_parsed.m_sliderInts);
}
FlrUiView<glm::vec4> Project::getColorPicker(const char* name) const {
  return getUiElemByName<glm::vec4>(name, m_parsed.m_colorPickers);
}

std::optional<float> Project::getConstFloat(const char* name) const {
  if (auto pElem = getElemByName(name, m_parsed.m_constFloats))
    return pElem->value;
  return std::nullopt;
}

std::optional<uint32_t> Project::getConstUint(const char* name) const {
  if (auto pElem = getElemByName(name, m_parsed.m_constUints))
    return pElem->value;
  return std::nullopt;
}

std::optional<int> Project::getConstInt(const char* name) const {
  if (auto pElem = getElemByName(name, m_parsed.m_constInts))
    return pElem->value;
  return std::nullopt;
}

BufferId Project::findBuffer(const char* name) const {
  return getElemIdByName<BufferId>(name, m_parsed.m_buffers);
}

BufferAllocation* Project::getBufferAlloc(BufferId buf, uint32_t subBufIdx) {
  assert(buf.isValid());
  assert(subBufIdx < m_buffers[buf.idx].size());
  return &m_buffers[buf.idx][subBufIdx];
}

uint32_t Project::getSubBufferCount(BufferId buf) const {
  assert(buf.isValid());
  return static_cast<uint32_t>(m_buffers[buf.idx].size());
}

void Project::barrierRW(BufferId buf, VkCommandBuffer commandBuffer) const {
  assert(buf.isValid());
  const auto& bufInfo = m_parsed.m_buffers[buf.idx];
  const auto& structInfo = m_parsed.m_structDefs[bufInfo.structIdx];
  for (const auto& buf : m_buffers[buf.idx])
    BufferUtilities::rwBarrier(
        commandBuffer,
        buf.getBuffer(),
        0,
        bufInfo.elemCount * structInfo.size);
}

void Project::setPushConstants(
    uint32_t push0,
    uint32_t push1,
    uint32_t push2,
    uint32 push3) {
  m_pushData.push0 = push0;
  m_pushData.push1 = push1;
  m_pushData.push2 = push2;
  m_pushData.push3 = push3;
}
} // namespace flr