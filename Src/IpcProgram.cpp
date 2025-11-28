#pragma once
#include "IpcProgram.h"

#include <stdio.h>
#include <tchar.h>

#include <iostream>
#include <optional>

// ??
#pragma comment(lib, "user32.lib")

namespace flr {
namespace flr_cmds {
namespace {
class CmdStreamView {
public:
  CmdStreamView(const char* stream, size_t streamSize)
      : m_pStream(stream),
        m_streamOffset(0),
        m_streamSize(streamSize),
        m_bFailed(!m_pStream || (m_streamSize == 0)) {}

  template <typename T> std::optional<T> read() {
    if (isFailed())
      return std::nullopt;

    size_t sz = sizeof(T);
    if ((m_streamOffset + sz) > m_streamSize) {
      m_bFailed = true;
      return std::nullopt;
    }

    T val;
    memcpy(&val, m_pStream + m_streamOffset, sz);
    m_streamOffset += sz;
    return val;
  }

  void setFailed() { m_bFailed = true; }
  bool isFailed() const { return m_bFailed; }

  void copyTo(void* dst, size_t srcOffset, size_t sizeBytes) {
    if (m_bFailed)
      return;
    if (srcOffset > m_streamSize || (srcOffset + sizeBytes) > m_streamSize) {
      m_bFailed = true;
      return;
    }
    memcpy(dst, m_pStream + srcOffset, sizeBytes);
  }

private:
  const char* m_pStream;
  size_t m_streamOffset;
  size_t m_streamSize;
  bool m_bFailed;
};
} // namespace

bool processIntroduction(const char* stream, size_t streamSize, flr::FlrParams& params) {
  CmdStreamView streamView(stream, streamSize);
  while (auto cmdType = streamView.read<uint32_t>()) {
    switch (*cmdType) {
    case CMD_FINISH: {
      return true;
    }
    case CMD_UINT_PARAM: {
      if (auto cmd = streamView.read<CmdUintParam>()) {
        ParsedFlr::ConstUint& param = params.m_uintParams.emplace_back();
        param.value = cmd->value;
        param.name.resize(cmd->nameSize, 0);
        streamView.copyTo(param.name.data(), cmd->nameOffset, cmd->nameSize);
      }
      break;
    }
    default: {
      return false;
    }
    }
  }

  return false;
}

bool processCmdList(
    Project* project,
    VkCommandBuffer commandBuffer,
    const FrameContext& frame,
    const char* stream,
    size_t streamSize) {
  CmdStreamView streamView(stream, streamSize);

  while (auto cmdType = streamView.read<uint32_t>()) {
    switch (*cmdType) {
    case CMD_FINISH: {
      return true; // denotes end of cmdlist
    }
    case CMD_PUSH_CONSTANTS: {
      if (auto cmd = streamView.read<CmdPushConstants>()) {
        project
            ->setPushConstants(cmd->push0, cmd->push1, cmd->push2, cmd->push3);
      }
      break;
    }
    case CMD_DISPATCH: {
      if (auto cmd = streamView.read<CmdDispatch>()) {
        project->dispatch(
            ComputeShaderId(cmd->computeShaderId),
            cmd->groupCountX,
            cmd->groupCountY,
            cmd->groupCountZ,
            commandBuffer,
            frame);
      }
      break;
    }
    case CMD_BARRIER_RW: {
      if (auto cmd = streamView.read<CmdBarrierRW>()) {
        project->barrierRW(BufferId(cmd->bufferId), commandBuffer);
      }
      break;
    }
    case CMD_BUFFER_WRITE: {
      if (auto cmd = streamView.read<CmdBufferWrite>()) {
        if (cmd->subBufIdx == ~0u)
          cmd->subBufIdx = frame.frameRingBufferIndex;
        BufferAllocation* alloc =
            project->getBufferAlloc(BufferId(cmd->bufferId), cmd->subBufIdx);
        char* pMapped = (char*)alloc->mapMemory();
        streamView.copyTo(
            pMapped + cmd->dstOffset,
            cmd->srcOffset,
            cmd->sizeBytes);
        alloc->unmapMemory();
      }
      break;
    }
    case CMD_BUFFER_STAGED_UPLOAD: {
      if (auto cmd = streamView.read<CmdBufferStagedUpload>()) {
        BufferAllocation* alloc =
            project->getBufferAlloc(BufferId(cmd->bufferId), cmd->subBufIdx);
        BufferAllocation staging =
            BufferUtilities::createStagingBuffer(cmd->sizeBytes);
        char* pMapped = (char*)staging.mapMemory();
        streamView.copyTo(pMapped, cmd->srcOffset, cmd->sizeBytes);
        staging.unmapMemory();
        BufferUtilities::copyBuffer(
            commandBuffer,
            staging.getBuffer(),
            0,
            alloc->getBuffer(),
            0,
            cmd->sizeBytes);
        GApplication->addDeletiontask(
            {[pStaging = new BufferAllocation(std::move(staging))]() {
               delete pStaging;
             },
             frame.frameRingBufferIndex});
      }
      break;
    }
    case CMD_UNIFORM_WRITE: {
      if (auto cmd = streamView.read<CmdUniformWrite>()) {
        if (cmd->dstOffset + cmd->sizeBytes > project->getDynamicDataSize())
          streamView.setFailed();
        streamView.copyTo(
            project->getDynamicDataPtr() + cmd->dstOffset,
            cmd->srcOffset,
            cmd->sizeBytes);
      }
      break;
    }
    case CMD_RUN_TASK: {
      if (auto cmd = streamView.read<CmdRunTask>()) {
        project->executeTaskBlock(
            TaskBlockId(cmd->taskId),
            commandBuffer,
            frame);
      }
      break;
    }
    default: {
      return false;
    }
    }
  }

  return false;
}
} // namespace flr_cmds

namespace flr_packets {
namespace {
class PacketWriter {
public:
  PacketWriter(char* stream, size_t size)
    : m_pStream(stream)
    , m_streamSize(size)
    , m_writeOffset(0u)
    , m_allocBottom(size)
    , m_bFailed(false) {}

