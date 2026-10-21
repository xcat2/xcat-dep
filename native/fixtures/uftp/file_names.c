/*
 * Gives handle_fileinfo() of the uftp receiver FILEINFO messages whose names try to leave the
 * destination directory, then reports which of the files exist. "temp" receives into a temp
 * directory (-T) and skips the absolute names, which a temp directory rejects.
 * Built with the receiver objects and AddressSanitizer by native/uftp-fixes.t.
 */
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

#include "client.h"
#include "client_config.h"
#include "client_fileinfo.h"
#include "uftp_common.h"

static void send_fileinfo(struct group_list_t *group, int ftype, const char *name, const char *link)
{
    static uint16_t file_id;
    unsigned char message[sizeof(struct fileinfo_h) + 2 * MAXPATHNAME + 8];
    struct fileinfo_h *fileinfo = (struct fileinfo_h *)message;
    int namelen = (int)(strlen(name) + 4) / 4;
    int linklen = link ? (int)(strlen(link) + 4) / 4 : 0;
    struct timeval now;

    memset(message, 0, sizeof(message));
    fileinfo->func = FILEINFO;
    fileinfo->hlen = (sizeof(struct fileinfo_h) / 4) + namelen + linklen;
    fileinfo->file_id = htons(++file_id);
    fileinfo->ftype = ftype;
    fileinfo->namelen = namelen;
    fileinfo->linklen = linklen;
    memcpy(message + sizeof(struct fileinfo_h), name, strlen(name));
    if (link) {
        memcpy(message + sizeof(struct fileinfo_h) + (namelen * 4), link, strlen(link));
    }
    memcpy(message + (fileinfo->hlen * 4), &uid, sizeof(uid));
    group->phase = PHASE_MIDGROUP;
    gettimeofday(&now, NULL);
    handle_fileinfo(group, message, (fileinfo->hlen * 4) + sizeof(uid), now);
    if (group->fileinfo.fd != -1) {
        close(group->fileinfo.fd);
        group->fileinfo.fd = -1;
    }
}

static void report(const char *label, const char *dir, const char *name)
{
    char path[MAXPATHNAME];
    struct stat statbuf;

    snprintf(path, sizeof(path), "%s/%s", dir, name);
    printf("%s: %s\n", label, lstat(path, &statbuf) == 0 ? "present" : "absent");
}

int main(int argc, char **argv)
{
    struct group_list_t group;
    char base[] = "/tmp/uftp-names-XXXXXX", dest[MAXPATHNAME], root[MAXPATHNAME];
    char path[MAXPATHNAME], name[MAXPATHNAME];
    int temp = argc > 1 && !strcmp(argv[1], "temp");

    if (!mkdtemp(base)) {
        perror("mkdtemp");
        return 2;
    }
    snprintf(dest, sizeof(dest), "%s/dest", base);
    mkdir(dest, 0755);
    snprintf(path, sizeof(path), "%s/outside", base);
    mkdir(path, 0755);
    snprintf(path, sizeof(path), "%s/outside/sub", base);
    mkdir(path, 0755);
    snprintf(path, sizeof(path), "%s/dest-other", base);
    mkdir(path, 0755);

    memset(&group, 0, sizeof(group));
    applog = stderr;
    listener = INVALID_SOCKET;
    cache_len = DEF_CACHE;
    uid = htonl(0x0A000001);
    strncpy(destdir[0], dest, sizeof(destdir[0]) - 1);
    destdircnt = 1;
    group.version = UFTP_VER_NUM;
    group.group_id = 1;
    group.blocksize = 1300;
    group.fileinfo.fd = -1;
    if (temp) {
        snprintf(tempdir, sizeof(tempdir), "%s/tmp", base);
        mkdir(tempdir, 0755);
        snprintf(root, sizeof(root), "%s/_group_%08X", tempdir, group.group_id);
    } else {
        snprintf(root, sizeof(root), "%s", dest);
    }

    /* "up" leads from the root to <base>/outside. */
    send_fileinfo(&group, FTYPE_DIR, "a..b", NULL);
    send_fileinfo(&group, FTYPE_REG, "a..b/../../escape-dotdot", NULL);
    send_fileinfo(&group, FTYPE_LINK, "up", temp ? "../../outside" : "../outside");
    send_fileinfo(&group, FTYPE_REG, "up/sub/escape-link", NULL);
    send_fileinfo(&group, FTYPE_REG, "ok/inside", NULL);
    report("a..b", root, "a..b");
    report("ok/inside", root, "ok/inside");
    report("escape-dotdot", temp ? tempdir : base, "escape-dotdot");
    report("escape-link", base, "outside/sub/escape-link");
    if (!temp) {
        snprintf(name, sizeof(name), "%s-other/escape-prefix", dest);
        send_fileinfo(&group, FTYPE_REG, name, NULL);
        snprintf(name, sizeof(name), "%s/abs-inside", dest);
        send_fileinfo(&group, FTYPE_REG, name, NULL);
        report("abs-inside", dest, "abs-inside");
        report("escape-prefix", base, "dest-other/escape-prefix");
    }
    return 0;
}
