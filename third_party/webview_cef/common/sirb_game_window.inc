// Native CEF Views window: OSR cannot implement real Pointer Lock. Use the
// normal Chromium input/permission pipeline instead of spoofing DOM state.
class SirbGameBrowserDelegate : public CefBrowserViewDelegate {
 public:
  explicit SirbGameBrowserDelegate(std::function<void(int)> created)
      : created_(std::move(created)) {}
  void OnBrowserCreated(CefRefPtr<CefBrowserView> view,
                        CefRefPtr<CefBrowser> browser) override {
    if (created_) { auto callback = std::move(created_); callback(browser->GetIdentifier()); }
  }
  cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
 private:
  std::function<void(int)> created_;
  IMPLEMENT_REFCOUNTING(SirbGameBrowserDelegate);
};
class SirbGameWindowDelegate : public CefWindowDelegate {
 public:
  SirbGameWindowDelegate(CefRefPtr<CefBrowserView> view, std::string title)
      : view_(view), title_(std::move(title)) {}
  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    window->SetTitle(title_);
    window->AddChildView(view_);
    window->Show();
    view_->RequestFocus();
  }
  void OnWindowDestroyed(CefRefPtr<CefWindow> window) override { view_ = nullptr; }
  bool CanClose(CefRefPtr<CefWindow> window) override {
    auto browser = view_ ? view_->GetBrowser() : nullptr;
    return !browser || browser->GetHost()->IsReadyToBeClosed() ||
        browser->GetHost()->TryCloseBrowser();
  }
  CefSize GetPreferredSize(CefRefPtr<CefView> view) override { return CefSize(1280, 800); }
  cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
 private:
  CefRefPtr<CefBrowserView> view_;
  std::string title_;
  IMPLEMENT_REFCOUNTING(SirbGameWindowDelegate);
};
void WebviewHandler::createGameWindow(std::string url, std::function<void(int)> callback) {
  if (!CefCurrentlyOn(TID_UI)) {
    CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::createGameWindow, this, url, callback));
    return;
  }
  CefURLParts parts;
  if (!CefParseURL(url, parts) ||
      (CefString(&parts.scheme) != "https" && CefString(&parts.scheme) != "http")) {
    callback(-1); return;
  }
  // One native game at a time, including a pending creation. It remains in the
  // same process tree/resource quotas and is closed with the application.
  if (game_window_pending_) { callback(-1); return; }
  for (const auto& entry : browser_map_) {
    if (!entry.second.browser->GetHost()->IsWindowRenderingDisabled()) {
      callback(-1); return;
    }
  }
  game_window_pending_ = true;
  auto extra = CefDictionaryValue::Create();
  {
    std::lock_guard<std::mutex> lock(sirb_config.mutex);
    extra->SetString("sirbToken", sirb_config.policy_key);
  }
  auto context = CefRequestContext::CreateContext(CefRequestContext::GetGlobalContext(), this);
  context->RegisterSchemeHandlerFactory("sirb", "config", new SirbPolicyFactory());
  auto delegate = new SirbGameBrowserDelegate([this, callback](int id) {
    game_window_pending_ = false;
    auto event = CefDictionaryValue::Create(); event->SetString("type", "gameWindowOpened");
    event->SetInt("windowId", id); sirbEvent(id, sirb_json(event));
    callback(id);
  });
  auto view = CefBrowserView::CreateBrowserView(this, url, CefBrowserSettings(), extra, context, delegate);
  if (!view || !CefWindow::CreateTopLevelWindow(new SirbGameWindowDelegate(view, url))) {
    game_window_pending_ = false;
    callback(-1);
  }
}
