/*
 * Seeks with seek_block() of the uftp sender to the last block below 2^31, to block 2^31, and to
 * the last block that the section count allows, in a file of 512-byte blocks. Built with the
 * sender objects and AddressSanitizer by native/uftp-fixes.t.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "server.h"
#include "uftp_common.h"

int seek_block(const struct finfo_t *finfo, int file, uint32_t block, f_offset_t *offset);

static void seek(const struct finfo_t *finfo, int fd, uint32_t block)
{
    f_offset_t offset = 0;

    lseek(fd, 0, SEEK_SET);
    if (seek_block(finfo, fd, block, &offset)) {
        printf("block %u: offset %lld\n", block, (long long)offset);
    } else {
        printf("block %u: failed\n", block);
    }
}

int main(void)
{
    struct finfo_t finfo;
    char path[] = "/tmp/uftp-seek-XXXXXX";
    int fd;

    applog = stderr;
    blocksize = 512;
    memset(&finfo, 0, sizeof(finfo));
    if ((fd = mkstemp(path)) == -1) {
        perror("mkstemp");
        return 2;
    }
    seek(&finfo, fd, 0x7FFFFFFF);
    seek(&finfo, fd, 0x80000000);
    seek(&finfo, fd, MAXSECTION * 0xFFFFU - 1);
    close(fd);
    unlink(path);
    return 0;
}
