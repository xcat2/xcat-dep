/*
 * Starts a file in one group of the uftp receiver, replaces a directory of its path with a symbolic
 * link from a second group, then aborts the first file. A third group aborts a file normally.
 * Receives straight into the destination directory (-D without -T).
 * Built with the receiver objects and AddressSanitizer by native/uftp-fixes.t.
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

static void start_group(struct group_list_t *group, uint32_t group_id)
{
    memset(group, 0, sizeof(*group));
    group->version = UFTP_VER_NUM;
    group->group_id = group_id;
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
    struct group_list_t first, second, third;
    char base[] = "/tmp/uftp-cleanup-XXXXXX", path[MAXPATHNAME];
    int fd;

    if (!mkdtemp(base)) {
        perror("mkdtemp");
        return 2;
    }
    applog = stderr;
    listener = INVALID_SOCKET;
    cache_len = DEF_CACHE;
    uid = htonl(0x0A000001);
    snprintf(destdir[0], sizeof(destdir[0]), "%s/dest", base);
    destdircnt = 1;
    mkdir(destdir[0], 0755);
    snprintf(path, sizeof(path), "%s/outside", base);
    mkdir(path, 0755);
    snprintf(path, sizeof(path), "%s/outside/sub", base);
    mkdir(path, 0755);
    snprintf(path, sizeof(path), "%s/outside/sub/victim", base);
    if ((fd = open(path, O_CREAT | O_WRONLY, 0644)) != -1) {
        close(fd);
    }

    start_group(&first, 1);
    send_fileinfo(&first, FTYPE_REG, "a/sub/victim", NULL, 2600);
    start_group(&second, 2);
    send_fileinfo(&second, FTYPE_LINK, "a", "../outside", 0);
    file_cleanup(&first, 1);
    report("outside victim", path);

    start_group(&third, 3);
    send_fileinfo(&third, FTYPE_REG, "c/partial", NULL, 2600);
    file_cleanup(&third, 1);
    snprintf(path, sizeof(path), "%s/c/partial", destdir[0]);
    report("aborted partial", path);
    return 0;
}
