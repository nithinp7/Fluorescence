#include "Fluorescence.h"

#include "GraphEditor/Graph.h"

#include <Althea/Application.h>
#include <Althea/Camera.h>
#include <Althea/Cubemap.h>
#include <Althea/DefaultTextures.h>
#include <Althea/DescriptorSet.h>
#include <Althea/GraphicsPipeline.h>
#include <Althea/Gui.h>
#include <Althea/InputManager.h>
#include <Althea/ModelViewProjection.h>
#include <Althea/Primitive.h>
#include <Althea/SingleTimeCommandBuffer.h>
#include <Althea/Skybox.h>
#include <Althea/Utilities.h>
#include <glm/glm.hpp>
#include <glm/gtc/constants.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <vulkan/vulkan.h>

#define GLFW_EXPOSE_NATIVE_WIN32
#include <GLFW/glfw3native.h>
#include <basetsd.h>
#include <commdlg.h>

#include <array>
#include <cstdint>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

static char s_filename[512] = {0};

using namespace AltheaEngine;

namespace flr {
Application* GApplication = nullptr;
GlobalHeap* GGlobalHeap = nullptr;

void Fluorescence::setStartupProject(const char* path) {
  strncpy(s_filename, path, 512);
  m_bReloadProject = true;
}

Fluorescence::Fluorescence(const FlrAppOptions& options)
  : m_options(options) {}

void Fluorescence::initGame(Application& app) {
  GApplication = &app;

  // TODO: need to unbind these at shutdown
  InputManager& input = app.getInputManager();
  input.setMouseCursorHidden(false);

  // Recreate any stale pipelines (shader hot-reload)
  input.addKeyBinding(
      {GLFW_KEY_R, GLFW_PRESS, GLFW_MOD_CONTROL},
      [&app, this]() {
        m_displayPass.tryRecompile(app);
        if (m_pProject) {
          if (m_pProject->hasFailed()) {
            m_bReloadProject = true;
          } else {
            m_pProject->tryRecompile();
          }
        }
      });

  input.addKeyBinding(
      {GLFW_KEY_T, GLFW_PRESS, GLFW_MOD_CONTROL},
      [&app, this]() { m_bFreezeTime = !m_bFreezeTime; });
  input.addKeyBinding(
      {GLFW_KEY_R, GLFW_PRESS, GLFW_MOD_CONTROL | GLFW_MOD_SHIFT},
      [&app, this]() {
        m_displayPass.tryRecompile(app);
        m_bReloadProject = true;
      });

  if (m_options.bStandaloneMode)
  {
    input.addKeyBinding(
      { GLFW_KEY_O, GLFW_PRESS, GLFW_MOD_CONTROL },
      [&app, this]() { m_bOpenFileDialogue = true; });
  }
  input.addKeyBinding({GLFW_KEY_P, GLFW_PRESS, 0}, [&app, this]() {
    m_bPaused = !m_bPaused;
  });
}

void Fluorescence::shutdownGame(Application& app) {}

void Fluorescence::createRenderState(Application& app) {
  Gui::createRenderState(app);

  SingleTimeCommandBuffer commandBuffer(app);
  _createGlobalResources(app, commandBuffer);
  _createDisplayPass(app);

  if (m_pProject)
    for (auto& program : m_programs)
      program->createRenderState(m_pProject, commandBuffer);
}

void Fluorescence::destroyRenderState(Application& app) {
  Gui::destroyRenderState(app);

  for (auto& program : m_programs)
    program->destroyRenderState();

  m_descriptorSets = {};

  delete m_pProject;
  m_pProject = nullptr;
  m_bReloadProject = true;

  m_displayPass = {};
  m_swapChainFrameBuffers = {};

  m_uniforms = {};
  m_heap = {};
  GGlobalHeap = nullptr;
}

static uint32_t s_frameCount = 0;
/*static*/
uint32_t Fluorescence::getFrameCount() { return s_frameCount; }

void Fluorescence::tick(Application& app, const FrameContext& frame) {
  {
    ++s_frameCount;

    Gui::startRecordingImgui();

    const ImGuiViewport* main_viewport = ImGui::GetMainViewport();
    /* if (ImGui::BeginMainMenuBar()) {
       static bool s_bSelectedFileTab = false;
       if (ImGui::MenuItem("File", "TEST", &s_bSelectedFileTab)) {
       }
     }*/

    // ImGui::EndMainMenuBar();

    // ImGui::SetNextWindowSize(ImVec2(1280, 1024));

    if (m_bOpenFileDialogue) {
      m_bOpenFileDialogue = false;

      OPENFILENAME ofn{};
      memset(&ofn, 0, sizeof(OPENFILENAME));

      char filename[512] = {0};

      ofn.lStructSize = sizeof(ofn);
      ofn.hwndOwner = glfwGetWin32Window(app.getWindow());
      ofn.lpstrFile = filename;
      ofn.lpstrFile[0] = '\0';
      ofn.nMaxFile = sizeof(filename);
      ofn.lpstrFilter = "FLR PROJECT\0*.flr\0\0";
      ofn.nFilterIndex = 1;
      ofn.lpstrFileTitle = NULL;
      ofn.nMaxFileTitle = 0;
      ofn.lpstrInitialDir = NULL;
      ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR;

      // Display the Open dialog box.

      if (GetOpenFileName(&ofn)) {
        strncpy(s_filename, filename, 512);
        m_bReloadProject = true;
      }
    }

    if (m_bReloadProject) {
      m_bReloadProject = false;

      if (m_pProject)
        app.addDeletiontask(DeletionTask{
            [pProject = m_pProject]() { delete pProject; },
            app.getCurrentFrameRingBufferIndex()});

      m_pProject = nullptr;
      if (Utilities::checkFileExists(std::string(s_filename))) {
        for (auto& program : m_programs)
          program->destroyRenderState();

        SingleTimeCommandBuffer commandBuffer(app);
        m_pProject =
            new Project(commandBuffer, m_uniforms, (const char*)s_filename);

        for (auto& program : m_programs)
          program->createRenderState(m_pProject, commandBuffer);

        PerFrameResources* prevDescTables = new PerFrameResources(std::move(m_descriptorSets));
        app.addDeletiontask(DeletionTask{ [prevDescTables]() {
            delete prevDescTables;
          }, app.getCurrentFrameRingBufferIndex() });
        
        DescriptorSetLayoutBuilder builder{};
        builder.addUniformBufferBinding();

        for (auto& program : m_programs)
          program->setupDescriptorTable(builder);

        m_descriptorSets = PerFrameResources(app, builder);

        ResourcesAssignment assignment = m_descriptorSets.assign();
        assignment.bindTransientUniforms(m_uniforms);

        for (auto& program : m_programs)
          program->createDescriptors(assignment);
      }
    }

    if (m_pProject &&
        (m_pProject->hasFailed() || m_pProject->hasRecompileFailed())) {
      if (ImGui::Begin("Project Errors", false)) {
        char buf[2048];
        snprintf(
            buf,
            2048,
            "%s",
            m_pProject->hasFailed() ? m_pProject->getErrorMessage()
                                    : m_pProject->getShaderCompileErrors());
        ImGui::PushStyleColor(0, ImVec4(0.9f, 0.2f, 0.4f, 1.0f));
        size_t errOffset = 0;
        size_t errStrLen = strlen(buf);
        while (errOffset < errStrLen) {
          size_t lineLen = errStrLen - errOffset;
          if (lineLen > 64) lineLen = 64;
          ImGui::TextUnformatted(&buf[errOffset], &buf[errOffset+lineLen]);
          errOffset += lineLen;
        }

        ImGui::PopStyleColor();
      }
      ImGui::End();
    }

    if (m_pProject && m_pProject->isReady()) {
      m_pProject->tick(frame);
      for (auto& program : m_programs)
        program->tick(m_pProject, frame);
    }

    //static GraphEditor::Graph graph;
    //graph.draw();

    Gui::finishRecordingImgui();
  }

  InputManager::MousePos mpos = app.getInputManager().getCurrentMousePos();
  uint32_t inputMask = app.getInputManager().getCurrentInputMask();

  static uint32_t prevInputMask = inputMask;

  if (!m_bFreezeTime)
    m_time += frame.deltaTime;

  FlrUniforms uniforms;
  uniforms.mouseUv.x =
      static_cast<float>(0.5 * mpos.x + 0.5);
  uniforms.mouseUv.y =
      static_cast<float>(0.5 - 0.5 * mpos.y);
  uniforms.time = m_time;
  uniforms.frameCount = s_frameCount;
  uniforms.prevInputMask = prevInputMask;
  uniforms.inputMask = inputMask;

  prevInputMask = inputMask;

  m_uniforms.getCurrentUniformBuffer(frame).updateUniforms(uniforms);
}

void Fluorescence::_createGlobalResources(
    Application& app,
    SingleTimeCommandBuffer& commandBuffer) {
  m_heap = GlobalHeap(app);
  GGlobalHeap = &m_heap;
  AltheaEngine::registerDefaultTexturesToHeap(m_heap);
  m_uniforms = TransientUniforms<FlrUniforms>(app, {});
  m_uniforms.registerToHeap(m_heap);
}

void Fluorescence::_createDisplayPass(Application& app) {
  VkClearValue colorClear;
  colorClear.color = {{0.0f, 0.0f, 0.0f, 1.0f}};
  VkClearValue depthClear;
  depthClear.depthStencil = {1.0f, 0};

  std::vector<Attachment> attachments = {Attachment{
      ATTACHMENT_FLAG_COLOR,
      app.getSwapChainImageFormat(),
      colorClear,
      false, // forPresent is false since the imGUI pass follows the
             // deferred pass
      false,
      true}};

  std::vector<SubpassBuilder> subpassBuilders;

  // DEFERRED PBR PASS
  {
    SubpassBuilder& subpassBuilder = subpassBuilders.emplace_back();
    subpassBuilder.colorAttachments.push_back(0);

    ShaderDefines defs;

    subpassBuilder.pipelineBuilder.setCullMode(VK_CULL_MODE_FRONT_BIT)
        .setDepthTesting(false);
    {
      ShaderDefines defs;
      defs.emplace("IS_VERTEX_SHADER", "");
      defs.emplace("VS_FullScreen", "main");
      subpassBuilder.pipelineBuilder.addVertexShader(
          GProjectDirectory + "/Shaders/Display.glsl",
          defs);
    }

    {
      ShaderDefines defs;
      defs.emplace("IS_PIXEL_SHADER", "");
      defs.emplace("PS_Default", "main");
      subpassBuilder.pipelineBuilder.addFragmentShader(
          GProjectDirectory + "/Shaders/Display.glsl",
          defs);
    }

    subpassBuilder.pipelineBuilder.layoutBuilder
        .addDescriptorSet(m_heap.getDescriptorSetLayout())
        .addPushConstants<FlrPush>(VK_SHADER_STAGE_ALL);
  }

  m_displayPass = RenderPass(
      app,
      app.getSwapChainExtent(),
      std::move(attachments),
      std::move(subpassBuilders));

  m_swapChainFrameBuffers =
      SwapChainFrameBufferCollection(app, m_displayPass, {});
}

void Fluorescence::draw(
    Application& app,
    VkCommandBuffer commandBuffer,
    const FrameContext& frame) {

  VkDescriptorSet heapDescriptorSet = m_heap.getDescriptorSet();
  if (m_pProject && m_pProject->isReady() && !m_bPaused) {
    m_pProject->draw(commandBuffer, frame);
    for (auto& program : m_programs)
      program->draw(m_pProject, commandBuffer, frame);
  }

  {
    FlrPush push{};
    if (m_pProject && m_pProject->isReady()) {
      push.push0 = m_pProject->getOutputTexture().index;
    } else {
      push.push0 = INVALID_BINDLESS_HANDLE;
    }

    ActiveRenderPass pass = m_displayPass.begin(
        app,
        commandBuffer,
        frame,
        m_swapChainFrameBuffers.getCurrentFrameBuffer(frame));
    // Bind global descriptor sets
    pass.setGlobalDescriptorSets(gsl::span(&heapDescriptorSet, 1));
    pass.getDrawContext().updatePushConstants(push, 0);

    {
      const DrawContext& context = pass.getDrawContext();
      context.bindDescriptorSets();
      context.draw(3);
    }
  }

  Gui::draw(app, frame, commandBuffer);
}
} // namespace flr