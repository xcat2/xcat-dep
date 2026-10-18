/*
 * Starts a file in one group of the uftp receiver, then receives a file of the same name in a
 * second group, which replaces the first file, and completes it. The first group then ends: it
 * aborts, or with "complete" it completes. A third group completes a file and a fourth aborts
 * one without another group in the way. Receives straight into the destination directory (-D
 * without -T). Built with the receiver objects and AddressSanitizer by native/uftp-fixes.t.
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

#define TSTAMP 1000000000

static void start_group(struct group_list_t *group, uint32_t group_id)
{
    memset(group, 0, sizeof(*group));
    group->version = UFTP_VER_NUM;
    group->group_id = group_id;
    group->blocksize = 1300;
    group->phase = PHASE_MIDGROUP;
    group->fileinfo.fd = -1;
}

static void send_fileinfo(struct group_list_t *group, const char *name)
{
    unsigned char message[sizeof(struct fileinfo_h) + MAXPATHNAME + 8];
    struct fileinfo_h *fileinfo = (struct fileinfo_h *)message;
    int namelen = (int)(strlen(name) + 4) / 4;
    struct timeval now;

    memset(message, 0, sizeof(message));
    fileinfo->func = FILEINFO;
    fileinfo->hlen = (sizeof(struct fileinfo_h) / 4) + namelen;
    fileinfo->file_id = htons(1);
    fileinfo->ftype = FTYPE_REG;
    fileinfo->namelen = namelen;
    fileinfo->lofsize = htonl(2600);
    memcpy(message + sizeof(struct fileinfo_h), name, strlen(name));
    memcpy(message + (fileinfo->hlen * 4), &uid, sizeof(uid));
    gettimeofday(&now, NULL);
    handle_fileinfo(group, message, (fileinfo->hlen * 4) + sizeof(uid), now);
    group->fileinfo.tstamp = TSTAMP;
}

static void report(const char *label, const char *path, const char *content)
{
    struct stat statbuf;
    char buf[64];
    ssize_t len = -1;
    int fd;

    if ((fd = open(path, O_RDONLY)) != -1) {
        len = read(fd, buf, sizeof(buf) - 1);
        close(fd);
    }
    if (len < 0 || lstat(path, &statbuf) == -1) {
        printf("%s: absent\n", label);
        return;
    }
    buf[len] = '\x0';
    printf("%s: %s, time %s\n", label, strcmp(buf, content) ? "other content" : content,
           statbuf.st_mtime == TSTAMP ? "set" : "kept");
}

int main(int argc, char **argv)
{
    struct group_list_t first, second, third, fourth;
    char base[] = "/tmp/uftp-replaced-XXXXXX", path[MAXPATHNAME];
    int complete = argc > 1 && !strcmp(argv[1], "complete");

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

    start_group(&first, 1);
    send_fileinfo(&first, "image");
    start_group(&second, 2);
    send_fileinfo(&second, "image");
    if (write(second.fileinfo.fd, "second", 6) != 6) {
        perror("write");
    }
    second.fileinfo.tstamp = 0;
    file_cleanup(&second, 0);
    file_cleanup(&first, !complete);
    snprintf(path, sizeof(path), "%s/image", destdir[0]);
    report("replaced file", path, "second");

    start_group(&third, 3);
    send_fileinfo(&third, "done");
    if (write(third.fileinfo.fd, "third", 5) != 5) {
        perror("write");
    }
    file_cleanup(&third, 0);
    snprintf(path, sizeof(path), "%s/done", destdir[0]);
    report("completed file", path, "third");

    start_group(&fourth, 4);
    send_fileinfo(&fourth, "partial");
    file_cleanup(&fourth, 1);
    snprintf(path, sizeof(path), "%s/partial", destdir[0]);
    report("aborted file", path, "");
    return 0;
}
