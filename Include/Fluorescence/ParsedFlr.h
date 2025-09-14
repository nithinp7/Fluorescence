
#include <Althea/Application.h>
#include <Althea/Utilities.h>
#include <Althea/GraphicsPipeline.h>

#include <cstdint>
#include <string>
#include <vector>

using namespace AltheaEngine;

namespace flr {
struct FlrParams;

struct ParsedFlr {
  ParsedFlr(Application& app, const char* projectPath, const FlrParams& params);

  struct ConstUint {
    std::string name;
    uint32_t value;
  };
  std::vector<ConstUint> m_constUints;

  struct ConstInt {
    std::string name;
    int value;
  };
  std::vector<ConstInt> m_constInts;

  struct ConstFloat {
    std::string name;
    float value;
  };
  std::vector<ConstFloat> m_constFloats;

  enum UiElementType : uint8_t {
    UET_SLIDER_UINT = 0,
    UET_SLIDER_INT,
    UET_SLIDER_FLOAT,
    UET_COLOR_PICKER,
    UET_CHECKBOX,
    UET_SAVE_IMAGE_BUTTON,
    UET_SAVE_BUFFER_BUTTON,
    UET_TASK_BUTTON,
    UET_SEPARATOR,
    UET_DROPDOWN_START,
    UET_DROPDOWN_END
  };
  struct UiElement {
    UiElementType type;
    uint32_t idx;
  };
  std::vector<UiElement> m_uiElements;

  struct GenericNamedElement {
    std::string name;
  };
  std::vector<GenericNamedElement> m_genericNamedElements;

  struct SliderUint {
    std::string name;
    uint32_t defaultValue;
    uint32_t min;
    uint32_t max;
    uint32_t uiIdx;
    uint32_t* pValue;
  };
  std::vector<SliderUint> m_sliderUints;

  struct SliderInt {
    std::string name;
    int defaultValue;
    int min;
    int max;
    uint32_t uiIdx;
    int* pValue;
  };
  std::vector<SliderInt> m_sliderInts;

  struct SliderFloat {
    std::string name;
    float defaultValue;
    float min;
    float max;
    uint32_t uiIdx;
    float* pValue;
  };
  std::vector<SliderFloat> m_sliderFloats;

  struct ColorPicker {
    std::string name;
    glm::vec4 defaultValue;
    uint32_t uiIdx;
    float* pValue;
  };
  std::vector<ColorPicker> m_colorPickers;

  struct Checkbox {
    std::string name;
    bool defaultValue;
    uint32_t uiIdx;
    uint32_t* pValue; // glsl bools are 32bit
  };
  std::vector<Checkbox> m_checkboxes;

  struct SaveImageButton {
    uint32_t imageIdx;
    uint32_t uiIdx;
  };
  std::vector<SaveImageButton> m_saveImageButtons;

  struct SaveBufferButton {
    uint32_t bufferIdx;
    uint32_t uiIdx;
  };
  std::vector<SaveBufferButton> m_saveBufferButtons;

  struct TaskButton {
    uint32_t taskBlockIdx;
    uint32_t uiIdx;
  };
  std::vector<TaskButton> m_taskButtons;
  
  struct StructDef {
    std::string name;
    std::string body;
    uint32_t size;
  };
  std::vector<StructDef> m_structDefs;

  struct BufferDesc {
    std::string name;
    uint32_t structIdx;
    uint32_t elemCount;
    uint32_t bufferCount;
    bool bCpuVisible;
    bool bTransferSrc;
    bool bIndirectArgs;
    bool bIndexBuffer;
  };
  std::vector<BufferDesc> m_buffers;

  struct ImageDesc {
    std::string name;
    std::string format;
    ImageOptions createOptions;
  };
  std::vector<ImageDesc> m_images;

  struct TextureFile {
    ImageOptions createOptions;
    Utilities::ImageFile loadedImage;
  };
  std::vector<TextureFile> m_textureFiles;

  struct TextureDesc {
    std::string name;
    int imageIdx;
    int texFileIdx; // image idx or texfile idx, but not both
  };
  std::vector<TextureDesc> m_textures;

  struct ComputeShader {
    std::string name;
    uint32_t groupSizeX;
    uint32_t groupSizeY;
    uint32_t groupSizeZ;
  };
  std::vector<ComputeShader> m_computeShaders;

