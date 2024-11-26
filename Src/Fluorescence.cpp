#include "Fluorescence.h"

#include "GraphEditor/Graph.h"
#include "Project.h"

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
// #define GLFW_EXPOSE_NATIVE_WGL
// #define GLFW_NATIVE_INCLUDE_NONE
#include <GLFW/glfw3native.h>
#include <basetsd.h>
#include <commdlg.h>

#include <array>
#include <cstdint>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

using namespace AltheaEngine;

namespace flr {

Fluorescence::Fluorescence() {}

static char s_filename[256] =
    "C:/Users/nithi/Documents/Code/Fluorescence/Projects/AgentSim/"
    "AgentSim.flr";
static bool s_bProjectWindowOpen = true;

void Fluorescence::initGame(Application& app) {
  // TODO: need to unbind these at shutdown
  InputManager& input = app.getInputManager();
  input.setMouseCursorHidden(false);

  // Recreate any stale pipelines (shader hot-reload)
  input.addKeyBinding(
      {GLFW_KEY_R, GLFW_PRESS, GLFW_MOD_CONTROL},
      [&app, this]() {
        m_displayPass.tryRecompile(app);
        if (m_pProject && !m_pProject->hasFailed())
          m_pProject->tryRecompile(app);
      });
  input.addKeyBinding(
      {GLFW_KEY_R, GLFW_PRESS, GLFW_MOD_CONTROL | GLFW_MOD_SHIFT},
      [&app, this]() {
        app.addDeletiontask(DeletionTask{
            [pProject = m_pProject]() { delete pProject; },
            app.getCurrentFrameRingBufferIndex()});
        m_pProject =
            new Project(app, m_heap, m_uniforms, (const char*)s_filename);
      });
  input.addKeyBinding(
      {GLFW_KEY_O, GLFW_PRESS, GLFW_MOD_CONTROL},
      [&app, this]() { s_bProjectWindowOpen = true; });
}

void Fluorescence::shutdownGame(Application& app) {}

void Fluorescence::createRenderState(Application& app) {
  Gui::createRenderState(app);

  SingleTimeCommandBuffer commandBuffer(app);
  _createGlobalResources(app, commandBuffer);
  _createDisplayPass(app);
}

void Fluorescence::destroyRenderState(Application& app) {
  Gui::destroyRenderState(app);

  delete m_pProject;
  m_pProject = nullptr;

  m_displayPass = {};
  m_swapChainFrameBuffers = {};

  m_uniforms = {};
  m_heap = {};
}

void Fluorescence::tick(Application& app, const FrameContext& frame) {
  {
    Gui::startRecordingImgui();

    const ImGuiViewport* main_viewport = ImGui::GetMainViewport();
    /* if (ImGui::BeginMainMenuBar()) {
       static bool s_bSelectedFileTab = false;
       if (ImGui::MenuItem("File", "TEST", &s_bSelectedFileTab)) {
       }
     }*/

    // ImGui::EndMainMenuBar();

    // ImGui::SetNextWindowSize(ImVec2(1280, 1024));

    if (ImGui::Begin("Open Flr File", &s_bProjectWindowOpen)) {

      ImGui::Text("Project Name");
      ImGui::InputText("##flr_file", s_filename, 256);

      static char s_errorLog[2048] = {0};

      ImGui::SameLine();

      if (ImGui::Button("Choose File")) {
        OPENFILENAME ofn{}; // common dialog box structure
        char szFile[260];   // buffer for file name
        // HWND hwnd = ;        // owner window
        // HANDLE hf;              // file handle

        // Initialize OPENFILENAME
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = glfwGetWin32Window(app.getWindow());
        ofn.lpstrFile = szFile;
        // Set lpstrFile[0] to '\0' so that GetOpenFileName does not
        // use the contents of szFile to initialize itself.
        ofn.lpstrFile[0] = '\0';
        ofn.nMaxFile = sizeof(szFile);
        ofn.lpstrFilter = "*.flr\0";
        ofn.nFilterIndex = 1;
        ofn.lpstrFileTitle = NULL;
        ofn.nMaxFileTitle = 0;
        ofn.lpstrInitialDir = NULL;
        ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST;

        // Display the Open dialog box.

        if (GetOpenFileName(&ofn)) {
          memcpy(s_filename, szFile, strlen(szFile));
          if (m_pProject)
            app.addDeletiontask(DeletionTask{
                [pProject = m_pProject]() { delete pProject; },
                app.getCurrentFrameRingBufferIndex()});

          m_pProject =
              new Project(app, m_heap, m_uniforms, (const char*)s_filename);
        }
      }

      if (ImGui::Button("Re-Open Project")) {
        if (m_pProject)
          app.addDeletiontask(DeletionTask{
              [pProject = m_pProject]() { delete pProject; },
              app.getCurrentFrameRingBufferIndex()});

        m_pProject =
            new Project(app, m_heap, m_uniforms, (const char*)s_filename);
      }

      ImGui::Separator();
      ImGui::Text("Log:");
      if (m_pProject) {
        if (m_pProject->hasFailed() || m_pProject->hasRecompileFailed()) {
          char buf[2048];
          sprintf(
              buf,
              "%s",
              m_pProject->hasFailed() ? m_pProject->getErrorMessage()
                                      : m_pProject->getShaderCompileErrors());
          ImGui::PushStyleColor(0, ImVec4(0.9f, 0.2f, 0.4f, 1.0f));
          ImGui::InputTextMultiline(
              "##logoutput",
              buf,
              2048,
              ImVec2(0, 0),
              ImGuiInputTextFlags_ReadOnly);
          ImGui::PopStyleColor();
        } else {
          ImGui::PushStyleColor(0, ImVec4(0.1f, 0.9f, 0.1f, 1.0f));
          ImGui::InputTextMultiline(
              "##logoutput",
              "Loaded project successfully!",
              2048,
              ImVec2(0, 0),
              ImGuiInputTextFlags_ReadOnly);
          ImGui::PopStyleColor();
        }
      } else {
        ImGui::PushStyleColor(0, ImVec4(0.8f, 0.8f, 0.8f, 1.0f));
        ImGui::InputTextMultiline(
            "##logoutput",
            "No Project Loaded",
            2048,
            ImVec2(0, 0),
            ImGuiInputTextFlags_ReadOnly);
        ImGui::PopStyleColor();
      }
    }
    ImGui::End();

    // static GraphEditor::Graph graph;
    // graph.draw();

    Gui::finishRecordingImgui();
  }

  InputManager::MousePos mpos = app.getInputManager().getCurrentMousePos();
  uint32_t inputMask = app.getInputManager().getCurrentInputMask();

  static uint32_t frameCount = 0;
  static uint32_t prevInputMask = inputMask;

  FlrUniforms uniforms;
  uniforms.mouseUv.x =
      static_cast<float>(mpos.x / app.getSwapChainExtent().width);
  uniforms.mouseUv.y =
      static_cast<float>(mpos.y / app.getSwapChainExtent().height);
  uniforms.time = static_cast<float>(frame.currentTime);
  uniforms.frameCount = frameCount++;
  uniforms.prevInputMask = prevInputMask;
  uniforms.inputMask = inputMask;

  m_uniforms.getCurrentUniformBuffer(frame).updateUniforms(uniforms);
}

void Fluorescence::_createGlobalResources(
    Application& app,
    SingleTimeCommandBuffer& commandBuffer) {
  m_heap = GlobalHeap(app);
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
  if (m_pProject && m_pProject->isReady()) {
    m_pProject->draw(app, commandBuffer, m_heap, frame);
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