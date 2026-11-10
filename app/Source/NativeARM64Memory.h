#pragma once
#include <simde/wasm/simd128.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

#if defined(__aarch64__) && defined(SIMDE_ARM_NEON_A32V7_NATIVE)
// Wasm's ordinary vector accesses may tear. These instructions access shared
// bytes outside C's non-atomic access rules; the compiler memory clobber keeps
// them ordered with the surrounding runtime operations. Bounds checks belong
// to the caller. Actual Wasm atomic instructions continue using C11 atomics.
// https://webassembly.github.io/threads/core/exec/relaxed.html
#define PG_HAS_NATIVE_SHARED_VECTORS 1
static inline simde_v128_t pg_shared_load128(const _Atomic volatile uint8_t *address) {
 simde_v128_t value;
 __asm__ volatile("ldr %q0, [%1]" : "=w"(value) : "r"(address) : "memory");
 return value;
}
static inline void pg_shared_store128(_Atomic volatile uint8_t *address,simde_v128_t value) {
 __asm__ volatile("str %q0, [%1]" : : "w"(value),"r"(address) : "memory");
}
static inline void pg_shared_load64(const _Atomic volatile uint8_t *address,uint8_t bytes[8]) {
 uint64_t value;
 __asm__ volatile("ldr %0, [%1]" : "=r"(value) : "r"(address) : "memory");
 memcpy(bytes,&value,8);
}
#elif defined(__x86_64__) && defined(SIMDE_X86_SSE2_NATIVE)
// Unaligned SSE2 accesses preserve Wasm's ordinary (possibly tearing) memory
// semantics. The memory clobber also orders surrounding compiler accesses.
#define PG_HAS_NATIVE_SHARED_VECTORS 1
static inline simde_v128_t pg_shared_load128(const _Atomic volatile uint8_t *address) {
 simde_v128_t value;
 __asm__ volatile("movdqu (%1), %0" : "=x"(value) : "r"(address) : "memory");
 return value;
}
static inline void pg_shared_store128(_Atomic volatile uint8_t *address, simde_v128_t value) {
 __asm__ volatile("movdqu %1, (%0)" : : "r"(address), "x"(value) : "memory");
}
static inline void pg_shared_load64(const _Atomic volatile uint8_t *address, uint8_t bytes[8]) {
 uint64_t value;
 __asm__ volatile("movq (%1), %0" : "=r"(value) : "r"(address) : "memory");
 memcpy(bytes, &value, 8);
}
#endif
