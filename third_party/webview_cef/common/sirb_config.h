#pragma once
#include <mutex>
#include <regex>
#include <string>
#include <vector>
#include <unordered_map>
#include <cstdlib>
#include <thread>
#include <chrono>
#include <random>
#include "include/cef_browser.h"
#include "include/cef_parser.h"
#include "include/wrapper/cef_helpers.h"

inline std::string sirb_new_policy_key() {
  std::random_device random;
  const char* hex="0123456789abcdef";std::string key;
  for(int i=0;i<32;i++){auto byte=random()&255;key+=hex[byte>>4];key+=hex[byte&15];}
  return key;
}
struct SirbConfig {
  std::mutex mutex;
  bool enabled = true;
  std::string profile;
  std::string script;
  std::vector<std::string> domains, allowed;
  std::unordered_map<int, std::string> topHosts;
  std::unordered_map<int, CefRefPtr<CefBrowser>> browsers;
  std::unordered_map<int,bool> speculative;
  const std::string policy_key=sirb_new_policy_key();
  std::vector<std::regex> patterns;
};
inline SirbConfig sirb_config;
inline bool sirb_gpu_enabled() {
  const char* value = std::getenv("SIRB_GPU_ACCELERATION");
  return !value || std::string(value) != "0";
}
inline std::string sirb_host(const std::string& url) {
  CefURLParts parts;
  if (!CefParseURL(url, parts)) return "";
  return CefString(&parts.host).ToString();
}
inline bool sirb_domain(const std::string& host, const std::string& domain) {
  return host == domain || (host.size() > domain.size() &&
    host.compare(host.size()-domain.size(), domain.size(), domain) == 0 &&
    host[host.size()-domain.size()-1] == '.');
}
