// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "webview_handler.h"
#include "sirb_config.h"
#include "sirb_policy.h"

#include <sstream>
#include <string>
#include <iostream>
#include <chrono>
#include <unordered_map>
#include <cstdint>
#include <cmath>

#include "include/base/cef_callback.h"
#include "include/cef_app.h"
#include "include/cef_parser.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/wrapper/cef_helpers.h"

#include <sstream>

// std::to_string fails for ints on Ubuntu 24.04:
// webview_handler.cc:86:86: error: no matching function for call to 'to_string'
// webview_handler.cc:567:24: error: no matching function for call to 'to_string'
namespace stringpatch
{
    template < typename T > std::string to_string( const T& n )
    {
        std::ostringstream stm ;
        stm << n ;
        return stm.str() ;
    }
}

#include "webview_js_handler.h"
#include "sirb_native.inc"
#include "sirb_game_window.inc"

namespace {
// The only browser that currently get focused
CefRefPtr<CefBrowser> current_focused_browser_ = nullptr;


}  // namespace

WebviewHandler::WebviewHandler() {

}

WebviewHandler::~WebviewHandler() {
    browser_map_.clear();
    js_callbacks_.clear();
}

bool WebviewHandler::OnProcessMessageReceived(
    CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
     CefProcessId source_process, CefRefPtr<CefProcessMessage> message)
{
	std::string message_name = message->GetName();
    if (message_name == kFocusedNodeChangedMessage)
    {
        auto focused=browser_map_.find(browser->GetIdentifier());
        if(focused!=browser_map_.end()&&focused->second.wants_focus&&browser->GetHost()->IsWindowRenderingDisabled())current_focused_browser_=browser;
        bool editable = message->GetArgumentList()->GetBool(0);
        onFocusedNodeChangeMessage(browser->GetIdentifier(), editable);
        if (editable) {
            onImeCompositionRangeChangedMessage(browser->GetIdentifier(), message->GetArgumentList()->GetInt(1), message->GetArgumentList()->GetInt(2), message->GetArgumentList()->GetInt(3));
        }
    }
    else if(message_name == kJSCallCppFunctionMessage)
    {
        CefString fun_name = message->GetArgumentList()->GetString(0);
		CefString param = message->GetArgumentList()->GetString(1);
		int js_callback_id = message->GetArgumentList()->GetInt(2);

        if (fun_name.empty() || !(browser.get())) {
		    return false;
	    }

        onJavaScriptChannelMessage(
            fun_name,param,stringpatch::to_string(js_callback_id), browser->GetIdentifier(), frame->GetIdentifier().ToString());
    }
    else if(message_name == kEvaluateCallbackMessage){
        CefString callbackId = message->GetArgumentList()->GetString(0);
        CefRefPtr<CefValue> param = message->GetArgumentList()->GetValue(1);

        if(!callbackId.empty()){
            auto it = js_callbacks_.find(callbackId.ToString());
            if(it != js_callbacks_.end()){
                it->second(param);
                js_callbacks_.erase(it);
            }
        }
    }
    return false;
}

void WebviewHandler::OnTitleChange(CefRefPtr<CefBrowser> browser,
                                  const CefString& title) {
    if (!browser->GetHost()->IsWindowRenderingDisabled()) {
        auto view = CefBrowserView::GetForBrowser(browser);
        if (view && view->GetWindow()) view->GetWindow()->SetTitle(title);
    }
    if(onTitleChangedEvent) {
        onTitleChangedEvent(browser->GetIdentifier(), title);
    }
}

void WebviewHandler::OnAddressChange(CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame,
                     const CefString& url) {
    if (frame->IsMain()) {
        std::lock_guard<std::mutex> lock(sirb_config.mutex);
        sirb_config.topHosts[browser->GetIdentifier()] = sirb_host(url);
    }
    if(frame->IsMain() && onUrlChangedEvent) {
        onUrlChangedEvent(browser->GetIdentifier(), url);
    }
}

bool WebviewHandler::OnCursorChange(CefRefPtr<CefBrowser> browser,
                            CefCursorHandle cursor,
                            cef_cursor_type_t type,
                            const CefCursorInfo& custom_cursor_info){
    if(onCursorChangedEvent) {
        onCursorChangedEvent(browser->GetIdentifier(), type);
        return true;
    }
    return false;
}

