// Standalone native regression: c++ -std=c++20 -O2 -pthread tool/test_pixels.cc -o /tmp/sirb-pixels && /tmp/sirb-pixels
#include "../third_party/webview_cef/common/sirb_pixels.h"
#include <cassert>
#include <chrono>
#include <iostream>
#include <thread>
#include <mutex>

int main() {
  for (size_t count = 0; count < 100; ++count) {
    std::vector<uint8_t> src(count*4+2), dst(count*4+2, 0x55);
    for (size_t i=0; i<count*4; ++i) src[i+1] = static_cast<uint8_t>(i*13+7);
    sirb::bgraToRgba(dst.data()+1, src.data()+1, count);
    assert(dst.front() == 0x55 && dst.back() == 0x55);
    for (size_t i=0; i<count; ++i) {
      assert(dst[i*4+1] == src[i*4+3]);
      assert(dst[i*4+2] == src[i*4+2]);
      assert(dst[i*4+3] == src[i*4+1]);
      assert(dst[i*4+4] == src[i*4+4]);
    }
    auto inPlace = src;
    sirb::bgraToRgba(inPlace.data()+1, inPlace.data()+1, count);
    for(size_t i=0; i<count*4; ++i) assert(inPlace[i+1] == dst[i+1]);
  }
  sirb::PixelFramePool pool;
  auto a = pool.acquire(8, 4), b = pool.acquire(8, 4), c = pool.acquire(8, 4);
  assert(a != b && b != c && a != c);
  assert(!pool.acquire(8, 4));
  auto* released = b.get(); b.reset();
  assert(pool.acquire(8, 4).get() == released);
  a->pixels[0] = 99;
  auto resized = pool.acquire(16, 8);
  assert(resized->width == 16 && a->width == 8 && a->pixels[0] == 99);

  // Slow concurrent raster upload must always see an immutable full frame.
  sirb::PixelFramePool concurrentPool;
  std::mutex mutex;
  std::shared_ptr<sirb::PixelFrame> latest;
  bool finished = false;
  std::thread raster([&] {
    while(true) {
      std::shared_ptr<sirb::PixelFrame> held;
      bool done;
      { std::lock_guard<std::mutex> lock(mutex); held=latest; done=finished; }
      if(held) {
        const auto value=held->pixels[0];
        std::this_thread::sleep_for(std::chrono::microseconds(20));
        for(auto byte:held->pixels) assert(byte == value);
      }
      if(done) break;
    }
  });
  for(int i=0; i<10000; ++i) {
    auto frame=concurrentPool.acquire(32, 16);
    assert(frame);
    std::fill(frame->pixels.begin(), frame->pixels.end(), static_cast<uint8_t>(i));
    { std::lock_guard<std::mutex> lock(mutex); latest=frame; }
  }
  { std::lock_guard<std::mutex> lock(mutex); finished=true; }
  raster.join();
  std::cout << "Pixel conversion, bounded reuse, resize and concurrent upload passed\n";
}
