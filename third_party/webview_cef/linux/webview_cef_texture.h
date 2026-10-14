#ifndef WEBVIEW_CEF_TEXTURE_H_
#define WEBVIEW_CEF_TEXTURE_H_
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <memory>
#include <mutex>
#include <vector>
#include "sirb_pixels.h"

using SirbPixelFrame = sirb::PixelFrame;
struct SirbTextureFrames {
  std::mutex mutex;
  sirb::PixelFramePool pool; // Accessed only by the serialized CEF producer.
  std::shared_ptr<SirbPixelFrame> latest;
  // Only changed on Flutter's raster thread. It owns the returned bytes until
  // the next copy_pixels call, after the previous GL upload has completed.
  std::shared_ptr<SirbPixelFrame> raster;

  SirbTextureFrames() {
    latest = std::make_shared<SirbPixelFrame>(1, 1);
    raster = latest;
  }
};
struct WebviewCefTexture { FlPixelBufferTexture parent_instance; SirbTextureFrames* frames; };
struct WebviewCefTextureClass { FlPixelBufferTextureClass parent_class; };
G_DEFINE_TYPE(WebviewCefTexture, webview_cef_texture, fl_pixel_buffer_texture_get_type())
#define WEBVIEW_CEF_TEXTURE(obj) (G_TYPE_CHECK_INSTANCE_CAST((obj), webview_cef_texture_get_type(), WebviewCefTexture))
static gboolean webview_cef_texture_copy_pixels(FlPixelBufferTexture* texture, const uint8_t** buffer,
  uint32_t* width, uint32_t* height, GError** error) {
  auto* state = WEBVIEW_CEF_TEXTURE(texture)->frames;
  if (!state) {
    if (error) {
      g_set_error(error, g_quark_from_static_string("webview_cef"), 1, "Texture frames uninitialized");
    }
    return FALSE;
  }
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->latest) {
      state->raster = state->latest;
    }
  }
  if (!state->raster || state->raster->pixels.empty()) {
    state->raster = std::make_shared<SirbPixelFrame>(1, 1);
  }
  *buffer = state->raster->pixels.data();
  *width = state->raster->width;
  *height = state->raster->height;
  return TRUE;
}
static void webview_cef_texture_finalize(GObject* object) {
  delete WEBVIEW_CEF_TEXTURE(object)->frames;
  G_OBJECT_CLASS(webview_cef_texture_parent_class)->finalize(object);
}
static void webview_cef_texture_class_init(WebviewCefTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = webview_cef_texture_copy_pixels;
  G_OBJECT_CLASS(klass)->finalize = webview_cef_texture_finalize;
}
static void webview_cef_texture_init(WebviewCefTexture* self) { self->frames = new SirbTextureFrames(); }
static WebviewCefTexture* webview_cef_texture_new() {
  return WEBVIEW_CEF_TEXTURE(g_object_new(webview_cef_texture_get_type(), nullptr));
}
#endif