bool WebviewHandler::OnTooltip(CefRefPtr<CefBrowser> browser, CefString& text) {
    if(onTooltipEvent) {
        onTooltipEvent(browser->GetIdentifier(), text);
        return true;
    }
    return false;
}

bool WebviewHandler::OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                                      cef_log_severity_t level,
                                      const CefString& message,
                                      const CefString& source,
                                      int line){
    if (!browser->GetHost()->IsWindowRenderingDisabled()) {
        const std::string text = message;
        if (text.rfind("__sirb__", 0) == 0) {
            auto value = CefParseJSON(text.substr(8), JSON_PARSER_RFC);
            if (value && value->GetType() == VTYPE_DICTIONARY) {
                const std::string type = value->GetDictionary()->GetString("type");
                // Website console traffic cannot forge native lifecycle/popup
                // events. Only diagnostic payloads enter the native-window bridge.
                if (type == "runtimeError" || type == "adError")
                    sirbEvent(browser->GetIdentifier(), text.substr(8));
            }
        } else if (level >= LOGSEVERITY_WARNING && level <= LOGSEVERITY_FATAL) {
            auto event = CefDictionaryValue::Create();
            event->SetString("type", "runtimeError"); event->SetString("category", "javascript");
            event->SetString("message", message); event->SetString("source", source);
            event->SetInt("line", line); event->SetInt("severity", level);
            sirbEvent(browser->GetIdentifier(), sirb_json(event));
        }
    } else if(onConsoleMessageEvent){
        onConsoleMessageEvent(browser->GetIdentifier(), level, message, source, line);
    }
    return false;
}

void WebviewHandler::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();
    {std::lock_guard<std::mutex> lock(sirb_config.mutex);sirb_config.browsers[browser->GetIdentifier()]=browser;}
    if (!browser->IsPopup()) {
        browser_map_.emplace(browser->GetIdentifier(), browser_info());
        browser_map_[browser->GetIdentifier()].browser = browser;
    }
}

bool WebviewHandler::DoClose(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();    
    // Allow the close. For windowed browsers this will result in the OS close
    // event being sent.
    return false;
}

void WebviewHandler::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();
    if (current_focused_browser_ && current_focused_browser_->IsSame(browser)) current_focused_browser_ = nullptr;
    if (!browser->GetHost()->IsWindowRenderingDisabled()) {
        auto event = CefDictionaryValue::Create(); event->SetString("type", "gameWindowClosed");
        sirbEvent(browser->GetIdentifier(), sirb_json(event));
    }
    browser_map_.erase(browser->GetIdentifier());
    std::lock_guard<std::mutex> lock(sirb_config.mutex);
    sirb_config.topHosts.erase(browser->GetIdentifier());
    sirb_config.browsers.erase(browser->GetIdentifier());
    sirb_config.speculative.erase(browser->GetIdentifier());
}

bool WebviewHandler::OnBeforePopup(CefRefPtr<CefBrowser> browser,
                                  CefRefPtr<CefFrame> frame,
                                  int popup_id,
                                  const CefString& target_url,
                                  const CefString& target_frame_name,
                                  CefLifeSpanHandler::WindowOpenDisposition target_disposition,
                                  bool user_gesture,
                                  const CefPopupFeatures& popupFeatures,
                                  CefWindowInfo& windowInfo,
                                  CefRefPtr<CefClient>& client,
                                  CefBrowserSettings& settings,
                                  CefRefPtr<CefDictionaryValue>& extra_info,
                                  bool* no_javascript_access) {
    if(!user_gesture)return true;
    auto value = CefDictionaryValue::Create();
    value->SetString("type", "popup"); value->SetString("url", target_url);
    value->SetBool("background", target_disposition == CEF_WOD_NEW_BACKGROUND_TAB);
    sirbEvent(browser->GetIdentifier(), sirb_json(value));
    return true;
}

void WebviewHandler::OnTakeFocus(CefRefPtr<CefBrowser> browser, bool next)
{
    // OSR has no native next/previous control. Do not blur the DOM input here:
    // that destroys the caret/selection when CEF temporarily yields focus.
}

bool WebviewHandler::OnSetFocus(CefRefPtr<CefBrowser> browser, FocusSource source)
{
    // Native game windows own their real Chromium focus/input pipeline.
    if (!browser->GetHost()->IsWindowRenderingDisabled()) return false;
    // Flutter owns focus. Loading a background page must not steal it.
    const auto it = browser_map_.find(browser->GetIdentifier());
    return it == browser_map_.end() || !it->second.wants_focus;
}

