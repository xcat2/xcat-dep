/*
 * Gives the transfer and completion phases of the uftp sender an encrypted message with the ID of a
 * listed client that has no encryption state, as a client that never registered. Built with the
 * sender objects and AddressSanitizer by native/uftp-fixes.t.
 */
#include <arpa/inet.h>
#include <stdio.h>
#include <string.h>

#include "server.h"

void handle_transfer_phase(unsigned char *packet, unsigned char *decrypted, int packetlen,
                           const union sockaddr_u *receiver, struct finfo_t *finfo, int *got_naks);
void handle_completion_phase(unsigned char *packet, unsigned char *decrypted, int packetlen,
                             const union sockaddr_u *receiver, struct finfo_t *finfo);

int main(void)
{
    static unsigned char packet[256], decrypted[MAXMTU];
    struct uftp_h *header = (struct uftp_h *)packet;
    union sockaddr_u receiver;
    struct finfo_t finfo;
    int got_naks = 0;

    memset(&receiver, 0, sizeof(receiver));
    memset(&finfo, 0, sizeof(finfo));
    keytype = KEY_AES256_GCM;
    destcount = 1;
    destlist[0].id = htonl(0xC0000234);
    strcpy(destlist[0].name, "receiver");
    header->func = ENCRYPTED;
    header->src_id = destlist[0].id;
    handle_transfer_phase(packet, decrypted, sizeof(packet), &receiver, &finfo, &got_naks);
    printf("transfer phase: survived\n");
    handle_completion_phase(packet, decrypted, sizeof(packet), &receiver, &finfo);
    printf("completion phase: survived\n");
    return 0;
}
