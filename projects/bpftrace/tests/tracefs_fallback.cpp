// SPDX-License-Identifier: Apache-2.0
// The test runner includes AttachedKprobeProbe from the freshly patched tag.
// Only its external dependencies are substituted below.
#include <atomic>
#include <cassert>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <linux/perf_event.h>
#include <map>
#include <memory>
#include <set>
#include <sstream>
#include <string>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <variant>
#include <vector>

#define LOG(level) std::ostringstream()
struct AttachError {};
struct Error {
  std::string message;
};
template <typename T>
Error make_error(std::string message = "")
{
  return { std::move(message) };
}
template <typename T>
struct Result {
  std::variant<T, Error> value;
  Result(T result) : value(std::move(result))
  {
  }
  Result(Error error) : value(std::move(error))
  {
  }
  explicit operator bool() const
  {
    return std::holds_alternative<T>(value);
  }
  T &operator*()
  {
    return std::get<T>(value);
  }
  Error takeError()
  {
    return std::get<Error>(value);
  }
};
enum class ProbeType { kprobe, kretprobe };
struct Probe {
  ProbeType type = ProbeType::kprobe;
  std::string path, attach_point = "test_func";
  uint64_t address = 0, func_offset = 0;
};
struct bpf_link {};
struct bpf_kprobe_opts {
  uint64_t offset = 0;
  bool retprobe = false;
};
#define DECLARE_LIBBPF_OPTS(type, name)                                        \
  type name                                                                    \
  {                                                                            \
  }
struct BpfProgram {
  void *bpf_prog() const
  {
    return nullptr;
  }
  int fd() const
  {
    return 9;
  }
};
class AttachedProbe {
public:
  explicit AttachedProbe(const Probe &)
  {
  }
  virtual ~AttachedProbe() = default;
  virtual int link_fd()
  {
    return -1;
  }
};
struct State {
  int attach_errno = EPERM, open_fail_cpu = -1, opens = 0, link_destroys = 0;
  unsigned long ioctl_failure = 0;
  bool create_failure = false, retprobe = false;
  int pid = 123;
  uint64_t offset = 0;
  std::string func, module;
  std::vector<int> cpus{ 0, 2 };
  std::set<int> fds;
  std::map<int, std::string> fd_events;
  std::vector<std::string> created, detached;
} state;
bpf_link link;
Result<uint64_t> resolve_offset_kprobe(Probe &probe)
{
  return probe.func_offset;
}
std::string eventname(const Probe &, uint64_t)
{
  return "p_test_func_0_1";
}
bpf_link *bpf_program__attach_kprobe_opts(void *,
                                          const char *,
                                          bpf_kprobe_opts *)
{
  errno = state.attach_errno;
  return errno ? nullptr : &link;
}
int bpf_link__destroy(bpf_link *p)
{
  assert(p == &link);
  ++state.link_destroys;
  return 0;
}
int bpf_link__fd(bpf_link *p)
{
  assert(p == &link);
  return 99;
}
namespace util {
std::vector<int> get_online_cpus()
{
  return state.cpus;
}
} // namespace util
namespace tracefs {
int create_tracefs_kprobe(const std::string &name,
                          bool retprobe,
                          const std::string &func,
                          uint64_t offset,
                          const std::string &module)
{
  state.created.push_back(name);
  state.retprobe = retprobe;
  state.func = func;
  state.offset = offset;
  state.module = module;
  return state.create_failure ? -1 : 42;
}
int detach_kprobe(const std::string &name)
{
  for (const auto &[fd, event] : state.fd_events) {
    (void)fd;
    assert(event != name); // this event's FDs must close before its removal
  }
  state.detached.push_back(name);
  errno = EBUSY; // cleanup must not replace the original error message
  return 0;
}
} // namespace tracefs
int mock_getpid()
{
  return state.pid;
}
int mock_close(int fd)
{
  assert(state.fds.erase(fd) == 1);
  assert(state.fd_events.erase(fd) == 1);
  return 0;
}
int mock_perf_open(long nr,
                   perf_event_attr *attr,
                   int pid,
                   int cpu,
                   int group,
                   unsigned long flags)
{
  assert(nr == __NR_perf_event_open && pid == -1 && group == -1);
  assert(flags == PERF_FLAG_FD_CLOEXEC);
  assert(attr->type == PERF_TYPE_TRACEPOINT && attr->config == 42);
  ++state.opens;
  if (cpu == state.open_fail_cpu) {
    errno = EMFILE;
    return -1;
  }
  int fd = 100 + state.opens;
  assert(state.fds.insert(fd).second);
  state.fd_events.emplace(fd, state.created.back());
  return fd;
}
int mock_ioctl(int fd, unsigned long request, int)
{
  assert(state.fds.count(fd));
  if (request == state.ioctl_failure && state.opens == 2) {
    errno = EACCES;
    return -1;
  }
  return 0;
}
#define getpid mock_getpid
#define close mock_close
#define syscall mock_perf_open
#define ioctl mock_ioctl
#include "attached-kprobe.inc"