void WebviewHandler::OnGotFocus(CefRefPtr<CefBrowser> browser)
{
}

void WebviewHandler::OnLoadError(CefRefPtr<CefBrowser> browser,
                                CefRefPtr<CefFrame> frame,
                                ErrorCode errorCode,
                                const CefString& errorText,
                                const CefString& failedUrl) {
    CEF_REQUIRE_UI_THREAD();

    // Don't display an error for downloaded files.
    if (errorCode == ERR_ABORTED)
        return;
    
    if (!frame->IsMain()) return;
    auto event = CefDictionaryValue::Create(); event->SetString("type", "loadError");
    event->SetString("error", errorText); event->SetString("url", failedUrl);
    event->SetInt("code", static_cast<int>(errorCode));
    sirbEvent(browser->GetIdentifier(), sirb_json(event));
}

void WebviewHandler::OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                                 CefLoadHandler::TransitionType transition_type) {
    if(frame->IsMain() && onLoadStart){
        onLoadStart(browser->GetIdentifier(), frame->GetURL());
    }
    return;
}

void WebviewHandler::OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                               int httpStatusCode) {
    if(frame->IsMain() && onLoadEnd){
        onLoadEnd(browser->GetIdentifier(), frame->GetURL());
    }
    return;
}

void WebviewHandler::CloseAllBrowsers(bool force_close) {
    if (!CefCurrentlyOn(TID_UI)) {if(CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::CloseAllBrowsers,this,force_close)))return;}
    if (browser_map_.empty()){
        return;
    }
    
    // CloseBrowser can reenter OnBeforeClose, which erases this map. Keep
    // strong references in a snapshot, not iterators into the callback's map.
    const auto closing = browser_map_;
    browser_map_.clear();
    for (const auto& entry : closing) {
        entry.second.browser->GetHost()->CloseBrowser(force_close);
    }
}

void WebviewHandler::closeBrowser(int browserId)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::closeBrowser, this, browserId));
        return;
    }
    auto it = browser_map_.find(browserId);
    if(it != browser_map_.end()){
        const auto browser = it->second.browser;
        browser_map_.erase(it);
        browser->GetHost()->CloseBrowser(true);
    }
}

void WebviewHandler::createBrowser(std::string url, bool speculative, std::function<void(int)> callback)
{
#ifndef OS_MAC
    if(!CefCurrentlyOn(TID_UI)) {
		CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::createBrowser, this, url, speculative, callback));
		return;
	}
#endif
    CefBrowserSettings browser_settings ;
    // Capped at 60 by CEF; ignored entirely when external begin frame drives the
    // frames (GPU path below). Kept for the software fallback path.
    browser_settings.windowless_frame_rate = 60;
    browser_settings.javascript_access_clipboard = STATE_ENABLED;
    CefWindowInfo window_info;
    window_info.SetAsWindowless(0);
#ifdef WEBVIEW_CEF_GPU_TEXTURE
    // Enable GPU shared-texture rendering: CEF delivers frames via
    // OnAcceleratedPaint (a D3D11 shared texture on Windows, an IOSurface on
    // macOS) instead of the software OnPaint CPU buffer. Requires the GPU to be
    // left enabled (see WebviewApp).
    window_info.shared_texture_enabled = sirb_gpu_enabled();
    // Drive frame production ourselves so the rate can follow the display's
    // refresh (>60 Hz) instead of being capped at windowless_frame_rate. The
    // platform layer ticks SendExternalBeginFrame on each vblank — Windows from
    // an IDXGIOutput vblank wait, macOS from a CVDisplayLink.
    window_info.external_begin_frame_enabled = sirb_gpu_enabled();
#endif
    auto extra = CefDictionaryValue::Create();
    {
        std::lock_guard<std::mutex> lock(sirb_config.mutex);
        extra->SetString("sirbToken",sirb_config.policy_key);
    }
    auto context = CefRequestContext::CreateContext(CefRequestContext::GetGlobalContext(), this);
    context->RegisterSchemeHandlerFactory("sirb","config",new SirbPolicyFactory());
    auto browser = CefBrowserHost::CreateBrowserSync(window_info, this, url, browser_settings, extra, context);
    if(browser){std::lock_guard<std::mutex> lock(sirb_config.mutex);sirb_config.speculative[browser->GetIdentifier()]=speculative;}
    callback(browser?browser->GetIdentifier():-1);
