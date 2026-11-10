#import <Foundation/Foundation.h>
#include "HostInternal.h"
#include "WasmFutex.h"
#include "wasm-rt-impl.h"
#include <assert.h>
#include <errno.h>
#include <unistd.h>
#undef wasm_rt_impl_try
#define wasm_rt_impl_try() 0
void pg_log(const char *message) {}
void *pg_pointer(struct w2c_env *host,uint64_t address,uint64_t bytes){abort();}
wasm_rt_shared_memory_t *w2c_env_memory(struct w2c_env *host){return &host->memory;}
uint32_t pg_atomic_wait32(wasm_rt_shared_memory_t *m,uint64_t a,uint32_t v,uint64_t t){return 0;}
uint32_t pg_atomic_notify(wasm_rt_shared_memory_t *m,uint64_t a,uint32_t n){return 0;}

// Inject faults into the real local-read loop without signals or a server.
static ssize_t probe_pread(int fd,void *buffer,size_t count,off_t offset);
#define pread probe_pread
#include "../Source/NativeAssets.m"
#undef pread
static unsigned calls,interruptOn,errorOn;
static ssize_t probe_pread(int fd,void *buffer,size_t count,off_t offset){
  calls++;
  if(calls==interruptOn){errno=EINTR;return -1;}
  if(calls==errorOn){errno=EIO;return -1;}
  return pread(fd,buffer,MIN(count,3),offset); // also exercise positive short reads
}

int main(void){@autoreleasepool {
  NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  NSFileManager *files=NSFileManager.defaultManager;
  assert([files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]);
  const uint8_t original[]={1,2,3,4,5,6,7,8};
  NSData *fixture=[NSData dataWithBytes:original length:sizeof original];
  NSString *path=[root stringByAppendingPathComponent:@"fixture.bin"];
  assert([fixture writeToFile:path atomically:YES]);
  @try {
    PGSetLocalGameFolder(root.fileSystemRepresentation);
    assetFiles=@[@[@"fixture.bin",@(sizeof original)]];
    uint8_t output[sizeof original]={0};
    // An interruption before any data or after a positive short read is retried.
    for(unsigned at=1;at<=2;at++){
      calls=0;interruptOn=at;errorOn=0;
      assert(readAsset(0,0,output,sizeof output)==sizeof output);
      assert(!memcmp(output,original,sizeof output));
    }
    // Real failures must remain errors, even after some bytes were read.
    for(unsigned at=1;at<=2;at++){
      calls=0;interruptOn=0;errorOn=at;
      assert(readAsset(0,0,output,sizeof output)==-1);
    }
    calls=0;errorOn=0;
    assert(readAsset(0,6,output,sizeof output)==2&&!memcmp(output,original+6,2));
    assert(readAsset(0,sizeof original,output,sizeof output)==0);
    assert(readAsset(0,0,output,0)==0);
    // EOF behavior is unchanged for a file shortened after folder validation.
    assert(truncate(path.fileSystemRepresentation,2)==0);
    assert(readAsset(0,0,output,sizeof output)==2);
    assert(readAsset(0,4,output,sizeof output)==0);
    assert(atomic_load(&healthReadErrors)==2);
    puts("PASS: interrupted local reads retry, short reads accumulate, real errors propagate, and EOF/range limits remain unchanged.");
  } @finally {
    PGSetLocalGameFolder(NULL);
    [files removeItemAtPath:root error:nil];
  }
}return 0;}
