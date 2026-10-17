#include <stdarg.h>

int __android_log_write(int prio, const char* tag, const char* text) {
    (void)prio;
    (void)tag;
    (void)text;
    return 0;
}

int __android_log_print(int prio, const char* tag, const char* fmt, ...) {
    (void)prio;
    (void)tag;
    (void)fmt;
    return 0;
}

int __android_log_vprint(int prio, const char* tag, const char* fmt, va_list ap) {
    (void)prio;
    (void)tag;
    (void)fmt;
    (void)ap;
    return 0;
}

void __android_log_assert(const char* cond, const char* tag, const char* fmt, ...) {
    (void)cond;
    (void)tag;
    (void)fmt;
}
