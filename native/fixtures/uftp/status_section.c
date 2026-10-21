/*
 * Drives handle_status() of the uftp sender with a STATUS that a receiver in the session can send.
 * Built with the sender objects and AddressSanitizer by t/uftp_status_section.t.
 */
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "server.h"
#include "server_config.h"
#include "server_transfer.h"

extern uint32_t current_position;

static int send_status(struct finfo_t *finfo, uint16_t section)
{
    unsigned char message[sizeof(struct status_h) + 1];
    struct status_h *status = (struct status_h *)message;
    int got_naks = 0;

    memset(message, 0, sizeof(message));
    status->func = STATUS;
    status->hlen = sizeof(struct status_h) / 4;
    status->file_id = htons(finfo->file_id);
    status->section = htons(section);
    message[sizeof(struct status_h)] = 1;
    handle_status(message, sizeof(message), finfo, 0, &got_naks);
    return got_naks;
}

int main(void)
{
    struct finfo_t finfo;

    memset(&finfo, 0, sizeof(finfo));
    finfo.file_id = 1;
    finfo.blocks = 2;
    finfo.sections = 1;
    finfo.secsize_small = 2;
    finfo.secsize_big = 2;
    finfo.naklist = calloc(finfo.blocks, 1);
    strcpy(destlist[0].name, "receiver");
    destcount = 1;
    max_nak_pct = 100;
    max_nak_cnt = 1;
    current_position = finfo.blocks;

    printf("section 0: %d\n", send_status(&finfo, 0));
    printf("section 1: %d\n", send_status(&finfo, 1));
    free(finfo.naklist);
    return 0;
}