  struct ComputeDispatch {
    uint32_t computeShaderIndex;
    uint32_t dispatchSizeX;
    uint32_t dispatchSizeY;
    uint32_t dispatchSizeZ;
  };
  std::vector<ComputeDispatch> m_computeDispatches;

  struct BufferResourceStateMapping{
    const char* name;
    VkAccessFlags accessFlags;
  };
  static constexpr BufferResourceStateMapping BUFFER_RESOURCE_STATE_TABLE[] = {
    {"rw", VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT},
    {"indirectArgs", VK_ACCESS_INDIRECT_COMMAND_READ_BIT},
    {"indexBuffer", VK_ACCESS_INDEX_READ_BIT}
  };

  struct Barrier {
    std::vector<uint32_t> buffers;
    VkAccessFlags accessFlags;
  };
  std::vector<Barrier> m_barriers;

  struct ObjMesh {
    std::string name;
    std::string path;
  };
  std::vector<ObjMesh> m_objModels;

  enum LayoutTransitionTarget : uint8_t {
    LTT_TEXTURE = 0,
    LTT_IMAGE_RW,
    LTT_ATTACHMENT,
    LTT_COUNT
  };
  static constexpr char* TRANSITION_TARGET_NAMES[LTT_COUNT] = {
      "texture",
      "image",
      "attachment"};
  struct Transition {
    uint32_t image;
    LayoutTransitionTarget transitionTarget;
  };
  std::vector<Transition> m_transitions;

  enum DrawMode : uint8_t {
    DM_DRAW = 0,
    DM_DRAW_INDEXED, 
    DM_DRAW_OBJ,
    DM_DRAW_INDIRECT,
    //DM_DRAW_INDEXED_INDIRECT
  };

  struct Draw {
    // TODO: re-usable subpasses that can be used multiple times...
    std::string vertexShader;
    std::string pixelShader;
    // param0/1/2 are used as follows
    // if drawMode==DM_DRAW: vertexCount, instanceCount, UNUSED
    // if drawMode==DM_DRAW_INDEXED: instanceCount, indexBufferIdx, subBufferIdx(optional)
    // if drawMode==DM_DRAW_INDIRECT, indirectBufferIdx, drawCount, subBufferIdx(optional)
    // if drawMode==DM_DRAW_OBJ, objIdx, UNUSED, UNUSED
    uint32_t param0;
    uint32_t param1;
    uint32_t param2;
    int vertexOutputStructIdx;
    DrawMode drawMode;
    AltheaEngine::PrimitiveType primType;
    float lineWidth; 
    bool bDisableDepth;
    bool bDisableBackfaceCull;
  };

  struct AttachmentRef {
    std::string aliasName;
    int imageIdx;
    bool bLoad;
    bool bStore;
  };
  struct RenderPass {
    std::string name;
    std::vector<Draw> draws;
    std::vector<AttachmentRef> attachments;
    int width;
    int height;
  };
  std::vector<RenderPass> m_renderPasses;

  enum TaskType : uint8_t {
    TT_COMPUTE = 0,
    TT_BARRIER,
    TT_RENDER,
    TT_TRANSITION,
    TT_TASK
  };
  struct Task {
    uint32_t idx;
    TaskType type;
  };
  std::vector<Task> m_taskList;

  struct TaskBlock {
    std::string name;
    std::vector<Task> tasks;
  };
  std::vector<TaskBlock> m_taskBlocks;

  enum FeatureFlag : uint32_t {
    FF_NONE = 0,
    FF_PERSPECTIVE_CAMERA = (1 << 0),
    FF_SYSTEM_AUDIO_INPUT = (1 << 1)
  };
  uint32_t m_featureFlags;

  int m_displayImageIdx;
  int m_initializationTaskIdx;

  bool isFeatureEnabled(FeatureFlag feature) const {
    return (m_featureFlags & feature) != 0;
  }

  static constexpr char* FEATURE_FLAG_NAMES[] = {
      "perspective_camera",
      "system_audio_input" // TODO: mic audio input
  };

  bool m_failed;
  char m_errMsg[2048];

