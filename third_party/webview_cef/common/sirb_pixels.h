#ifndef SIRB_PIXELS_H_
#define SIRB_PIXELS_H_

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>
#if defined(__SSE2__) || defined(_M_X64)
#include <emmintrin.h>
#elif defined(_M_ARM64) && defined(_MSC_VER) && !defined(__clang__)
#include <arm64_neon.h>
#elif defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#endif

namespace sirb {
// CEF BGRA -> Flutter RGBA; both buffers may be unaligned. Preserve alpha.
inline void bgraToRgba(void* destination, const void* source, size_t pixels) {
  auto* dst = static_cast<uint8_t*>(destination);
  const auto* src = static_cast<const uint8_t*>(source);
  size_t i = 0;
#if defined(__SSE2__) || defined(_M_X64)
  const auto ga = _mm_set1_epi32(static_cast<int>(0xff00ff00u));
  const auto channel = _mm_set1_epi32(0x000000ff);
  for (; i + 4 <= pixels; i += 4) {
    const auto bgra = _mm_loadu_si128(reinterpret_cast<const __m128i*>(src + i*4));
    const auto rb = _mm_or_si128(
        _mm_slli_epi32(_mm_and_si128(bgra, channel), 16),
        _mm_and_si128(_mm_srli_epi32(bgra, 16), channel));
    _mm_storeu_si128(reinterpret_cast<__m128i*>(dst + i*4),
                    _mm_or_si128(_mm_and_si128(bgra, ga), rb));
  }
#elif defined(__aarch64__) || defined(_M_ARM64)
  for (; i + 16 <= pixels; i += 16) {
    auto channels = vld4q_u8(src + i*4);
    const auto blue = channels.val[0];
    channels.val[0] = channels.val[2];
    channels.val[2] = blue;
    vst4q_u8(dst + i*4, channels);
  }
#endif
  for (; i < pixels; ++i) {
    const auto blue = src[i*4];
    const auto green = src[i*4+1];
    const auto red = src[i*4+2];
    const auto alpha = src[i*4+3];
    dst[i*4] = red; dst[i*4+1] = green;
    dst[i*4+2] = blue; dst[i*4+3] = alpha;
  }
}

struct PixelFrame {
  uint32_t width, height;
  std::vector<uint8_t> pixels;
  PixelFrame(uint32_t w, uint32_t h)
      : width(w), height(h), pixels(static_cast<size_t>(w)*h*4, 0) {}
};

// Producer-side bounded pool. Caller serializes acquire; published frames stay
// immutable until ALL consumers release them (including Flutter's GL upload).
class PixelFramePool {
 public:
  std::shared_ptr<PixelFrame> acquire(uint32_t width, uint32_t height) {
    if (width != width_ || height != height_) {
      frames_.clear(); // Consumers retain old-size frames until upload finishes.
      width_ = width; height_ = height;
    }
    for (const auto& frame : frames_) {
      if (frame.use_count() == 1) return frame;
    }
    if (frames_.size() >= 3) return nullptr; // Backpressure, never overwrite/upload race.
    auto frame = std::make_shared<PixelFrame>(width, height);
    frames_.push_back(frame);
    return frame;
  }
 private:
  uint32_t width_ = 0, height_ = 0;
  std::vector<std::shared_ptr<PixelFrame>> frames_;
};
} // namespace sirb
#endif
