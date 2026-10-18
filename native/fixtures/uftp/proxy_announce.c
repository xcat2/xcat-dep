/*
 * Gives read_announce() of the uftp proxy an unencrypted ANNOUNCE with each block size in turn.
 * Built with the proxy objects and AddressSanitizer by native/uftp-fixes.t.
 */
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "proxy.h"
#include "uftp_common.h"

int read_announce(struct pr_group_list_t *group, unsigned char *packet, const union sockaddr_u *src,
                  int packetlen);

static void announce(unsigned int blocksize)
{
    unsigned char packet[sizeof(struct uftp_h) + sizeof(struct announce_h) + 8];
    struct uftp_h *header = (struct uftp_h *)packet;
    struct announce_h *ann = (struct announce_h *)(packet + sizeof(struct uftp_h));
    struct pr_group_list_t group;
    union sockaddr_u src;

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
    printf("block size %u: %s\n", blocksize,
           read_announce(&group, packet, &src, sizeof(packet)) ? "accepted" : "rejected");
}

int main(void)
{
    static const unsigned int sizes[] = { 0, 511, 512, 1300, MAXMTU - 200, MAXMTU - 199, 65535 };
    unsigned int i;

    applog = stderr;
    listener = INVALID_SOCKET;
    for (i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        announce(sizes[i]);
    }
    return 0;
}