#ifdef WEBVIEW_CEF_GPU_TEXTURE
    // The GPU shared-texture path is the only render path on this build (no
    // OnPaint fallback). If no accelerated frame arrives shortly, the GPU
    // compositor likely can't export a shared texture — warn so a black webview
    // isn't silent.
    CefPostDelayedTask(TID_UI, base::BindOnce(&WebviewHandler::warnIfNoAcceleratedFrame, this), 5000);
#endif
}

void WebviewHandler::warnIfNoAcceleratedFrame() {
#ifdef WEBVIEW_CEF_GPU_TEXTURE
    if (sirb_gpu_enabled() && !received_accelerated_frame_ && !gpu_warning_logged_) {
        gpu_warning_logged_ = true;
        fprintf(stderr,
                "[webview_cef] WARNING: no GPU accelerated-paint frame after 5s. "
                "This build renders the webview only via the GPU shared-texture "
                "path; if it appears black, the GPU compositor may be unavailable "
                "(headless, VM, software GL, or a crashed GPU process).\n");
        fflush(stderr);
    }
#endif
}

void WebviewHandler::sendExternalBeginFrame() {
#ifdef WEBVIEW_CEF_GPU_TEXTURE
    if (!sirb_gpu_enabled()) return;
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::sendExternalBeginFrame, this));
        return;
    }
    for (auto& kv : browser_map_) {
        if (!kv.second.hidden && kv.second.browser && kv.second.browser->GetHost() &&
            kv.second.browser->GetHost()->IsWindowRenderingDisabled()) {
            kv.second.browser->GetHost()->SendExternalBeginFrame();
        }
    }
#endif
}

void WebviewHandler::sendScrollEvent(int browserId, int x, int y, int deltaX, int deltaY) {
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::sendScrollEvent,this,browserId,x,y,deltaX,deltaY));return;}

    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        CefMouseEvent ev;
        ev.x = x;
        ev.y = y;
        it->second.browser->GetHost()->SendMouseWheelEvent(ev, deltaX, deltaY);
    }
}

void WebviewHandler::changeSize(int browserId, float a_dpi, int w, int h)
{
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::changeSize,this,browserId,a_dpi,w,h));return;}
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        if (w >= 0 && h >= 0 && it->second.width == static_cast<uint32_t>(w) && it->second.height == static_cast<uint32_t>(h) && std::abs(it->second.dpi - a_dpi) < 0.001f) {
            return;
        }
        bool dpi_changed = std::abs(it->second.dpi - a_dpi) >= 0.001f;
        it->second.dpi = a_dpi;
        it->second.width = w;
        it->second.height = h;
        auto host = it->second.browser->GetHost();
        if (dpi_changed) {
            host->NotifyScreenInfoChanged();
        }
        host->WasResized();
        host->Invalidate(PET_VIEW);
#ifdef WEBVIEW_CEF_GPU_TEXTURE
        host->SendExternalBeginFrame();
#endif
    }
}

void WebviewHandler::cursorClick(int browserId, int x, int y, bool up, int button)
{
    if (button < 0 || button > 2) return;
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::cursorClick,this,browserId,x,y,up,button));return;}
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        CefMouseEvent ev;
        ev.x = x;
        ev.y = y;
        CefBrowserHost::MouseButtonType btnType = CefBrowserHost::MouseButtonType::MBT_LEFT;
        uint32_t btnModifier = EVENTFLAG_LEFT_MOUSE_BUTTON;
        if (button == 2) {
            btnType = CefBrowserHost::MouseButtonType::MBT_RIGHT;
            btnModifier = EVENTFLAG_RIGHT_MOUSE_BUTTON;
        } else if (button == 1) {
            btnType = CefBrowserHost::MouseButtonType::MBT_MIDDLE;
            btnModifier = EVENTFLAG_MIDDLE_MOUSE_BUTTON;
        }
        ev.modifiers = btnModifier;
        if(up && it->second.is_dragging) {
            it->second.browser->GetHost()->DragTargetDrop(ev);
            it->second.browser->GetHost()->DragSourceSystemDragEnded();
            it->second.is_dragging = false;
        } else {
            if (!up) {
                int64_t now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now().time_since_epoch()).count();
                if ((now_ms - it->second.last_click_time_ms <= 500) &&
                    (std::abs(x - it->second.last_click_x) <= 6) &&
                    (std::abs(y - it->second.last_click_y) <= 6)) {
                    it->second.current_click_count = (it->second.current_click_count % 3) + 1;
                } else {
                    it->second.current_click_count = 1;
                }
                it->second.last_click_x = x;
                it->second.last_click_y = y;
                it->second.last_click_time_ms = now_ms;
            }
            it->second.browser->GetHost()->SendMouseClickEvent(
                ev, btnType, up, it->second.current_click_count);
        }
    }
}

