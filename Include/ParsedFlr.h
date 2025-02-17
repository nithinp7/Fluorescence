
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

  struct Checkbox {
    std::string name;
    bool defaultValue;
    uint32_t uiIdx;
    uint32_t* pValue; // glsl bools are 32bit
  };
  std::vector<Checkbox> m_checkboxes;

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

  struct AttachmentDesc {
    std::string name;
    int imageIdx;
  };
  std::vector<AttachmentDesc> m_attachments;

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

  struct RenderPass {
    std::vector<Draw> draws;
    std::vector<int> colorAttachments;
    int width;
    int height;
    bool bIsDisplayPass;
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
    I_CHECKBOX,
    I_STRUCT,
    I_STRUCT_SIZE,
    I_STRUCTURED_BUFFER,
    I_COMPUTE_SHADER,
    I_COMPUTE_DISPATCH,
    I_BARRIER,
    I_OBJ_MODEL,
    I_DISPLAY_PASS,
    I_RENDER_PASS,
    I_DISABLE_DEPTH,
    I_COLOR_ATTACHMENTS,
    I_DRAW,
    I_DRAW_OBJ,
    I_VERTEX_OUTPUT,
    I_FEATURE,
    I_IMAGE,
    I_TEXTURE_ALIAS,
    I_ATTACHMENT_ALIAS,
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
      "checkbox",
      "struct",
      "struct_size",
      "structured_buffer",
      "compute_shader",
      "compute_dispatch",
      "barrier",
      "obj_model",
      "display_pass",
      "render_pass",
      "disable_depth",
      "color_attachments",
      "draw",
      "draw_obj",
      "vertex_output",
      "enable_feature",
      "image",
      "texture_alias",
      "attachment_alias",
      "texture_file",
      "transition_layout"};
};

} // namespace flr