  void declareFailure() {
    m_bFailed = true;
    // TODO what about shader recompile failed (where flr has parsed fine?)
    uint32_t failedCmd = FMT_FAILED;
    memcpy(m_pStream, &failedCmd, 4);
  }

  void serialize(const void* src, size_t sz) {
    if (m_writeOffset + sz > m_allocBottom)
      declareFailure();
    
     if (m_bFailed)
      return;

    memcpy(m_pStream + m_writeOffset, src, sz);
    m_writeOffset += sz;
  }

  void serialize(const std::string& s) {
    serialize(s.data(), s.size() + 1);
  }

  std::optional<uint32_t> allocate(const void* src, size_t sz) {
    if (m_writeOffset + sz > m_allocBottom)
      declareFailure();
    
    if (m_bFailed)
      return std::nullopt;

    m_allocBottom -= sz;
    memcpy(m_pStream + m_allocBottom, src, sz);
    return m_allocBottom;
  }

private:
  char* m_pStream;
  size_t m_streamSize;
  uint32_t m_writeOffset;
  uint32_t m_allocBottom;
  bool m_bFailed;
};
}
// the establishment is a flr --> script communication format consisting
// of mappings between string names and element IDs
void assembleEstablishmentPacket(Project* project, char* outStream, size_t streamSize) {
  const ParsedFlr& parsed = project->getParsedFlr();

  PacketWriter writer(outStream, streamSize);

  if (project->hasFailed()) {
    writer.declareFailure();
    return;
  }

  {
    uint32_t greetCmd = FMT_GREET;
    writer.serialize(&greetCmd, 4);
  }

  {
    uint32_t cmd = FMT_REINIT;
    writer.serialize(&cmd, 4);
  }

  for (uint32_t bidx = 0; bidx < parsed.m_buffers.size(); bidx++) {
    const ParsedFlr::BufferDesc& buf = parsed.m_buffers[bidx];
    const ParsedFlr::StructDef& str = parsed.m_structDefs[buf.structIdx];
    uint32_t bufType = buf.bCpuVisible ? 1u : 0u;
    uint32_t bufSize = buf.elemCount * str.size;
    uint32_t cmd[] = {FMT_BUFFER, bidx, bufSize, buf.bufferCount, bufType};
    writer.serialize(cmd, 20);
    writer.serialize(buf.name);
  }

  for (uint32_t cidx = 0; cidx < parsed.m_computeShaders.size(); cidx++) {
    const ParsedFlr::ComputeShader& cs = parsed.m_computeShaders[cidx];
    uint32_t cmd[] = {FMT_COMPUTE_SHADER, cidx};
    writer.serialize(cmd, 8);
    writer.serialize(cs.name);
  }

  for (uint32_t tidx = 0; tidx < parsed.m_taskBlocks.size(); tidx++) {
    const ParsedFlr::TaskBlock& tb = parsed.m_taskBlocks[tidx];
    uint32_t cmd[] = {FMT_TASK, tidx};
    writer.serialize(cmd, 8);
    writer.serialize(tb.name);
  }

  for (const ParsedFlr::ConstFloat& c : parsed.m_constFloats) {
    uint32_t cmd = FMT_CONST;
    writer.serialize(&cmd, 4);
    char type = 'f';
    writer.serialize(&type, 1);
    writer.serialize(&c.value, 4);
    writer.serialize(c.name);
  }

  for (const ParsedFlr::ConstUint& c : parsed.m_constUints) {
    uint32_t cmd = FMT_CONST;
    writer.serialize(&cmd, 4);
    char type = 'I';
    writer.serialize(&type, 1);
    writer.serialize(&c.value, 4);
    writer.serialize(c.name);
  }

  for (const ParsedFlr::ConstInt& c : parsed.m_constInts) {
    uint32_t cmd = FMT_CONST;
    writer.serialize(&cmd, 4);
    char type = 'i';
    writer.serialize(&type, 1);
    writer.serialize(&c.value, 4);
    writer.serialize(c.name);
  }

  char* pDynamicData = (char*)project->getDynamicDataPtr();
  uint32_t dynamicDataSize = static_cast<uint32_t>(project->getDynamicDataSize());
  {
    uint32_t uiCmdType = 0;
    uint32_t cmd[] = { FMT_UI, uiCmdType, dynamicDataSize };
    writer.serialize(&cmd, 12);
  }
    
  for (const ParsedFlr::SliderUint& slider : parsed.m_sliderUints) {
    uint32_t uiCmdType = 1;
    uint32_t ptrdif = static_cast<uint32_t>(((char*)slider.pValue) - pDynamicData);
    uint32_t cmd[] = { FMT_UI, uiCmdType, ptrdif };
    writer.serialize(&cmd, 12);
    writer.serialize(slider.name);
  }

  for (const ParsedFlr::SliderInt& slider : parsed.m_sliderInts) {
    uint32_t uiCmdType = 2;
    uint32_t ptrdif = static_cast<uint32_t>(((char*)slider.pValue) - pDynamicData);
    uint32_t cmd[] = { FMT_UI, uiCmdType, ptrdif };
    writer.serialize(&cmd, 12);
    writer.serialize(slider.name);
  }

  for (const ParsedFlr::SliderFloat& slider : parsed.m_sliderFloats) {
    uint32_t uiCmdType = 3;
    uint32_t ptrdif = static_cast<uint32_t>(((char*)slider.pValue) - pDynamicData);
    uint32_t cmd[] = { FMT_UI, uiCmdType, ptrdif };
    writer.serialize(&cmd, 12);
    writer.serialize(slider.name);
  }

  for (const ParsedFlr::Checkbox& checkbox : parsed.m_checkboxes) {
    uint32_t uiCmdType = 4;
    uint32_t ptrdif = static_cast<uint32_t>(((char*)checkbox.pValue) - pDynamicData);
    uint32_t cmd[] = { FMT_UI, uiCmdType, ptrdif };
    writer.serialize(&cmd, 12);
    writer.serialize(checkbox.name);
  }

  if (auto allocOffs = writer.allocate(pDynamicData, dynamicDataSize)) {
    uint32_t cmd[] = { FMT_UI_UPDATE, *allocOffs, dynamicDataSize };
    writer.serialize(cmd, 12);
  }

  {
    uint32_t finishCmd = FMT_FINISH;
    writer.serialize(&finishCmd, 4);
  }
}

void assembleUpdatePacket(Project* project, char* stream, size_t streamSize) {
  PacketWriter writer(stream, streamSize);

  if (project->hasFailed()) {
    writer.declareFailure();
    return;
  }

  {
    uint32_t greetCmd = FMT_GREET;
    writer.serialize(&greetCmd, 4);
  }

  char* pDynamicData = (char*)project->getDynamicDataPtr();
  uint32_t dynamicDataSize = static_cast<uint32_t>(project->getDynamicDataSize());
  if (auto allocOffs = writer.allocate(pDynamicData, dynamicDataSize)) {
    uint32_t cmd[] = { FMT_UI_UPDATE, *allocOffs, dynamicDataSize };
    writer.serialize(cmd, 12);
  }

  {
    uint32_t finishCmd = FMT_FINISH;
    writer.serialize(&finishCmd, 4);
  }
}
} // namespace flr_packets

// TODO - pass in desired shared buffer size from cmdline args... ? (still
// need to clamp)
#define BUF_SIZE (1 << 30)

IpcProgram::IpcProgram()
  : m_bInitialSetup(true) {
  m_writeDoneSemaphoreHandle = OpenSemaphoreW(
      SEMAPHORE_ALL_ACCESS,
      false,
      L"Global_FlrWriteDoneSemaphore");
  m_readDoneSemaphoreHandle = OpenSemaphoreW(
      SEMAPHORE_ALL_ACCESS,
      false,
      L"Global_FlrReadDoneSemaphore");
  m_sharedMemoryHandle =
      OpenFileMappingW(FILE_MAP_ALL_ACCESS, false, L"Global_FlrSharedMemory");
  m_sharedMemoryBuffer = nullptr;

  if (!m_writeDoneSemaphoreHandle || !m_readDoneSemaphoreHandle ||
      !m_sharedMemoryHandle) {
    std::cerr << "Could not initialize shared resources." << std::endl;
    throw std::runtime_error("Could not initialize shared resources.");
    return;
  }

  m_sharedMemoryBuffer =
      MapViewOfFile(m_sharedMemoryHandle, FILE_MAP_ALL_ACCESS, 0, 0, BUF_SIZE);

  if (!m_sharedMemoryBuffer) {
    std::cerr << "Could not map shared memory." << std::endl;
    throw std::runtime_error("Could not map shared memory.");
    return;
  }
  
  // The introduction params are populated into sharedmem before the flr app is launched,
  // so not initial synchronization is necessary for processing the introduction

  if (!flr_cmds::processIntroduction((const char*)m_sharedMemoryBuffer, BUF_SIZE, m_params)) {
    std::cerr << "Failed processing introduction cmdlist." << std::endl;
    throw std::runtime_error("Failed processing introduction cmdlist.");
    return;
  }
}

IpcProgram::~IpcProgram() {
  if (m_sharedMemoryBuffer)
    UnmapViewOfFile(m_sharedMemoryBuffer);

  if (m_writeDoneSemaphoreHandle)
    CloseHandle(m_writeDoneSemaphoreHandle);
  if (m_readDoneSemaphoreHandle)
    CloseHandle(m_readDoneSemaphoreHandle);
  if (m_sharedMemoryHandle)
    CloseHandle(m_sharedMemoryHandle);
}

void IpcProgram::setupParams(FlrParams& params) {
  params = m_params;
}

void IpcProgram::createRenderState(Project* project, SingleTimeCommandBuffer& commandBuffer) {
  // On initial setup, the invoking script launches the app and immediately waits for both the introduction
  // to be parsed and the establishment packet to be written. The app has logical ownership of the sharedmem
  // upon initial launch so no wait is necessary the first time around.
  if (!m_bInitialSetup)
    WaitForSingleObject(m_writeDoneSemaphoreHandle, INFINITE);
  flr_packets::assembleEstablishmentPacket(
    project,
    (char*)m_sharedMemoryBuffer,
    BUF_SIZE);

  ReleaseSemaphore(m_readDoneSemaphoreHandle, 1, nullptr);

  m_bInitialSetup = false;
}

void IpcProgram::destroyRenderState() {}

void IpcProgram::tick(Project* project, const FrameContext& frame) {}

void IpcProgram::draw(
    Project* project,
    VkCommandBuffer commandBuffer,
    const FrameContext& frame) {

  WaitForSingleObject(m_writeDoneSemaphoreHandle, INFINITE);

  bool result = flr_cmds::processCmdList(
      project,
      commandBuffer,
      frame,
      (char*)m_sharedMemoryBuffer,
      BUF_SIZE);
  if (!result)
    std::cerr << "Could not parse commandlist" << std::endl;
  flr_packets::assembleUpdatePacket(project, (char*)m_sharedMemoryBuffer, BUF_SIZE);

  ReleaseSemaphore(m_readDoneSemaphoreHandle, 1, nullptr);
}
} // namespace flr