void WebviewHandler::cursorMove(int browserId, int x , int y, bool dragging)
{
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::cursorMove,this,browserId,x,y,dragging));return;}
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        CefMouseEvent ev;
        ev.x = x;
        ev.y = y;
        if(dragging) {
            ev.modifiers = EVENTFLAG_LEFT_MOUSE_BUTTON;
            if (std::abs(x - it->second.last_click_x) > 6 || std::abs(y - it->second.last_click_y) > 6) {
                it->second.last_click_time_ms = 0;
            }
        }
        if(it->second.is_dragging && dragging) {
            it->second.browser->GetHost()->DragTargetDragOver(ev, DRAG_OPERATION_EVERY);
        } else {
            it->second.browser->GetHost()->SendMouseMoveEvent(ev, false);
        }
    }
}

bool WebviewHandler::StartDragging(CefRefPtr<CefBrowser> browser,
                                  CefRefPtr<CefDragData> drag_data,
                                  DragOperationsMask allowed_ops,
                                  int x,
                                  int y){
    auto it = browser_map_.find(browser->GetIdentifier());
    if (it != browser_map_.end() && it->second.browser->IsSame(browser)) {
        CefMouseEvent ev;
        ev.x = x;
        ev.y = y;
        ev.modifiers = EVENTFLAG_LEFT_MOUSE_BUTTON;
        it->second.browser->GetHost()->DragTargetDragEnter(drag_data, ev, DRAG_OPERATION_EVERY);
        it->second.is_dragging = true;
    }
    return true;
}

void WebviewHandler::OnImeCompositionRangeChanged(CefRefPtr<CefBrowser> browser, const CefRange &selection_range, const CefRenderHandler::RectList &character_bounds)
{
    CEF_REQUIRE_UI_THREAD();
    auto it = browser_map_.find(browser->GetIdentifier());
    if(it == browser_map_.end() || !it->second.browser.get() || browser->IsPopup()) {
        return;
    }
    if (!character_bounds.empty()) {
        if (it->second.is_ime_commit) {
            auto lastCharacter = character_bounds.back();
            it->second.prev_ime_position = lastCharacter;
            onImeCompositionRangeChangedMessage(browser->GetIdentifier(), lastCharacter.x + lastCharacter.width, lastCharacter.y + lastCharacter.height, lastCharacter.height);
            it->second.is_ime_commit = false;
        }
        else
        {
            auto firstCharacter = character_bounds.front();
            if (firstCharacter != it->second.prev_ime_position) {
                it->second.prev_ime_position = firstCharacter;
                onImeCompositionRangeChangedMessage(browser->GetIdentifier(), firstCharacter.x, firstCharacter.y + firstCharacter.height, firstCharacter.height);
            }
        }
    }
}

void WebviewHandler::sendKeyEvent(CefKeyEvent ev)
{
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::sendKeyEvent,this,ev));return;}
    auto browser = current_focused_browser_;
    if (!browser.get()) {
        return;
    }
    browser->GetHost()->SendKeyEvent(ev);
}

void WebviewHandler::loadUrl(int browserId, std::string url)
{
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::loadUrl,this,browserId,url));return;}
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetMainFrame()->LoadURL(url);
    }
}

void WebviewHandler::goForward(int browserId) {
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::goForward,this,browserId));return;}
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetMainFrame()->GetBrowser()->GoForward();
    }
}

void WebviewHandler::goBack(int browserId) {
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::goBack,this,browserId));return;}
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetMainFrame()->GetBrowser()->GoBack();
    }
}

void WebviewHandler::reload(int browserId) {
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::reload,this,browserId));return;}
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetMainFrame()->GetBrowser()->Reload();
    }
}

