#include "NativeFaultAccess.h"
#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

static volatile sig_atomic_t lastWrite = -1, faults;
static volatile unsigned char *page;
static size_t pageSize;
static void handleFault(int signal, siginfo_t *info, void *context) {
 (void)signal;
 if (info->si_addr != (const void *)page) _exit(2);
 lastWrite = PGFaultIsWrite(context);
 faults++;
 if (mprotect((void *)page, pageSize, PROT_READ | PROT_WRITE)) _exit(3);
}
int main(void) {
 pageSize = (size_t)getpagesize();
 page = mmap(NULL,pageSize,PROT_READ | PROT_WRITE,MAP_PRIVATE | MAP_ANON,-1,0);
 assert(page != MAP_FAILED);
 struct sigaction handler = {0};
 handler.sa_sigaction = handleFault; handler.sa_flags = SA_SIGINFO;
 sigemptyset(&handler.sa_mask);
 assert(!sigaction(SIGSEGV,&handler,NULL)); assert(!sigaction(SIGBUS,&handler,NULL));
 *page = 37;
 assert(!mprotect((void *)page,pageSize,PROT_NONE));
 unsigned char value = *page;
 assert(value == 37 && faults == 1 && lastWrite == 0);
 assert(!mprotect((void *)page,pageSize,PROT_READ));
 *page = 51;
 assert(*page == 51 && faults == 2 && lastWrite == 1);
 assert(!munmap((void *)page,pageSize));
 puts("PASS: Darwin read and write protection faults decoded correctly");
}
