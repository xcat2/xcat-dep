/*
 * Gives handle_fileseg() of the uftp receiver a block of the file, then blocks that the file does
 * not have. Built with the receiver objects and AddressSanitizer by native/uftp-fixes.t.
 */
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "client.h"
#include "client_transfer.h"

static void send_block(struct group_list_t *group, uint16_t section, uint16_t block)
{
    unsigned char message[sizeof(struct fileseg_h) + 4];
    struct fileseg_h *fileseg = (struct fileseg_h *)message;

    memset(message, 0, sizeof(message));
    fileseg->func = FILESEG;
    fileseg->hlen = sizeof(struct fileseg_h) / 4;
    fileseg->file_id = htons(group->file_id);
    fileseg->section = htons(section);
    fileseg->sec_block = htons(block);
    group->fileinfo.got_data = 0;
    handle_fileseg(group, message, sizeof(message), 0);
    printf("section %u block %u: %s\n", section, block, group->fileinfo.got_data ? "accepted" : "rejected");
}

int main(void)
{
    struct group_list_t group;

    memset(&group, 0, sizeof(group));
    group.file_id = 1;
    group.blocksize = 4;
    group.max_txseq = 1;
    group.fileinfo.ftype = FTYPE_REG;
    group.fileinfo.blocks = 2;
    group.fileinfo.size = 2 * group.blocksize;
    group.fileinfo.sections = 1;
    group.fileinfo.secsize_small = 2;
    group.fileinfo.secsize_big = 2;
    /* Every block is marked as received, so an accepted block is a duplicate that writes nothing. */
    group.fileinfo.naklist = calloc(group.fileinfo.blocks, 1);
    send_block(&group, 0, 1);
    send_block(&group, 0, 2);
    send_block(&group, 1, 0);
    free(group.fileinfo.naklist);
    return 0;
}
