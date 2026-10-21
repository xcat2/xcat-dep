/*
 * Gives read_announce() of the uftp receiver an unencrypted ANNOUNCE with each block size in turn,
 * while descriptor 0 holds the file of another transfer.
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
#include "uftp_common.h"

int read_announce(struct group_list_t *group, unsigned char *packet, union sockaddr_u *src,
                  struct timeval rxtime, int packetlen);

static void announce(unsigned int blocksize)
{
    unsigned char packet[sizeof(struct uftp_h) + sizeof(struct announce_h) + 8];
    struct uftp_h *header = (struct uftp_h *)packet;
    struct announce_h *ann = (struct announce_h *)(packet + sizeof(struct uftp_h));
    struct group_list_t group;
    union sockaddr_u src;
    struct timeval now;

    memset(packet, 0, sizeof(packet));
    memset(&group, 0, sizeof(group));
    memset(&src, 0, sizeof(src));
    src.sin.sin_family = AF_INET;
    header->version = UFTP_VER_NUM;
    header->func = ANNOUNCE;
    header->group_id = htonl(1);
    ann->func = ANNOUNCE;
    ann->hlen = (sizeof(struct announce_h) + 8) / 4;
    ann->robust = 2;
    ann->blocksize = htons(blocksize);
    gettimeofday(&now, NULL);
    printf("block size %u: %s\n", blocksize,
           read_announce(&group, packet, &src, now, sizeof(packet)) ? "accepted" : "rejected");
}

int main(void)
{
    static const unsigned int sizes[] = { 0, 511, 512, 1300, MAXMTU - 200, MAXMTU - 199, 65535 };
    char path[] = "/tmp/uftp-fd0-XXXXXX";
    unsigned int i;

    applog = stderr;
    listener = INVALID_SOCKET;
    close(0);
    if (mkstemp(path) != 0) {
        fprintf(stderr, "descriptor 0 is not free\n");
        return 2;
    }
    for (i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        announce(sizes[i]);
    }
    printf("fd 0: %s\n", fcntl(0, F_GETFD) == -1 ? "closed" : "open");
    unlink(path);
    return 0;
}