void WebviewHandler::openDevTools(int browserId) {
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::openDevTools,this,browserId));return;}
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        CefWindowInfo windowInfo;
#ifdef OS_WIN
        windowInfo.SetAsPopup(nullptr, "DevTools");
#endif
        it->second.browser->GetHost()->ShowDevTools(windowInfo, this, CefBrowserSettings(), CefPoint());
    }
}

void WebviewHandler::imeSetComposition(int browserId, std::string text)
{
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::imeSetComposition,this,browserId,text));return;}
    auto it = browser_map_.find(browserId);
    if (it==browser_map_.end() || !it->second.browser.get()) {
        return;
    }

    CefString cTextStr = CefString(text);

    std::vector<CefCompositionUnderline> underlines;
    cef_composition_underline_t underline = {};
    underline.range.from = 0;
    underline.range.to = static_cast<int>(0 + cTextStr.length());
    underline.color = ColorUNDERLINE;
    underline.background_color = ColorBKCOLOR;
    underline.thick = 0;
    underline.style = CEF_CUS_DOT;
    underlines.push_back(underline);

    // Keeps the caret at the end of the composition
    auto selection_range_end = static_cast<int>(0 + cTextStr.length());
    // Keep the caret at the end of the composition (matches cefclient).
    CefRange selection_range = CefRange(selection_range_end, selection_range_end);
    it->second.browser->GetHost()->ImeSetComposition(cTextStr, underlines, CefRange(UINT32_MAX, UINT32_MAX), selection_range);
}

void WebviewHandler::imeCommitText(int browserId, std::string text)
{
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::imeCommitText,this,browserId,text));return;}
    auto it = browser_map_.find(browserId);
    if (it==browser_map_.end() || !it->second.browser.get()) {
        return;
    }

    CefString cTextStr = CefString(text);
    it->second.is_ime_commit = true;

    std::vector<CefCompositionUnderline> underlines;
    auto selection_range_end = static_cast<int>(0 + cTextStr.length());
    CefRange selection_range = CefRange(selection_range_end, selection_range_end);
    // Establish the composition on all platforms before committing so the commit
    // has a live composition to replace (previously skipped on Windows).
    it->second.browser->GetHost()->ImeSetComposition(cTextStr, underlines, CefRange(UINT32_MAX, UINT32_MAX), selection_range);
    it->second.browser->GetHost()->ImeCommitText(cTextStr, CefRange(UINT32_MAX, UINT32_MAX), 0);

}

void WebviewHandler::setClientFocus(int browserId, bool focus)
{
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::setClientFocus,this,browserId,focus));return;}
    auto it = browser_map_.find(browserId);
    if (it==browser_map_.end() || !it->second.browser.get()) {
        return;
    }
    it->second.wants_focus = focus;
    if(focus) current_focused_browser_=it->second.browser;
    else if(current_focused_browser_ && current_focused_browser_->IsSame(it->second.browser))current_focused_browser_=nullptr;
    if (focus) {
        // Re-arm the first-frame re-assert (handles a SetFocus that lands before
        // the browser is render/input-ready under external_begin_frame).
        it->second.focus_reasserted = false;
    }
    it->second.browser->GetHost()->SetFocus(focus);
}

CefRefPtr<CefBrowser> WebviewHandler::getFocusedBrowser()
{
    return current_focused_browser_;
}

void WebviewHandler::imeSetCompositionNative(const std::wstring& text, int cursor)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::imeSetCompositionNative, this, text, cursor));
        return;
    }
    auto browser = current_focused_browser_;
    if (!browser.get()) {
        return;
    }
    CefString cTextStr;
    cTextStr.FromWString(text);

    std::vector<CefCompositionUnderline> underlines;
    cef_composition_underline_t underline = {};
    underline.range.from = 0;
    underline.range.to = static_cast<int>(cTextStr.length());
    underline.color = ColorUNDERLINE;
    underline.background_color = ColorBKCOLOR;
    underline.thick = 0;
    underline.style = CEF_CUS_DOT;
    underlines.push_back(underline);

    const int len = static_cast<int>(cTextStr.length());
    const int caret = (cursor < 0 || cursor > len) ? len : cursor;
    CefRange selection_range(caret, caret);
    browser->GetHost()->ImeSetComposition(cTextStr, underlines,
        CefRange(UINT32_MAX, UINT32_MAX), selection_range);
}