void check_failure(const Probe &input, const std::string &message)
{
  auto probe = input;
  auto result = AttachedKprobeProbe::make(probe, BpfProgram{});
  assert(!result);
  assert(result.takeError().message.find(message) != std::string::npos);
  assert(state.fds.empty());
  assert(state.detached == state.created);
}
int main()
{
  Probe probe;
  state.attach_errno = 0;
  {
    auto result = AttachedKprobeProbe::make(probe, BpfProgram{});
    assert(result && (*result)->link_fd() == 99);
    assert(state.created.empty());
  }
  assert(state.link_destroys == 1);
  for (int error : { EINVAL, EILSEQ }) {
    state = State{};
    state.attach_errno = error;
    check_failure(probe, error == EILSEQ ? "instruction" : "");
    assert(state.created.empty());
  }
  std::set<std::string> names;
  for (int pid : { 123, 456 }) {
    for (int error : { EPERM, ENOENT }) {
      state = State{};
      state.pid = pid;
      state.attach_errno = error;
      {
        auto result = AttachedKprobeProbe::make(probe, BpfProgram{});
        assert(result && (*result)->link_fd() == -1);
        assert(state.fds.size() == 2 && state.detached.empty());
        assert(names.insert(state.created.at(0)).second);
        assert(state.created.at(0).find("_" + std::to_string(pid) + "_") !=
               std::string::npos);
      }
      assert(state.fds.empty() && state.detached == state.created);
      assert(state.link_destroys == 0);
    }
  }
  state = State{};
  {
    auto first = AttachedKprobeProbe::make(probe, BpfProgram{});
    auto second = AttachedKprobeProbe::make(probe, BpfProgram{});
    assert(first && second && state.fds.size() == 4);
    assert(state.created[0] != state.created[1]);
    (*first).reset();
    assert(state.fds.size() == 2 && state.detached.size() == 1);
    assert(state.detached[0] == state.created[0]);
    (*second).reset();
    assert(state.fds.empty() && state.detached == state.created);
  }
  state = State{};
  state.create_failure = true;
  assert(!AttachedKprobeProbe::make(probe, BpfProgram{}));
  assert(state.opens == 0 && state.detached.empty());
  state = State{};
  state.cpus.clear();
  check_failure(probe, "no online CPUs");
  for (int cpu : { 0, 2 }) {
    state = State{};
    state.open_fail_cpu = cpu;
    check_failure(probe, strerror(EMFILE));
  }
  for (auto request : std::vector<unsigned long>{ PERF_EVENT_IOC_SET_BPF,
                                                  PERF_EVENT_IOC_ENABLE }) {
    state = State{};
    state.ioctl_failure = request;
    check_failure(probe, strerror(EACCES));
  }
  state = State{};
  probe.type = ProbeType::kretprobe;
  probe.path = "test_module";
  probe.func_offset = 16;
  {
    assert(AttachedKprobeProbe::make(probe, BpfProgram{}));
  }
  assert(state.retprobe && state.module == "test_module" && state.offset == 16);
  assert(state.func == "test_func");
  state = State{};
  probe = Probe{};
  probe.attach_point.clear();
  probe.address = 0x12345678;
  {
    assert(AttachedKprobeProbe::make(probe, BpfProgram{}));
  }
  assert(state.func.empty() && state.offset == probe.address);
  std::cout << "PASS: libbpf, fallback, unique names, FD lifecycle, failure "
               "rollback, module/address probes\n";
}
