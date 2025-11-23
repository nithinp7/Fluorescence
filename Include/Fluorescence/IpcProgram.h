#include "Fluorescence.h"

#include <windows.h>
#include <conio.h>
#include <WinBase.h>

#include <vulkan/vulkan.h>

using namespace AltheaEngine;

namespace flr {
  namespace flr_cmds {
    // NOTE: Keep in sync with FlrCmdType in flrlib.py
    enum eCmdType : uint32_t {
      CMD_FINISH = 0,
      CMD_UINT_PARAM,
      CMD_PUSH_CONSTANTS,
      CMD_DISPATCH,
      CMD_BARRIER_RW,
      CMD_BUFFER_WRITE,
      CMD_BUFFER_STAGED_UPLOAD,
      CMD_UNIFORM_WRITE,
      CMD_RUN_TASK
    };

    // only valid on introduction
    struct CmdUintParam {
      uint32_t nameOffset;
      uint32_t nameSize;
      uint32_t value;
    };

    struct CmdPushConstants {
      uint32_t push0;
      uint32_t push1;
      uint32_t push2;
      uint32_t push3;
    };

    struct CmdDispatch {
      uint32_t computeShaderId;
      uint32_t groupCountX;
      uint32_t groupCountY;
      uint32_t groupCountZ;
    };

    struct CmdBarrierRW {
      uint32_t bufferId;
    };

    struct CmdBufferWrite {
      uint32_t bufferId;
      uint32_t subBufIdx;
      uint32_t srcOffset;
      uint32_t dstOffset;
      uint32_t sizeBytes;
    };

    struct CmdBufferStagedUpload {
      uint32_t bufferId;
      uint32_t subBufIdx;
      uint32_t srcOffset;
      uint32_t sizeBytes;
    };

    struct CmdUniformWrite {
      uint32_t srcOffset;
      uint32_t dstOffset;
      uint32_t sizeBytes;
    };

    struct CmdRunTask {
      uint32_t taskId;
    };

    bool processIntroduction(const char* stream, size_t streamSize, flr::FlrParams& params);
    bool processCmdList(Project* project, VkCommandBuffer commandBuffer, const FrameContext& frame, const char* stream, size_t streamSize);
  } // namespace flr_cmds

  namespace flr_packets {
    // NOTE: Keep in sync with FlrMessageType in flrlib.py
    enum eMessageType : uint32_t {
      FMT_FINISH = 0,
      FMT_BUFFER,
      FMT_UI,
      FMT_UI_UPDATE,
      FMT_COMPUTE_SHADER,
      FMT_TASK,
      FMT_CONST,
      FMT_REINIT,
      FMT_GREET = 0x1F1F1F1F,
      FMT_FAILED = 0xFFFFFFFF
    };

    void assembleEstablishmentPacket(Project* project, char* stream, size_t streamSize);
    void assembleUpdatePacket(Project* project, char* stream, size_t streamSize);
  } // namespace flr_packets

  class IpcProgram : public IFlrProgram {
  public:
    IpcProgram();
    ~IpcProgram();

    //void setupDescriptorTable(DescriptorSetLayoutBuilder& builder) override;
    //void createDescriptors(ResourcesAssignment& assignment) override;
    void setupParams(FlrParams& params) override;
    void createRenderState(Project* project, SingleTimeCommandBuffer& commandBuffer) override;
    void destroyRenderState() override;

    void tick(Project* project, const FrameContext& frame) override;
    void draw(
      Project* project,
      VkCommandBuffer commandBuffer,
      const FrameContext& frame) override;

  private:
    // TODO - would really like to double buffer so that the script can run a frame ahead of 
    // the FLR app

    // TODO - should rename these, "writeDone" --> "scriptDone" and "readDone" --> "appDone"
    HANDLE m_writeDoneSemaphoreHandle;
    HANDLE m_readDoneSemaphoreHandle;
    HANDLE m_sharedMemoryHandle;
    void* m_sharedMemoryBuffer;

    bool m_bInitialSetup;

    flr::FlrParams m_params;
  };
} // namespace flr