void WebviewHandler::imeCommitTextNative(const std::wstring& text)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::imeCommitTextNative, this, text));
        return;
    }
    auto browser = current_focused_browser_;
    if (!browser.get()) {
        return;
    }
    CefString cTextStr;
    cTextStr.FromWString(text);
    browser->GetHost()->ImeCommitText(cTextStr, CefRange(UINT32_MAX, UINT32_MAX), 0);
}

void WebviewHandler::imeFinishComposition()
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::imeFinishComposition, this));
        return;
    }
    auto browser = current_focused_browser_;
    if (!browser.get()) {
        return;
    }
    browser->GetHost()->ImeFinishComposingText(false);
}

void WebviewHandler::setCookie(const std::string& domain, const std::string& key, const std::string& value){
    CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(nullptr);
    if(manager){
        CefCookie cookie;
		CefString(&cookie.path).FromASCII("/");
		CefString(&cookie.name).FromString(key.c_str());
		CefString(&cookie.value).FromString(value.c_str());

		if (!domain.empty()) {
			CefString(&cookie.domain).FromString(domain.c_str());
		}

		cookie.httponly = true;
		cookie.secure = false;
		std::string httpDomain = "https://" + domain + "/cookiestorage";
		manager->SetCookie(httpDomain, cookie, nullptr);
    }
}

void WebviewHandler::deleteCookie(const std::string& domain, const std::string& key)
{
    CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(nullptr);
    if (manager) {
        std::string httpDomain = "https://" + domain + "/cookiestorage";
        manager->DeleteCookies(httpDomain, key, nullptr);
    }
}

void WebviewHandler::visitAllCookies(std::function<void(std::map<std::string, std::map<std::string, std::string>>)> callback){
    CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(nullptr);
    if (!manager)
	{
		return;
	}

    CefRefPtr<WebviewCookieVisitor> cookieVisitor = new WebviewCookieVisitor();
    cookieVisitor->setOnVisitComplete(callback);

    manager->VisitAllCookies(cookieVisitor);
}

void WebviewHandler::visitUrlCookies(const std::string& domain, const bool& isHttpOnly, std::function<void(std::map<std::string, std::map<std::string, std::string>>)> callback){
    CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(nullptr);
    if (!manager)
	{
		return;
	}

    CefRefPtr<WebviewCookieVisitor> cookieVisitor = new WebviewCookieVisitor();
    cookieVisitor->setOnVisitComplete(callback);

    std::string httpDomain = "https://" + domain + "/cookiestorage";

    manager->VisitUrlCookies(httpDomain, isHttpOnly, cookieVisitor);
}

void WebviewHandler::setJavaScriptChannels(int browserId, const std::vector<std::string> channels)
{
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::setJavaScriptChannels,this,browserId,channels));return;}
    std::string extensionCode = "try{";
    for(auto& channel : channels)
    {
        extensionCode += channel;
        extensionCode += " = (e,r) => {external.JavaScriptChannel('";
        extensionCode += channel;
        extensionCode += "',e,r)};";
    }
    extensionCode += "}catch(e){console.log(e);}";
    executeJavaScript(browserId, extensionCode);
}

void WebviewHandler::sendJavaScriptChannelCallBack(const bool error, const std::string result, const std::string callbackId, const int browserId, const std::string frameId)
{
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kExecuteJsCallbackMessage);
    CefRefPtr<CefListValue> args = message->GetArgumentList();
    args->SetInt(0, atoi(callbackId.c_str()));
    args->SetBool(1, error);
    args->SetString(2, result);
    auto bit = browser_map_.find(browserId);
    if(bit != browser_map_.end()){
        int64_t frameIdInt = atoll(frameId.c_str());

        CefRefPtr<CefFrame> frame = bit->second.browser->GetMainFrame();

        // CefFrame::GetIdentifier() returns a string identifier in current CEF
        // (since CEF 122) on every platform.
        bool identifierMatch = std::stoll(frame->GetIdentifier().ToString()) == frameIdInt;
        if (identifierMatch)
        {
            frame->SendProcessMessage(PID_RENDERER, message);
        }
    }
}

static std::string GetCallbackId()
{
    auto time = std::chrono::time_point_cast<std::chrono::nanoseconds>(std::chrono::system_clock::now());
	time_t timestamp = time.time_since_epoch().count();
    return std::to_string(timestamp);
} 

