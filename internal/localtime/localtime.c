#include <stdint.h>
#include <time.h>

// Offset of local time from UTC, in seconds, at the given epoch second.
int32_t asciidoctor_utc_offset(int64_t secs) {
  time_t t = (time_t)secs;
  struct tm tm;
#ifdef _WIN32
  if (localtime_s(&tm, &t) != 0) return 0;
  return (int32_t)(_mkgmtime(&tm) - t);
#else
  if (localtime_r(&t, &tm) == NULL) return 0;
  return (int32_t)tm.tm_gmtoff;
#endif
}
