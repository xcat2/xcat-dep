/*
 * Receives a file through handle_fileseg() of the uftp receiver and checks the file on disk.
 * "short-tail" ends the file with a short block at the end of the default disk cache.
 * "long-repeat" then sends that last block again with a full block of data.
 * "short-last" sends a last block shorter than the end of the file, then the right one.
 * "lost-blocks" loses blocks before a full disk cache of the smallest size with the largest blocks.
 * Built with the receiver objects and AddressSanitizer by native/uftp-fixes.t.
 */
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "client.h"
#include "client_common.h"
#include "client_config.h"
#include "client_transfer.h"
#include "uftp_common.h"

void handle_fileinfo_regular(struct group_list_t *group);

static unsigned char byte_at(f_offset_t offset)
{
    return (unsigned char)(offset * 7 + offset / 251);
}

/* Sends a block with len bytes of file data, or with the data of the file when len is 0. */
static void send_block(struct group_list_t *group, uint32_t block, int len)
{
    f_offset_t start = (f_offset_t)block * group->blocksize;
    int i;
    unsigned char *message;
    struct fileseg_h *fileseg;

    if (!len) {
        len = group->blocksize;
        if (group->fileinfo.size - start < len) {
            len = (int)(group->fileinfo.size - start);
        }
    }
    message = calloc(sizeof(struct fileseg_h) + len, 1);
    fileseg = (struct fileseg_h *)message;
    fileseg->func = FILESEG;
    fileseg->hlen = sizeof(struct fileseg_h) / 4;
    fileseg->file_id = htons(group->file_id);
    fileseg->section = htons(0);
    fileseg->sec_block = htons(block);
    for (i = 0; i < len; i++) {
        message[sizeof(struct fileseg_h) + i] = byte_at(start + i);
    }
    handle_fileseg(group, message, sizeof(struct fileseg_h) + len, 0);
    free(message);
}

int main(int argc, char **argv)
{
    static const uint32_t lost_order[] = { 0, 5, 6, 7, 1, 2, 3, 4 };
    struct group_list_t group;
    char path[] = "/tmp/uftp-cache-XXXXXX";
    unsigned char *data;
    uint32_t block, missing = 0;
    f_offset_t i, differ = 0;
    int lost, fd;
    FILE *fp;

    if (argc != 2) {
        fprintf(stderr, "usage: %s short-tail|long-repeat|short-last|lost-blocks\n", argv[0]);
        return 2;
    }
    lost = !strcmp(argv[1], "lost-blocks");
    memset(&group, 0, sizeof(group));
    group.file_id = 1;
    group.max_txseq = 1;
    group.fileinfo.ftype = FTYPE_REG;
    if (lost) {
        cache_len = 10240;
        group.blocksize = 8800;
        group.fileinfo.size = 7 * 8800 + 100;
    } else {
        /* 1300 bytes is the default block size of the sender. */
        cache_len = DEF_CACHE;
        group.blocksize = 1300;
        group.fileinfo.size = (f_offset_t)(DEF_CACHE / 1300) * 1300 + DEF_CACHE % 1300;
        if (!strcmp(argv[1], "short-last")) {
            /* The right last block does not fit after block 805, a short one does. */
            group.fileinfo.size += 1000 - DEF_CACHE % 1300;
        }
    }
    group.fileinfo.blocks =
        (uint32_t)((group.fileinfo.size + group.blocksize - 1) / group.blocksize);
    group.fileinfo.sections = 1;
    group.fileinfo.big_sections = 1;
    group.fileinfo.secsize_big = group.fileinfo.blocks;
    group.fileinfo.secsize_small = group.fileinfo.blocks;
    if ((fd = mkstemp(path)) == -1) {
        perror("mkstemp");
        return 2;
    }
    close(fd);
    strncpy(group.fileinfo.filepath, path, sizeof(group.fileinfo.filepath) - 1);
    applog = stderr;
    listener = INVALID_SOCKET;

    handle_fileinfo_regular(&group);
    if (lost) {
        for (block = 0; block < sizeof(lost_order) / sizeof(lost_order[0]); block++) {
            send_block(&group, lost_order[block], 0);
        }
    } else {
        for (block = 0; block < group.fileinfo.blocks - 1; block++) {
            send_block(&group, block, 0);
        }
        if (!strcmp(argv[1], "short-last")) {
            send_block(&group, block, 500);
        }
        send_block(&group, block, 0);
        if (!strcmp(argv[1], "long-repeat")) {
            send_block(&group, block, group.blocksize);
        }
    }
    flush_disk_cache(&group);
    close(group.fileinfo.fd);

    for (block = 0; block < group.fileinfo.blocks; block++) {
        missing += group.fileinfo.naklist[block];
    }
    data = calloc(group.fileinfo.size + 1, 1);
    fp = fopen(path, "rb");
    if (!fp || fread(data, 1, group.fileinfo.size + 1, fp) != (size_t)group.fileinfo.size) {
        differ = 1;
    }
    for (i = 0; !differ && i < group.fileinfo.size; i++) {
        differ = data[i] != byte_at(i);
    }
    if (fp) {
        fclose(fp);
    }
    unlink(path);
    printf("%s: %u blocks, %u missing, file %s\n", argv[1], group.fileinfo.blocks, missing,
           differ ? "differs" : "matches");
    return 0;
}
