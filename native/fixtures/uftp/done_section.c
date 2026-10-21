/*
 * Gives handle_done() of the uftp receiver a DONE for a section of the file and DONE messages for
 * a section past its end, then gets the NAKs of each section that the DONE scheduled, as the
 * receive loop does when the NAK timer expires. "empty" receives a file without sections.
 * Built with the receiver objects and AddressSanitizer by native/uftp-fixes.t.
 */
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "client.h"
#include "client_transfer.h"
#include "uftp_common.h"

void handle_fileinfo_regular(struct group_list_t *group);

static void send_done(struct group_list_t *group, const char *label, uint16_t section, int listed)
{
    unsigned char message[sizeof(struct done_h) + 4];
    struct done_h *done = (struct done_h *)message;
    uint32_t client = listed ? uid : uid + 1, s;
    unsigned char *naks;
    unsigned int nak_count = 0;

    group->fileinfo.nak_time.tv_sec = 0;
    group->fileinfo.nak_time.tv_usec = 0;
    group->fileinfo.nak_section_first = 0;
    group->fileinfo.nak_section_last = 0;
    group->fileinfo.last_section = 0;
    memset(message, 0, sizeof(message));
    done->func = DONE;
    done->hlen = sizeof(struct done_h) / 4;
    done->file_id = htons(group->file_id);
    done->section = htons(section);
    memcpy(message + sizeof(struct done_h), &client, sizeof(client));
    handle_done(group, message, sizeof(message));
    for (s = group->fileinfo.nak_section_first; s < group->fileinfo.nak_section_last; s++) {
        naks = NULL;
        nak_count += get_naks(group, s, &naks);
        free(naks);
    }
    printf("%s: sections %u-%u, %u NAKs\n", label, group->fileinfo.nak_section_first,
           group->fileinfo.nak_section_last, nak_count);
}

int main(int argc, char **argv)
{
    struct group_list_t group;
    char path[] = "/tmp/uftp-done-XXXXXX";
    int fd, empty = argc > 1 && !strcmp(argv[1], "empty");

    memset(&group, 0, sizeof(group));
    applog = stderr;
    listener = INVALID_SOCKET;
    cache_len = 1048576;
    uid = htonl(0x0A000001);
    group.file_id = 1;
    group.blocksize = 1300;
    group.fileinfo.ftype = FTYPE_REG;
    if (!empty) {
        /* One section of two blocks. */
        group.fileinfo.size = 2 * 1300;
        group.fileinfo.blocks = 2;
        group.fileinfo.sections = 1;
        group.fileinfo.big_sections = 1;
        group.fileinfo.secsize_big = 2;
        group.fileinfo.secsize_small = 2;
    }
    if ((fd = mkstemp(path)) == -1) {
        perror("mkstemp");
        return 2;
    }
    close(fd);
    strncpy(group.fileinfo.filepath, path, sizeof(group.fileinfo.filepath) - 1);
    handle_fileinfo_regular(&group);

    if (empty) {
        send_done(&group, "empty unlisted", 0, 0);
    } else {
        send_done(&group, "section 0 listed", 0, 1);
        send_done(&group, "section 1 listed", 1, 1);
        send_done(&group, "section 1 unlisted", 1, 0);
    }
    unlink(path);
    return 0;
}
