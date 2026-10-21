/*
 * Gives send_file() of the uftp sender a sparse file one byte larger than 65535 sections of 512
 * byte blocks hold. Built with the sender objects and AddressSanitizer by native/uftp-fixes.t.
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "server.h"
#include "uftp_common.h"

int send_file(const char *f_basedir, const char *filename, const char *n_destfname,
              uint32_t group_id, uint8_t group_inst, int delete, int freespace);

int main(void)
{
    char dir[] = "/tmp/uftp-size-XXXXXX", path[MAXPATHNAME];
    int fd;

    applog = stderr;
    blocksize = 512;
    if (!mkdtemp(dir)) {
        perror("mkdtemp");
        return 2;
    }
    snprintf(path, sizeof(path), "%s/big", dir);
    if ((fd = open(path, O_CREAT | O_WRONLY, 0644)) == -1 ||
            ftruncate(fd, (off_t)512 * 4096 * 65535 + 1) == -1) {
        perror(path);
        return 2;
    }
    close(fd);
    printf("send_file returned %s\n",
           send_file(dir, "big", "big", 1, 0, 0, 0) == ERR_PARAM ? "ERR_PARAM" : "another code");
    unlink(path);
    rmdir(dir);
    return 0;
}
