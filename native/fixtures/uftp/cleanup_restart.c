/*
 * Interrupts a file in a group of the uftp receiver, restarts the group, replaces a directory of
 * the path of that file with a symbolic link from the restarted group, and aborts it without the
 * file. A second group restarts the same way without the link. Receives into a temp directory
 * (-T). Built with the receiver objects and AddressSanitizer by native/uftp-fixes.t.
 */
#include <arpa/inet.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

#include "client.h"
#include "client_common.h"
#include "client_config.h"
#include "client_fileinfo.h"
#include "uftp_common.h"

static void start_group(struct group_list_t *group, uint32_t group_id, uint8_t group_inst)
{
    memset(group, 0, sizeof(*group));
    group->version = UFTP_VER_NUM;
    group->group_id = group_id;
    group->group_inst = group_inst;
    group->blocksize = 1300;
    group->phase = PHASE_MIDGROUP;
    group->fileinfo.fd = -1;
}

static void send_fileinfo(struct group_list_t *group, int ftype, const char *name, const char *link,
                          uint32_t size)
{
    unsigned char message[sizeof(struct fileinfo_h) + 2 * MAXPATHNAME + 8];
    struct fileinfo_h *fileinfo = (struct fileinfo_h *)message;
    int namelen = (int)(strlen(name) + 4) / 4;
    int linklen = link ? (int)(strlen(link) + 4) / 4 : 0;
    struct timeval now;

    memset(message, 0, sizeof(message));
    fileinfo->func = FILEINFO;
    fileinfo->hlen = (sizeof(struct fileinfo_h) / 4) + namelen + linklen;
    fileinfo->file_id = htons(1);
    fileinfo->ftype = ftype;
    fileinfo->namelen = namelen;
    fileinfo->linklen = linklen;
    fileinfo->lofsize = htonl(size);
    memcpy(message + sizeof(struct fileinfo_h), name, strlen(name));
    if (link) {
        memcpy(message + sizeof(struct fileinfo_h) + (namelen * 4), link, strlen(link));
    }
    memcpy(message + (fileinfo->hlen * 4), &uid, sizeof(uid));
    gettimeofday(&now, NULL);
    handle_fileinfo(group, message, (fileinfo->hlen * 4) + sizeof(uid), now);
}

static void report(const char *label, const char *path)
{
    struct stat statbuf;

    printf("%s: %s\n", label, lstat(path, &statbuf) == 0 ? "present" : "absent");
}

int main(void)
{
    struct group_list_t first, restarted;
    char base[] = "/tmp/uftp-restart-XXXXXX", path[MAXPATHNAME];
    int fd;

    if (!mkdtemp(base)) {
        perror("mkdtemp");
        return 2;
    }
    applog = stderr;
    listener = INVALID_SOCKET;
    cache_len = DEF_CACHE;
    uid = htonl(0x0A000001);
    snprintf(tempdir, sizeof(tempdir), "%s/temp", base);
    mkdir(tempdir, 0755);
    snprintf(destdir[0], sizeof(destdir[0]), "%s/dest", base);
    destdircnt = 1;
    mkdir(destdir[0], 0755);
    snprintf(path, sizeof(path), "%s/outside", base);
    mkdir(path, 0755);
    snprintf(path, sizeof(path), "%s/outside/victim", base);
    if ((fd = open(path, O_CREAT | O_WRONLY, 0644)) != -1) {
        close(fd);
    }

    start_group(&first, 1, 0);
    send_fileinfo(&first, FTYPE_REG, "a/victim", NULL, 2600);
    file_cleanup(&first, 1);
    start_group(&restarted, 1, 1);
    read_restart_file(&restarted);
    send_fileinfo(&restarted, FTYPE_LINK, "a", "../../outside", 0);
    file_cleanup(&restarted, 1);
    report("outside victim", path);

    start_group(&first, 2, 0);
    send_fileinfo(&first, FTYPE_REG, "c/partial", NULL, 2600);
    file_cleanup(&first, 1);
    snprintf(path, sizeof(path), "%s/_group_00000002/c/partial", tempdir);
    report("interrupted partial", path);
    start_group(&restarted, 2, 1);
    read_restart_file(&restarted);
    file_cleanup(&restarted, 1);
    report("unused partial", path);
    return 0;
}
