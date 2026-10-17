// Sirb's browser-host extensions. Included once by webview_handler.cc.
void WebviewHandler::OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser, TerminationStatus status,
  int error_code, const CefString& error_string) {
  auto event = CefDictionaryValue::Create(); event->SetString("type", "renderCrash");
  event->SetString("error", error_string.empty() ? "Renderer process terminated" : error_string);
  event->SetInt("status", static_cast<int>(status)); event->SetInt("code", error_code);
  auto value = CefValue::Create(); value->SetDictionary(event);
  sirbEvent(browser->GetIdentifier(), CefWriteJSON(value, JSON_WRITER_DEFAULT));
}
static std::string sirb_json(CefRefPtr<CefDictionaryValue> dictionary) {
  auto value = CefValue::Create(); value->SetDictionary(dictionary);
  return CefWriteJSON(value, JSON_WRITER_DEFAULT);
}
void WebviewHandler::sirbEvent(int browserId, std::string json) {
  if (!CefCurrentlyOn(TID_UI)) {
    CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::sirbEvent, this, browserId, json));
    return;
  }
  auto entry = browser_map_.find(browserId);
  if (entry != browser_map_.end() &&
      !entry->second.browser->GetHost()->IsWindowRenderingDisabled()) {
    auto value = CefParseJSON(json, JSON_PARSER_RFC);
    if (value && value->GetType() == VTYPE_DICTIONARY && onNativeEvent) {
      auto event = value->GetDictionary(); event->SetInt("windowId", browserId);
      auto frame = entry->second.browser->GetMainFrame();
      if (!event->HasKey("url") && frame) event->SetString("url", frame->GetURL());
      onNativeEvent(CefWriteJSON(value, JSON_WRITER_DEFAULT));
    }
    return;
  }
  if (onConsoleMessageEvent) onConsoleMessageEvent(browserId, 0, "__sirb__" + json, "sirb", 0);
}
WebviewHandler::ReturnValue WebviewHandler::OnBeforeResourceLoad(
  CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
  CefRefPtr<CefRequest> request, CefRefPtr<CefCallback> callback) {
  const auto url = request->GetURL().ToString();
  if(url.rfind("sirb://",0)==0)return RV_CONTINUE;
  const auto host = sirb_host(url);
  // The initiator, not the resource domain, controls per-site disabling.
  auto page = sirb_host(request->GetFirstPartyForCookies());
  bool blocked = false;
  {
    std::lock_guard<std::mutex> lock(sirb_config.mutex);
    if (!sirb_config.enabled) return RV_CONTINUE;
    if (browser) {
      auto site = sirb_config.topHosts.find(browser->GetIdentifier());
      if (site != sirb_config.topHosts.end()) page = site->second;
    }
    for (const auto& allowed : sirb_config.allowed)
      if (sirb_domain(page, allowed) || sirb_domain(host, allowed)) return RV_CONTINUE;
    for (const auto& domain : sirb_config.domains)
      if (sirb_domain(host, domain)) { blocked = true; break; }
    if (!blocked) for (const auto& pattern : sirb_config.patterns)
      if (std::regex_search(url, pattern)) { blocked = true; break; }
  }
  if (!blocked) return RV_CONTINUE;
  if (browser) {
    auto event = CefDictionaryValue::Create();
    event->SetString("type", "blocked");
    event->SetString("url", url);
    event->SetString("page", page);
    sirbEvent(browser->GetIdentifier(), sirb_json(event));
  }
  return RV_CANCEL;
}
void WebviewHandler::OnResourceLoadComplete(CefRefPtr<CefBrowser> browser,
  CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request, CefRefPtr<CefResponse> response,
  URLRequestStatus status, int64_t received_content_length) {
  // On IO: do not modify browser/frame state. Normal aborts (navigation, close,
  // and ad cancellation) are not page failures. No headers/body are collected.
  if (!browser || status == UR_CANCELED) return;
  const auto code = response ? response->GetError() : ERR_FAILED;
  const int http = response ? response->GetStatus() : 0;
  if (code == ERR_ABORTED || (status != UR_FAILED && http < 400)) return;
  auto event = CefDictionaryValue::Create(); event->SetString("type", "runtimeError");
  event->SetString("category", "network"); event->SetString("message", "Resource request failed");
  event->SetString("source", request->GetURL()); event->SetString("operation", request->GetMethod());
  event->SetInt("code", static_cast<int>(code)); event->SetInt("httpStatus", http);
  event->SetInt("requestStatus", static_cast<int>(status));
  event->SetDouble("receivedBytes", static_cast<double>(received_content_length));
  // HTTP headers can succeed before the stream fails. Do not call this success,
  // retry signed URLs, or assume every transport failure is an ad cancellation.
  if (status == UR_FAILED && http >= 200 && http < 300) {
    event->SetString("diagnostic", "responseBodyTransferFailed");
    event->SetString("reason", "HTTP headers succeeded but resource transfer failed before successful completion.");
  }
  sirbEvent(browser->GetIdentifier(), sirb_json(event));
}
void WebviewHandler::sirbControl(int browserId, std::string action, std::string value) {
  if (!CefCurrentlyOn(TID_UI)) {
    CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::sirbControl, this, browserId, action, value));
    return;
  }
  auto entry = browser_map_.find(browserId);
  if (entry == browser_map_.end()) return;
  auto browser = entry->second.browser;
  auto host = browser->GetHost();
  if (action == "hidden") {
    entry->second.hidden = value == "true";
    host->WasHidden(entry->second.hidden);
    if (!entry->second.hidden) {
      host->WasResized();
      host->Invalidate(PET_VIEW);
#ifdef WEBVIEW_CEF_GPU_TEXTURE
      host->SendExternalBeginFrame();
#endif
    }
  } else if (action == "muted") host->SetAudioMuted(value == "true");
  else if (action == "scripts") {
    auto parsed=CefParseJSON(value,JSON_PARSER_RFC);
    if(!parsed || parsed->GetType()!=VTYPE_DICTIONARY) return;
    auto data=parsed->GetDictionary();
    {std::lock_guard<std::mutex> lock(sirb_config.mutex);sirb_config.speculative[browserId]=data->GetBool("speculative");}
    std::vector<CefString> frames; browser->GetFrameIdentifiers(frames);
    for(const auto& id:frames) {
      auto frame=browser->GetFrameByIdentifier(id); if(!frame) continue;
      auto message=CefProcessMessage::Create("sirbUpdateScript");
      message->GetArgumentList()->SetString(0,data->GetString("runtime"));
      frame->SendProcessMessage(PID_RENDERER,message);
    }
  }
  else if (action == "theme") {
    auto params = CefDictionaryValue::Create(); auto list = CefListValue::Create();
    auto feature = CefDictionaryValue::Create(); feature->SetString("name", "prefers-color-scheme");
    feature->SetString("value", value); list->SetDictionary(0, feature); params->SetList("features", list);
    host->ExecuteDevToolsMethod(0, "Emulation.setEmulatedMedia", params);
  }
  else if (action == "stop") browser->StopLoad();
  else if (action == "zoom") host->SetZoomLevel(std::stod(value));
  else if (action == "find") host->Find(value, true, false, false);
  else if (action == "findNext") host->Find(value, true, false, true);
  else if (action == "findPrevious") host->Find(value, false, false, true);
  else if (action == "stopFind") host->StopFinding(true);
  else if (action == "copy") {
    auto frame = browser->GetFocusedFrame();
    if (!frame) frame = browser->GetMainFrame();
    if (frame) frame->Copy();
  }
  else if (action == "paste") {
    auto frame = browser->GetFocusedFrame();
    if (!frame) frame = browser->GetMainFrame();
    if (frame) frame->Paste();
  }
  else if (action == "cut") {
    auto frame = browser->GetFocusedFrame();
    if (!frame) frame = browser->GetMainFrame();
    if (frame) frame->Cut();
  }
  else if (action == "selectAll") {
    auto frame = browser->GetFocusedFrame();
    if (!frame) frame = browser->GetMainFrame();
    if (frame) frame->SelectAll();
  }
  else if (action == "undo") {
    auto frame = browser->GetFocusedFrame();
    if (!frame) frame = browser->GetMainFrame();
    if (frame) frame->Undo();
  }
  else if (action == "redo") {
    auto frame = browser->GetFocusedFrame();
    if (!frame) frame = browser->GetMainFrame();
    if (frame) frame->Redo();
  }
}
bool WebviewHandler::OnBeforeDownload(CefRefPtr<CefBrowser> browser,
  CefRefPtr<CefDownloadItem> item, const CefString& name,
  CefRefPtr<CefBeforeDownloadCallback> callback) {
  callback->Continue("", true);
  return true;
}
void WebviewHandler::OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
  CefRefPtr<CefDownloadItem> item, CefRefPtr<CefDownloadItemCallback> callback) {
  auto event = CefDictionaryValue::Create();
  event->SetString("type", "download"); event->SetInt("id", item->GetId());
  event->SetString("url", item->GetURL()); event->SetString("path", item->GetFullPath());
  event->SetInt("percent", item->GetPercentComplete());
  event->SetBool("complete", item->IsComplete()); event->SetBool("canceled", item->IsCanceled());
  sirbEvent(browser->GetIdentifier(), sirb_json(event));
}
void WebviewHandler::OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen) {
  sirbEvent(browser->GetIdentifier(), std::string("{\"type\":\"fullscreen\",\"value\":") + (fullscreen ? "true}" : "false}"));
}
void WebviewHandler::OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString>& urls) {
  if (urls.empty()) return;
  auto event = CefDictionaryValue::Create(); event->SetString("type", "favicon");
  event->SetString("url", urls.front()); sirbEvent(browser->GetIdentifier(), sirb_json(event));
}
void WebviewHandler::OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool loading, bool back, bool forward) {
  auto event = CefDictionaryValue::Create(); event->SetString("type", "navigation");
  event->SetBool("loading", loading); event->SetBool("back", back); event->SetBool("forward", forward);
  sirbEvent(browser->GetIdentifier(), sirb_json(event));
}
