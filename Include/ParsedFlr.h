
#include <Althea/Application.h>
#include <Althea/Utilities.h>

#include <cstdint>
#include <string>
#include <vector>

using namespace AltheaEngine;

namespace flr {

struct ParsedFlr {
  ParsedFlr(Application& app, const char* projectPath);

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

  struct Barrier {
    std::vector<uint32_t> buffers;
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
    LTT_ATTACHMENT
  };
  static constexpr char* TRANSITION_TARGET_NAMES[] = {
      "texture",
      "image",
      "attachment"};
  struct Transition {
    uint32_t image;
    LayoutTransitionTarget transitionTarget;
  };
  std::vector<Transition> m_transitions;

  struct Draw {
    // TODO: re-usable subpasses that can be used multiple times...
    std::string vertexShader;
    std::string pixelShader;
    uint32_t vertexCount;
    uint32_t instanceCount;
    int objMeshIdx; // if >= 0, pulls vertex count from loaded file
    int vertexOutputStructIdx;
    bool bDisableDepth;
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
    TT_TRANSITION
  };
  struct Task {
    uint32_t idx;
    TaskType type;
  };
  std::vector<Task> m_taskList;

  enum FeatureFlag : uint32_t {
    FF_NONE = 0,
    FF_PERSPECTIVE_CAMERA = (1 << 0),
    FF_SYSTEM_AUDIO_INPUT = (1 << 1)
  };
  uint32_t m_featureFlags;

  int m_displayImageIdx;

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
    I_STRUCT,
    I_STRUCT_SIZE,
    I_STRUCTURED_BUFFER,
    I_COMPUTE_SHADER,
    I_COMPUTE_DISPATCH,
    I_BARRIER,
    I_OBJ_MODEL,
    I_DISPLAY_IMAGE,
    I_RENDER_PASS,
    I_DISABLE_DEPTH,
    I_LOAD_ATTACHMENTS,
    I_STORE_ATTACHMENTS,
    I_LOADSTORE_ATTACHMENTS,
    I_LOAD_DEPTH,
    I_STORE_DEPTH,
    I_LOADSTORE_DEPTH,
    I_DRAW,
    I_DRAW_OBJ,
    I_VERTEX_OUTPUT,
    I_FEATURE,
    I_IMAGE,
    I_DEPTH_IMAGE,
    I_TEXTURE_ALIAS,
    I_TEXTURE_FILE,
    I_TRANSITION,
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
      "struct",
      "struct_size",
      "structured_buffer",
      "compute_shader",
      "compute_dispatch",
      "barrier",
      "obj_model",
      "display_image",
      "render_pass",
      "disable_depth",
      "load_attachments",
      "store_attachments",
      "loadstore_attachments",
      "load_depth",
      "store_depth",
      "loadstore_depth",
      "draw",
      "draw_obj",
      "vertex_output",
      "enable_feature",
      "image",
      "depth_image",
      "texture_alias",
      "texture_file",
      "transition_layout"};

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

} // namespace flr