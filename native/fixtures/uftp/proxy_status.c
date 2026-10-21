/*
 * Gives handle_status() of the uftp proxy the STATUS that a client sends for a section of 512-byte
 * blocks, sends the pending NAKs upstream with send_status(), and reads that STATUS back from a
 * loopback socket. The client STATUS covers a full section, a full section with the TFMCC
 * extension, and a short section followed by old data in the packet buffer. Built with the proxy
 * objects and AddressSanitizer by native/uftp-fixes.t.
 */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "proxy.h"
#include "proxy_downstream.h"
#include "proxy_upstream.h"
#include "uftp_common.h"

#define BLOCKSIZE 512

static struct pr_group_list_t group;
static int server;

static int bound_socket(union sockaddr_u *addr)
{
    socklen_t len = sizeof(addr->sin);
    struct timeval timeout = { 2, 0 };
    int s;

    memset(addr, 0, sizeof(*addr));
    addr->sin.sin_family = AF_INET;
    addr->sin.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (((s = socket(AF_INET, SOCK_DGRAM, 0)) == -1) ||
        (bind(s, (struct sockaddr *)&addr->sin, len) == -1) ||
        (getsockname(s, (struct sockaddr *)&addr->sin, &len) == -1) ||
        (setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) == -1)) {
        perror("socket");
        exit(2);
    }
    return s;
}

/*
 * Sends the proxy a client STATUS for a section of blocks blocks with a NAK for its last block, as
 * a client sends it: blocks / 8 + 1 bytes of NAKs after the header and its extensions. The packet
 * buffer holds 0xFF after the message.
 */
static void forward(const char *label, unsigned int blocks, int tfmcc)
{
    unsigned char message[MAXMTU], packet[MAXMTU], *naks;
    struct status_h *status = (struct status_h *)message;
    struct tfmcc_ack_info_he *ext = (struct tfmcc_ack_info_he *)(message + sizeof(struct status_h));
    unsigned int i, hlen;
    int len, naklen;

    memset(message, 0xFF, sizeof(message));
    hlen = sizeof(struct status_h) + (tfmcc ? sizeof(struct tfmcc_ack_info_he) : 0);
    memset(message, 0, hlen + (blocks / 8) + 1);
    status->func = STATUS;
    status->hlen = hlen / 4;
    status->file_id = htons(1);
    status->section = htons(0);
    if (tfmcc) {
        ext->exttype = EXT_TFMCC_ACK_INFO;
        ext->extlen = sizeof(struct tfmcc_ack_info_he) / 4;
        ext->cc_seq = htons(0xFFFF);
        ext->cc_rate = htons(0xFFFF);
        ext->client_id = 0xFFFFFFFF;
        ext->tstamp_hi = 0xFFFFFFFF;
        ext->tstamp_lo = 0xFFFFFFFF;
    }
    message[hlen + (blocks - 1) / 8] |= 1 << ((blocks - 1) % 8);
    handle_status(&group, 0, message, hlen + (blocks / 8) + 1);
    send_status(&group, 0);

    do {
        len = recv(server, packet, sizeof(packet), 0);
    } while ((len > (int)(sizeof(struct uftp_h) + sizeof(struct status_h))) &&
             (packet[1] != STATUS));
    if ((len <= (int)(sizeof(struct uftp_h) + sizeof(struct status_h))) ||
        (packet[1] != STATUS)) {
        printf("%s: no STATUS\n", label);
        return;
    }
    status = (struct status_h *)(packet + sizeof(struct uftp_h));
    naks = packet + sizeof(struct uftp_h) + (status->hlen * 4);
    naklen = len - (int)(naks - packet);
    printf("%s: %d bytes, NAKs", label, naklen);
    for (i = 0; i < (unsigned int)naklen * 8; i++) {
        if (naks[i >> 3] & (1 << (i & 7))) {
            printf(" %u", i);
        }
    }
    printf("\n");
}

int main(void)
{
    union sockaddr_u listener_addr, server_addr;

    applog = stderr;
    uid = htonl(0x0A000002);
    listener = bound_socket(&listener_addr);
    server = bound_socket(&server_addr);
    group.version = UFTP_VER_NUM;
    group.group_id = 1;
    group.blocksize = BLOCKSIZE;
    group.up_addr = server_addr;
    group.destcount = 1;
    group.destinfo[0].pending = -1;

    forward("full section", BLOCKSIZE * 8, 0);
    forward("tfmcc full section", BLOCKSIZE * 8, 1);
    forward("short section", 10, 0);
    return 0;
}
