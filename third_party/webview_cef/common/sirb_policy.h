#pragma once
#include "sirb_config.h"
#include "include/cef_scheme.h"
#include "include/cef_resource_handler.h"
#include <algorithm>
#include <charconv>
#include <cstring>

// Read-only, authenticated, in-process resource. No sockets or filesystem access.
// CEF copies browser extra_info once: fetch the current policy at every new V8
// context rather than replaying a stale ad/appearance/speculation configuration.
class SirbPolicyResource final : public CefResourceHandler {
 public:
  SirbPolicyResource(std::string body,int status):body_(std::move(body)),status_(status) {}
  bool Open(CefRefPtr<CefRequest>,bool& handle,CefRefPtr<CefCallback>) override {handle=true;return true;}
  void GetResponseHeaders(CefRefPtr<CefResponse> response,int64_t& length,CefString&) override {
    response->SetStatus(status_);response->SetMimeType("text/plain");response->SetCharset("utf-8");
    CefResponse::HeaderMap headers;
    headers.emplace("Access-Control-Allow-Origin","*");
    headers.emplace("Access-Control-Allow-Methods","GET, OPTIONS");
    headers.emplace("Access-Control-Allow-Headers","X-Sirb-Key, X-Sirb-Browser");
    headers.emplace("Cache-Control","no-store");
    response->SetHeaderMap(headers);length=static_cast<int64_t>(body_.size());
  }
  bool Read(void* out,int requested,int& read,CefRefPtr<CefResourceReadCallback>) override {
    read=static_cast<int>(std::min(body_.size()-offset_,static_cast<size_t>(std::max(0,requested))));
    if(read==0)return false;
    std::memcpy(out,body_.data()+offset_,read);offset_+=read;return true;
  }
  bool Skip(int64_t requested,int64_t& skipped,CefRefPtr<CefResourceSkipCallback>) override {
    skipped=std::min(static_cast<int64_t>(body_.size()-offset_),std::max<int64_t>(0,requested));offset_+=skipped;return skipped>0;
  }
  void Cancel() override {body_.clear();offset_=0;}
 private:
  std::string body_;size_t offset_=0;int status_;
  IMPLEMENT_REFCOUNTING(SirbPolicyResource);
};

class SirbPolicyFactory final : public CefSchemeHandlerFactory {
 public:
  CefRefPtr<CefResourceHandler> Create(CefRefPtr<CefBrowser> browser,CefRefPtr<CefFrame>,const CefString&,CefRefPtr<CefRequest> request) override {
    if(request->GetMethod()=="OPTIONS")return new SirbPolicyResource("",204);
    auto key=request->GetHeaderByName("X-Sirb-Key").ToString();
    auto header=request->GetHeaderByName("X-Sirb-Browser").ToString();
    int id=0;auto parsed=std::from_chars(header.data(),header.data()+header.size(),id);
    std::lock_guard<std::mutex> lock(sirb_config.mutex);
    if(request->GetMethod()!="GET" || key!=sirb_config.policy_key || parsed.ec!=std::errc() || parsed.ptr!=header.data()+header.size() || !sirb_config.browsers.count(id) || (browser && browser->GetIdentifier()!=id))return new SirbPolicyResource("",403);
    const bool speculative=sirb_config.speculative[id];
    auto flags=std::string("window.__sirbSpeculative=")+(speculative?"true;":"false;");
    flags+=std::string("window.__sirbBlocking=")+(sirb_config.enabled?"true;":"false;");
    return new SirbPolicyResource(flags+sirb_config.script,200);
  }
 private:
  IMPLEMENT_REFCOUNTING(SirbPolicyFactory);
};