void WebviewHandler::executeJavaScript(int browserId, const std::string code, std::function<void(CefRefPtr<CefValue>)> callback)
{
    if (!CefCurrentlyOn(TID_UI)) {CefPostTask(TID_UI,base::BindOnce(&WebviewHandler::executeJavaScript,this,browserId,code,callback));return;}
    if(!code.empty())
    {
        auto bit = browser_map_.find(browserId);
        if(bit != browser_map_.end() && bit->second.browser.get()){
            CefRefPtr<CefFrame> frame = bit->second.browser->GetMainFrame();
            if (frame)
            {
                std::string finalCode = code;
                if(callback != nullptr){
                    std::string callbackId = GetCallbackId();

                    finalCode = "external.EvaluateCallback('";
                    finalCode += callbackId;
                    finalCode += "',(function(){return ";
                    finalCode += code;
                    finalCode += "})());";
                    js_callbacks_[callbackId] = callback;
                }
			    frame->ExecuteJavaScript(finalCode, frame->GetURL(), 0);
            }
        }
    }
}

void WebviewHandler::GetViewRect(CefRefPtr<CefBrowser> browser, CefRect &rect) {
    CEF_REQUIRE_UI_THREAD();
    auto it = browser_map_.find(browser->GetIdentifier());
    if(it == browser_map_.end() || !it->second.browser.get() || browser->IsPopup()) {
        return;
    }
    rect.x = rect.y = 0;
    
    if (it->second.width < 1) {
        rect.width = 1;
    } else {
        rect.width = it->second.width;
    }
    
    if (it->second.height < 1) {
        rect.height = 1;
    } else {
        rect.height = it->second.height;
    }
}

bool WebviewHandler::GetScreenInfo(CefRefPtr<CefBrowser> browser, CefScreenInfo& screen_info) {
    auto info = browser_map_.find(browser->GetIdentifier());
    if (info == browser_map_.end()) return false;
    screen_info.device_scale_factor = info->second.dpi;
    screen_info.rect = CefRect(0, 0, info->second.width, info->second.height);
    screen_info.available_rect = screen_info.rect;
    return true;
}

void WebviewHandler::OnPaint(CefRefPtr<CefBrowser> browser, CefRenderHandler::PaintElementType type,
                            const CefRenderHandler::RectList &dirtyRects, const void *buffer, int w, int h) {
    if (type == PET_VIEW && !browser->IsPopup() && onPaintCallback != nullptr) {
        onPaintCallback(browser->GetIdentifier(), buffer, w, h);
    }
}

void WebviewHandler::OnAcceleratedPaint(CefRefPtr<CefBrowser> browser, CefRenderHandler::PaintElementType type,
                            const CefRenderHandler::RectList &dirtyRects, const CefAcceleratedPaintInfo &info) {
#ifdef WEBVIEW_CEF_GPU_TEXTURE
    if (type == PET_VIEW && !browser->IsPopup() && onAcceleratedPaintCallback != nullptr) {
        received_accelerated_frame_ = true;
        // Use the produced texture's physical dimensions, not the latest
        // requested logical viewport (which may already be a resize ahead).
        const int w = info.extra.coded_size.width;
        const int h = info.extra.coded_size.height;
        auto it = browser_map_.find(browser->GetIdentifier());
        if (it != browser_map_.end()) {
            // A produced frame means the browser is render/input-ready. With
            // external_begin_frame a SetFocus issued right after creation can be
            // dropped (the browser wasn't ready yet), which left the webview
            // unable to receive keyboard input until the window was re-focused.
            // Re-apply the requested focus once, now that frames are flowing.
            if (it->second.wants_focus && !it->second.focus_reasserted) {
                it->second.focus_reasserted = true;
                it->second.browser->GetHost()->SetFocus(true);
            }
        }
        // The shared texture is pool-owned and only valid for the duration of
        // this callback. On Windows it is a HANDLE (open with
        // ID3D11Device1::OpenSharedResource1); on macOS it is an IOSurfaceRef.
        // The platform renderer wraps/copies it before returning.
#ifdef __APPLE__
        const void* sharedTexture = reinterpret_cast<const void*>(info.shared_texture_io_surface);
#else
        const void* sharedTexture = reinterpret_cast<const void*>(info.shared_texture_handle);
#endif
        onAcceleratedPaintCallback(browser->GetIdentifier(), sharedTexture,
                                   w, h, static_cast<int>(info.format));
    }
#endif
}
