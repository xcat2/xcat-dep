/*
 * Gives read_fileinfo() of the uftp receiver FILEINFO messages for a file of the largest size that
 * 65535 sections of 512 byte blocks hold, and for a file one byte larger, then aborts the group.
 * Descriptor 0 holds the file of another transfer.
 * Built with the receiver objects and AddressSanitizer by native/uftp-fixes.t.
 */
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

#include "client.h"
#include "client_common.h"
#include "uftp_common.h"

int read_fileinfo(struct group_list_t *group, const unsigned char *message, int meslen,
                  struct timeval rxtime);

static void fileinfo(f_offset_t size)
{
    unsigned char message[sizeof(struct fileinfo_h) + 8];
    struct fileinfo_h *info = (struct fileinfo_h *)message;
    struct group_list_t group;
    struct timeval now;
    int accepted;

    memset(message, 0, sizeof(message));
    memset(&group, 0, sizeof(group));
    group.version = UFTP_VER_NUM;
    group.blocksize = 512;
    group.phase = PHASE_MIDGROUP;
    info->func = FILEINFO;
    info->hlen = (sizeof(struct fileinfo_h) / 4) + 1;
    info->file_id = htons(1);
    info->ftype = FTYPE_REG;
    info->namelen = 1;
    info->hifsize = htons((uint16_t)(size >> 32));
    info->lofsize = htonl((uint32_t)(size & 0xFFFFFFFF));
    memcpy(message + sizeof(struct fileinfo_h), "big", 3);
    memcpy(message + (info->hlen * 4), &uid, sizeof(uid));
    gettimeofday(&now, NULL);
    accepted = read_fileinfo(&group, message, sizeof(message), now);
    printf("size %lld: %s", (long long)size, accepted ? "accepted" : "rejected");
    if (accepted) {
        printf(", %u sections", group.fileinfo.sections);
    }
    printf("\n");
    file_cleanup(&group, 1);
}

int main(void)
{
    f_offset_t limit = (f_offset_t)512 * 4096 * 65535;
    char path[] = "/tmp/uftp-fd0-XXXXXX";

    applog = stderr;
    listener = INVALID_SOCKET;
    uid = htonl(0x0A000001);
    close(0);
    if (mkstemp(path) != 0) {
        fprintf(stderr, "descriptor 0 is not free\n");
        return 2;
    }
    fileinfo(limit);
    fileinfo(limit + 1);
    printf("fd 0: %s\n", fcntl(0, F_GETFD) == -1 ? "closed" : "open");
    unlink(path);
    return 0;
}