  enum Instr : uint8_t {
    I_CONST_UINT = 0,
    I_CONST_INT,
    I_CONST_FLOAT,
    I_SLIDER_UINT,
    I_SLIDER_INT,
    I_SLIDER_FLOAT,
    I_COLOR_PICKER,
    I_CHECKBOX,
    I_SAVE_IMAGE_BUTTON,
    I_SAVE_BUFFER_BUTTON,
    I_TASK_BUTTON,
    I_SEPARATOR,
    I_DROPDOWN_START,
    I_DROPDOWN_END,
    I_STRUCT,
    I_STRUCT_SIZE,
    I_STRUCTURED_BUFFER,
    I_INDEX_BUFFER,
    I_ENABLE_CPU_ACCESS,
    I_COMPUTE_SHADER,
    I_COMPUTE_DISPATCH,
    I_BARRIER,
    I_OBJ_MODEL,
    I_DISPLAY_IMAGE,
    I_RENDER_PASS,
    I_DISABLE_DEPTH,
    I_DISABLE_BACKFACE_CULLING,
    I_LOAD_ATTACHMENTS,
    I_STORE_ATTACHMENTS,
    I_LOADSTORE_ATTACHMENTS,
    I_LOAD_DEPTH,
    I_STORE_DEPTH,
    I_LOADSTORE_DEPTH,
    I_DRAW,
    I_DRAW_INDEXED,
    I_DRAW_INDIRECT,
    I_DRAW_OBJ,
    I_PRIM_TYPE,
    I_VERTEX_OUTPUT,
    I_FEATURE,
    I_IMAGE,
    I_DEPTH_IMAGE,
    I_TEXTURE_ALIAS,
    I_TEXTURE_FILE,
    I_TRANSITION,
    I_TASK_BLOCK_START,
    I_TASK_BLOCK_END,
    I_RUN_TASK,
    I_INITIALIZATION_TASK,
    I_INCLUDE,
    I_COUNT
  };

  static constexpr char* INSTR_NAMES[I_COUNT] = {
      "uint",
      "int",
      "float",
      "slider_uint",
      "slider_int",
      "slider_float",
      "color_picker",
      "checkbox",
      "save_image_button",
      "save_buffer_button",
      "task_button",
      "ui_separator",
      "ui_dropdown_start",
      "ui_dropdown_end",
      "struct",
      "struct_size",
      "structured_buffer",
      "index_buffer",
      "enable_cpu_access",
      "compute_shader",
      "compute_dispatch",
      "barrier",
      "obj_model",
      "display_image",
      "render_pass",
      "disable_depth",
      "disable_backface_culling",
      "load_attachments",
      "store_attachments",
      "loadstore_attachments",
      "load_depth",
      "store_depth",
      "loadstore_depth",
      "draw",
      "draw_indexed",
      "draw_indirect",
      "draw_obj",
      "primitive_type",
      "vertex_output",
      "enable_feature",
      "image",
      "depth_image",
      "texture_alias",
      "texture_file",
      "transition_layout",
      "task_block_start",
      "task_block_end",
      "run_task",
      "initialization_task",
      "include"};

  struct ImageFormatTableEntry {
    const char* glslFormatName;
    VkFormat vkFormat;
  };

  static constexpr ImageFormatTableEntry IMAGE_FORMAT_TABLE[] = {
    {"rgba8", VK_FORMAT_R8G8B8A8_UNORM},
    {"rgba16", VK_FORMAT_R16G16B16A16_UNORM},
    {"r8", VK_FORMAT_R8_UNORM},
    {"r16", VK_FORMAT_R16_UNORM},
    {"rg8", VK_FORMAT_R8G8_UNORM},
    {"rg16", VK_FORMAT_R16G16_UNORM},
    {"rgba8_snorm", VK_FORMAT_R8G8B8A8_SNORM},
    {"rgba16_snorm", VK_FORMAT_R16G16B16A16_SNORM},
    {"r8_snorm", VK_FORMAT_R8_SNORM},
    {"r16_snorm", VK_FORMAT_R16_SNORM},
    {"rg8_snorm", VK_FORMAT_R8G8_SNORM},
    {"rg16_snorm", VK_FORMAT_R16G16_SNORM},
    {"rgba32f", VK_FORMAT_R32G32B32A32_SFLOAT},
    {"r32f", VK_FORMAT_R32_SFLOAT},
    {"rg16f", VK_FORMAT_R16G16_SFLOAT},
    {"rgba32i", VK_FORMAT_R32G32B32A32_SINT},
    {"r32i", VK_FORMAT_R32_SINT},
    {"rgba32ui", VK_FORMAT_R32G32B32A32_UINT},
    {"r32ui", VK_FORMAT_R32_UINT}
  };
};

struct FlrParams {
  std::vector<ParsedFlr::ConstUint> m_uintParams;
};
} // namespace flr