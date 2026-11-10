#pragma once
#include <sys/ucontext.h>

// Decode the hardware page-fault access type saved by Darwin's signal handler.
static inline int PGFaultIsWrite(const void *context) {
 const ucontext_t *state = context;
#if defined(__aarch64__)
 return (state->uc_mcontext->__es.__esr >> 6) & 1; // ARM data abort WnR.
#elif defined(__x86_64__)
 return (state->uc_mcontext->__es.__err >> 1) & 1; // x86 page-fault W/R.
#else
#error Unsupported page-fault architecture
#endif
}
