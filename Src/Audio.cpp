#include "Audio.h"

#include <stdio.h>
#include <cassert>
#include <Windows.h>
#include <mmreg.h>

#include <cstdint>

namespace flr {

// TODO: Rename class to something more descriptive...

Audio::Audio(bool bLoopBack) : m_bLoopBack(bLoopBack), m_sampleOffset(0) {
  m_samples.resize(4800);

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
  if (m_bLoopBack)
    hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &m_pRecorder);
  else
    hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &m_pRecorder);

  assert(SUCCEEDED(hr));
  hr = enumerator->Release();
  assert(SUCCEEDED(hr));

  hr = m_pRecorder->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&m_pRecorderClient);
  assert(SUCCEEDED(hr));

  hr = m_pRecorderClient->GetMixFormat(&m_pFormat);
  assert(SUCCEEDED(hr));

  hr = m_pRecorderClient->Initialize(AUDCLNT_SHAREMODE_SHARED, m_bLoopBack ? AUDCLNT_STREAMFLAGS_LOOPBACK : 0, 10000000, 0, m_pFormat, nullptr);
  assert(SUCCEEDED(hr));

  hr = m_pRecorderClient->GetService(__uuidof(IAudioCaptureClient), (void**)&m_pCaptureService);
  assert(SUCCEEDED(hr));

  hr = m_pRecorderClient->Start();
  assert(SUCCEEDED(hr));
}

Audio::~Audio() {
  m_pRecorderClient->Stop();

  m_pCaptureService->Release();
  m_pRecorderClient->Release();
  m_pRecorder->Release();

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

    uint32_t reductionFactor = 1;

    WAVEFORMATEXTENSIBLE* format = reinterpret_cast<WAVEFORMATEXTENSIBLE*>(m_pFormat);
    if (format->SubFormat.Data1 == WAVE_FORMAT_IEEE_FLOAT) {
      for (int i = 0; i < nFrames; i+=reductionFactor) {
        float avg = 0.0f;
        for (int j = i; j < i + reductionFactor; j++) {
          BYTE* offs = captureBuffer + j * m_pFormat->nBlockAlign;
          float c0 = *reinterpret_cast<float*>(offs);
          float c1 = *reinterpret_cast<float*>(offs + 4);

          avg += 0.5f * (c0 + c1) / reductionFactor;
        }

        m_samples[m_sampleOffset++ % m_samples.size()] = avg;
      }
    }
    else {
      //float qdenom = static_cast<float>((1u << (m_pFormat->wBitsPerSample - 1)) - 1u);
      //float c0 = *reinterpret_cast<uint32_t*>(offs) / qdenom;
      //float c1 = *reinterpret_cast<uint32_t*>(offs + 4) / qdenom;
      assert(false);
    }
  }
}

void Audio::copySamples(float* dst, uint32_t count) const {
  for (uint32_t i = 0; i < count; i++) {
    uint32_t idx = (m_sampleOffset - count + i) % m_samples.size();
    dst[i] = m_samples[idx];
  }
}

void Audio::DCT2_naive(float* coeffs, uint32_t K) const {
  uint32_t skip = 4;
  uint32_t N = m_samples.size() / skip;

  float PI = 3.14159265359f;
  for (uint32_t k = 0; k < K; k++) {
    coeffs[k] = 0.0f;
  }

  for (uint32_t n = 0; n < N; n++) {
    float xn = m_samples[(m_sampleOffset + n*skip)%m_samples.size()];
    float freqScale = PI / K * (n + 0.5f);
    for (uint32_t k = 0; k < K; k++) {
      float f = cos(freqScale * k);
      coeffs[k] += xn * f;
    }
  }

  float sqrt_2overN = sqrt(2.0 / K);
  coeffs[0] *= 1.0 / sqrt(K);
  for (uint32_t k = 1; k < K; k++) {
    coeffs[k] *= sqrt_2overN;
  }
}

/*static*/
void Audio::DCT2_naive(float* coeffs, const float* samples, uint32_t N) {
  //float* norm = (float*)alloca(sizeof(float) * N);

  float PI = 3.14159265359f;
  for (uint32_t k = 0; k < N; k++) {
    coeffs[k] = 0.0f;
    //norm[k] = 0.0f;
  }

  for (uint32_t n = 0; n < N; n++) {
    float xn = samples[n];
    float freqScale = PI / N * (n + 0.5f);
    for (uint32_t k = 0; k < N; k++) {
      float f = cos(freqScale * k);
      coeffs[k] += xn * f;
      //norm[k] += f;
    }
  }

  float sqrt_2overN = sqrt(2.0 / N);
  coeffs[0] *= 1.0 / sqrt(N);
  for (uint32_t k = 1; k < N; k++) {
    coeffs[k] *= sqrt_2overN;
  }
}
} // namespace flr