
#include <initguid.h>
#include <mmdeviceapi.h>
#include <Audioclient.h>

#include <vector>

namespace flr {
class Audio { // TODO: better name
public:
  Audio(bool bLoopBack);
  ~Audio();

  void play();
  void copySamples(float* dst, uint32_t count) const;

  static void DCT2_naive(float* coeffs, const float* samples, uint32_t N);

private:
  bool m_bLoopBack = false;

  IMMDevice* m_pRecorder;
  IAudioClient* m_pRecorderClient;
  IAudioCaptureClient* m_pCaptureService;
  WAVEFORMATEX* m_pFormat;

  uint32_t m_sampleOffset;
  std::vector<float> m_samples;
};
} // namespace flr