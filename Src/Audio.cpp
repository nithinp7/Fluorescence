#include "Audio.h"

#include <stdio.h>
#include <cassert>
#include <Windows.h>
#include <mmreg.h>

#include <cstdint>

namespace flr {

// TODO: Rename class to something more descriptive...

Audio::Audio() : m_sampleOffset(0) {
  m_samples.resize(48000);

  HRESULT hr;
  IMMDeviceEnumerator* enumerator = nullptr;

  // Initializes the COM library
  hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  assert(SUCCEEDED(hr));

  hr = CoCreateInstance(
    __uuidof(MMDeviceEnumerator),
    nullptr,
    CLSCTX_ALL,
    __uuidof(IMMDeviceEnumerator),
    (void**)&enumerator
  );
  assert(SUCCEEDED(hr));

  // enumerate and choose recorder / renderer devices
  hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &m_pRecorder);
  assert(SUCCEEDED(hr));
  hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &m_pRenderer);
  assert(SUCCEEDED(hr));
  hr = enumerator->Release();
  assert(SUCCEEDED(hr));

  hr = m_pRecorder->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&m_pRecorderClient);
  assert(SUCCEEDED(hr));

  hr = m_pRenderer->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&m_pRenderClient);
  assert(SUCCEEDED(hr));

  hr = m_pRecorderClient->GetMixFormat(&m_pFormat);
  assert(SUCCEEDED(hr));

  printf("Mix format:\n");
  printf("  Frame size     : %d\n", m_pFormat->nBlockAlign);
  printf("  Channels       : %d\n", m_pFormat->nChannels);
  printf("  Bits per second: %d\n", m_pFormat->wBitsPerSample);
  printf("  Sample rate:   : %d\n", m_pFormat->nSamplesPerSec);

  // REVIEW BLOCK
  hr = m_pRecorderClient->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 10000000, 0, m_pFormat, nullptr);
  assert(SUCCEEDED(hr));

  hr = m_pRenderClient->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 10000000, 0, m_pFormat, nullptr);
  assert(SUCCEEDED(hr));

  hr = m_pRenderClient->GetService(__uuidof(IAudioRenderClient), (void**)&m_pRenderService);
  assert(SUCCEEDED(hr));

  hr = m_pRecorderClient->GetService(__uuidof(IAudioCaptureClient), (void**)&m_pCaptureService);
  assert(SUCCEEDED(hr));


  hr = m_pRecorderClient->Start();
  assert(SUCCEEDED(hr));

  hr = m_pRenderClient->Start();
  assert(SUCCEEDED(hr));

}

Audio::~Audio() {
  m_pRecorderClient->Stop();
  m_pRenderClient->Stop();

  m_pCaptureService->Release();
  m_pRenderService->Release();

  m_pRecorderClient->Release();
  m_pRenderClient->Release();

  m_pRecorder->Release();
  m_pRenderer->Release();

  CoUninitialize();
}

void Audio::play() {
  HRESULT hr;
  uint32_t nFrames;
  DWORD flags;
  BYTE* captureBuffer;
  BYTE* renderBuffer;

  while (true)
  {
    hr = m_pCaptureService->GetBuffer(&captureBuffer, &nFrames, &flags, nullptr, nullptr);
    assert(SUCCEEDED(hr));
    if (!nFrames)
      break;

    hr = m_pCaptureService->ReleaseBuffer(nFrames);
    assert(SUCCEEDED(hr));

    // hr = m_pRenderService->GetBuffer(nFrames, &renderBuffer);
    // assert(SUCCEEDED(hr));

    //float qdenom = static_cast<float>((1u << (m_pFormat->wBitsPerSample - 1)) - 1u);

    for (int i = 0; i < nFrames; i++) {
      BYTE* offs = captureBuffer + i * m_pFormat->nBlockAlign;
      float c0 = *reinterpret_cast<float*>(offs);
      float c1 = *reinterpret_cast<float*>(offs + 4);
      //float c0 = *reinterpret_cast<uint32_t*>(offs) / qdenom;
      //float c1 = *reinterpret_cast<uint32_t*>(offs + 4) / qdenom;

      m_samples[m_sampleOffset++ % m_samples.size()] = c0;
    }

    // memcpy(renderBuffer, captureBuffer, m_pFormat->nBlockAlign * nFrames);

    // hr = m_pRenderService->ReleaseBuffer(nFrames, 0);
    // assert(SUCCEEDED(hr));
  }
}

void Audio::copySamples(float* dst, uint32_t count) const {
  for (uint32_t i = 0; i < count; i++) {
    uint32_t idx = (m_sampleOffset - i - 1) % m_samples.size();
    dst[i] = m_samples[idx];
  }
}
} // namespace flr