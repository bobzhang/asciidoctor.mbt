// Monotonic clock for the timings report (`-t`).
#ifdef _WIN32
#include <windows.h>

double asciidoctor_cli_monotonic_seconds(void) {
  LARGE_INTEGER freq, count;
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&count);
  return (double)count.QuadPart / (double)freq.QuadPart;
}
#else
#include <time.h>

double asciidoctor_cli_monotonic_seconds(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}
#endif
