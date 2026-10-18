/*
 * Receives into a destination directory with a backup directory (-D and -A, without -T). One
 * group creates a symbolic link to a directory outside both, and the next replaces it with a
 * directory, which moves the link into the backup directory. Two more groups create a file below
 * that directory and overwrite it, which backs the file up below the moved link. A last pair of
 * groups overwrites a file without a link in the way, and three groups receive a file whose backup
 * path is longer than MAXPATHNAME. Built with the receiver objects and AddressSanitizer by
 * native/uftp-fixes.t.
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
    snprintf(group->start_date, sizeof(group->start_date), "20261018");
    snprintf(group->start_time, sizeof(group->start_time), "120000");
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

/* Receives a file that holds content, as one group. */
static void receive(uint32_t group_id, const char *name, const char *content)
{
    struct group_list_t group;

    start_group(&group, group_id);
    send_fileinfo(&group, FTYPE_REG, name, NULL, 2600);
    if ((group.fileinfo.fd >= 0) &&
        (write(group.fileinfo.fd, content, strlen(content)) != (ssize_t)strlen(content))) {
        perror("write");
    }
    file_cleanup(&group, 0);
}

static void report(const char *label, const char *path)
{
    char buf[64];
    ssize_t len = -1;
    int fd;

    if ((fd = open(path, O_RDONLY)) != -1) {
        len = read(fd, buf, sizeof(buf) - 1);
        close(fd);
    }
    if (len < 0) {
        printf("%s: absent\n", label);
    } else {
        buf[len] = '\x0';
        printf("%s: %s\n", label, buf);
    }
}

int main(void)
{
    struct group_list_t group;
    char base[] = "/tmp/uftp-backup-XXXXXX", path[MAXBACKUPPATHNAME], outside[MAXPATHNAME];
    char name[MAXPATHNAME], dir[60];
    int fd, len;

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
    snprintf(backupdir[0], sizeof(backupdir[0]), "%s/backup", base);
    backupcnt = 1;
    mkdir(backupdir[0], 0755);
    snprintf(outside, sizeof(outside), "%s/outside", base);
    mkdir(outside, 0755);
    snprintf(path, sizeof(path), "%s/outside/sub", base);
    mkdir(path, 0755);
    snprintf(path, sizeof(path), "%s/outside/sub/victim", base);
    if ((fd = open(path, O_CREAT | O_WRONLY, 0644)) != -1) {
        if (write(fd, "outside", 7) != 7) {
            perror("write");
        }
        close(fd);
    }

    start_group(&group, 1);
    send_fileinfo(&group, FTYPE_LINK, "up", outside, 0);
    start_group(&group, 2);
    send_fileinfo(&group, FTYPE_DIR, "up", NULL, 0);
    receive(3, "up/sub/victim", "first");
    receive(4, "up/sub/victim", "second");
    report("outside victim", path);
    snprintf(path, sizeof(path), "%s/up/sub/victim", destdir[0]);
    report("received file", path);

    receive(5, "plain", "first");
    receive(6, "plain", "second");
    snprintf(path, sizeof(path), "%s/20261018/120000/%s/plain", backupdir[0], destdir[0]);
    report("backup of plain", path);
    snprintf(path, sizeof(path), "%s/plain", destdir[0]);
    report("plain", path);

    /* Four directories and a file name that bring the file path 25 bytes below MAXPATHNAME,
       which leaves room for the temp file suffix. */
    memset(dir, 'd', sizeof(dir) - 1);
    dir[sizeof(dir) - 1] = '\x0';
    len = snprintf(name, sizeof(name), "%s/%s/%s/%s/", dir, dir, dir, dir);
    memset(name + len, 'f', MAXPATHNAME - 25 - (strlen(destdir[0]) + 1) - len);
    name[MAXPATHNAME - 25 - (strlen(destdir[0]) + 1)] = '\x0';
    receive(7, name, "first");
    receive(8, name, "second");
    receive(9, name, "third");
    snprintf(path, sizeof(path), "%s/20261018/120000/%s/%s", backupdir[0], destdir[0], name);
    printf("long backup path: %zu bytes\n", strlen(path));
    report("backup of long", path);
    snprintf(path, sizeof(path), "%s/%s", destdir[0], name);
    report("long", path);
    return 0;
}
