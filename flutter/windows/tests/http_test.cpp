#include "../runner/http_request.h"
#include <atomic>
#include <iostream>
#include <thread>
#include <stdexcept>

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  const auto port = static_cast<unsigned short>(std::stoi(argv[1]));
  using namespace std::chrono;
  try {
    const auto post = [&](const wchar_t* path, const std::function<bool()>& cancel,
                          milliseconds timeout = seconds(5)) {
      return HttpRequest(L"127.0.0.1", port, false, path, L"Content-Type: text/plain", {'o','k'}, cancel, timeout);
    };
    auto reply = post(L"/ok", [] { return false; });
    if (reply.status != 200 || reply.body != "local fixture") throw std::runtime_error("normal reply");
    reply = post(L"/redirect", [] { return false; });
    if (reply.status != 302) throw std::runtime_error("redirect must not be followed");
    for (const auto path : {L"/headers", L"/body"}) {
      std::atomic<bool> cancel{false};
      std::thread timer([&] { std::this_thread::sleep_for(milliseconds(200)); cancel = true; });
      const auto start = steady_clock::now();
      std::string error;
      try { post(path, [&] { return cancel.load(); }); }
      catch (const std::exception& e) { error = e.what(); }
      timer.join();
      if (error != "Request cancelled." || steady_clock::now() - start > seconds(2))
        throw std::runtime_error("pending I/O cancellation did not complete promptly");
      // A cancelled call fully releases the transport before the next request.
      if (post(L"/ok", [] { return false; }).status != 200) throw std::runtime_error("request after cancellation");
    }
    auto fails = [&](const wchar_t* path, milliseconds limit) {
      try { post(path, [] { return false; }, limit); }
      catch (const std::exception& e) { return std::string(e.what()); }
      throw std::runtime_error("request unexpectedly succeeded");
    };
    const auto start = steady_clock::now();
    if (fails(L"/dribble", milliseconds(350)) != "Google's request timed out." || steady_clock::now() - start > seconds(2))
      throw std::runtime_error("whole-request deadline did not interrupt progressive response");
    if (fails(L"/large", seconds(5)) != "Google's reply exceeds 2 MiB.") throw std::runtime_error("size limit");
    fails(L"/truncated", seconds(5));
    std::cout << "C9_HTTP_PASS normal, redirects, cancel headers/body, retry, total deadline, size, truncation\n";
    return 0;
  } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}
