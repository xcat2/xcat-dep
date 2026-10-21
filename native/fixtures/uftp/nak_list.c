/*
 * Builds the NAK list of a full section and of a short section with get_naks() of the uftp
 * receiver, sends each with send_status() as the receive loop does when the NAK timer expires,
 * and reads the STATUS back from a loopback socket. Built with the receiver objects and
 * AddressSanitizer by native/uftp-fixes.t.
 */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "client.h"
#include "client_transfer.h"
#include "uftp_common.h"

void handle_fileinfo_regular(struct group_list_t *group);

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

/* Receives every block but the last one of a file of blocks 512-byte blocks in one section. */
static void send_naks(const char *label, uint32_t blocks, int receiver, const union sockaddr_u *to)
{
    struct group_list_t group;
    unsigned char packet[MAXMTU], *naks;
    const struct status_h *status = (const struct status_h *)(packet + sizeof(struct uftp_h));
    char path[] = "/tmp/uftp-naks-XXXXXX";
    unsigned int nak_count, i;
    int fd, len, naklen;

    memset(&group, 0, sizeof(group));
    group.group_id = 1;
    group.file_id = 1;
    group.blocksize = 512;
    group.fileinfo.ftype = FTYPE_REG;
    group.fileinfo.size = (f_offset_t)blocks * group.blocksize;
    group.fileinfo.blocks = blocks;
    /* One section, as read_fileinfo() splits a file of up to blocksize * 8 blocks. */
    group.fileinfo.sections = 1;
    group.fileinfo.secsize_small = blocks;
    group.fileinfo.secsize_big = blocks + 1;
    group.fileinfo.big_sections = 0;
    if ((fd = mkstemp(path)) == -1) {
        perror("mkstemp");
        exit(2);
    }
    close(fd);
    strncpy(group.fileinfo.filepath, path, sizeof(group.fileinfo.filepath) - 1);
    group.replyaddr = *to;
    handle_fileinfo_regular(&group);
    memset(group.fileinfo.naklist, 0, blocks);
    group.fileinfo.naklist[blocks - 1] = 1;

    naks = NULL;
    nak_count = get_naks(&group, 0, &naks);
    send_status(&group, 0, naks, nak_count);
    free(naks);

    do {
        len = recv(receiver, packet, sizeof(packet), 0);
    } while ((len > (int)(sizeof(struct uftp_h) + sizeof(struct status_h))) &&
             (packet[1] != STATUS));
    if ((len <= (int)(sizeof(struct uftp_h) + sizeof(struct status_h))) ||
        (packet[1] != STATUS)) {
        printf("%s: no STATUS\n", label);
    } else {
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
    close(group.fileinfo.fd);
    free(group.fileinfo.naklist);
    free(group.fileinfo.section_done);
    free(group.fileinfo.cache);
    free(group.fileinfo.cache_status);
    unlink(path);
}

int main(void)
{
    union sockaddr_u listener_addr, receiver_addr;
    int receiver;

    applog = stderr;
    cache_len = 1048576;
    uid = htonl(0x0A000001);
    listener = bound_socket(&listener_addr);
    receiver = bound_socket(&receiver_addr);
    send_naks("full section", 512 * 8, receiver, &receiver_addr);
    send_naks("short section", 10, receiver, &receiver_addr);
    return 0;
}
