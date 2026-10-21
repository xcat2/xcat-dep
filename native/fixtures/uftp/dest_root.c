/*
 * Gives handle_fileinfo() of the uftp receiver delete requests and regular files whose names
 * resolve to the destination directory, and checks after each that a file in that directory
 * survives. A delete request for a file and a free space request for "." show the requests that
 * still work. Receives straight into the destination directory (-D without -T). Built with the
 * receiver objects and AddressSanitizer by native/uftp-fixes.t.
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

static char keep[MAXPATHNAME], other[MAXPATHNAME];

static void create(const char *path)
{
    int fd;

    if ((fd = open(path, O_CREAT | O_WRONLY, 0644)) != -1) {
        close(fd);
    }
}

static const char *exists(const char *path)
{
    struct stat statbuf;

    return lstat(path, &statbuf) == 0 ? "present" : "absent";
}

static void request(const char *label, int ftype, const char *name)
{
    unsigned char message[sizeof(struct fileinfo_h) + MAXPATHNAME + 8];
    struct fileinfo_h *fileinfo = (struct fileinfo_h *)message;
    struct group_list_t group;
    int namelen = (int)(strlen(name) + 4) / 4;
    struct timeval now;

    create(keep);
    create(other);
    memset(&group, 0, sizeof(group));
    group.version = UFTP_VER_NUM;
    group.group_id = 1;
    group.blocksize = 1300;
    group.phase = PHASE_MIDGROUP;
    group.fileinfo.fd = -1;
    memset(message, 0, sizeof(message));
    fileinfo->func = FILEINFO;
    fileinfo->hlen = (sizeof(struct fileinfo_h) / 4) + namelen;
    fileinfo->file_id = htons(1);
    fileinfo->ftype = ftype;
    fileinfo->namelen = namelen;
    fileinfo->lofsize = htonl(ftype == FTYPE_REG ? 2600 : 0);
    memcpy(message + sizeof(struct fileinfo_h), name, strlen(name));
    memcpy(message + (fileinfo->hlen * 4), &uid, sizeof(uid));
    gettimeofday(&now, NULL);
    handle_fileinfo(&group, message, (fileinfo->hlen * 4) + sizeof(uid), now);
    printf("%s: %s, keep %s, other %s\n", label,
           group.fileinfo.comp_status == COMP_STAT_REJECTED ? "rejected" : "accepted",
           exists(keep), exists(other));
    file_cleanup(&group, 1);
}

int main(void)
{
    char base[] = "/tmp/uftp-root-XXXXXX", name[MAXPATHNAME];

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
    snprintf(keep, sizeof(keep), "%s/keep", destdir[0]);
    snprintf(other, sizeof(other), "%s/other", destdir[0]);

    request("delete .", FTYPE_DELETE, ".");
    request("delete ./", FTYPE_DELETE, "./");
    request("delete ./.", FTYPE_DELETE, "./.");
    snprintf(name, sizeof(name), "%s/", destdir[0]);
    request("delete dest/", FTYPE_DELETE, name);
    snprintf(name, sizeof(name), "%s/.", destdir[0]);
    request("delete dest/.", FTYPE_DELETE, name);
    request("file .", FTYPE_REG, ".");
    snprintf(name, sizeof(name), "%s/./", destdir[0]);
    request("file dest/./", FTYPE_REG, name);
    request("delete other", FTYPE_DELETE, "other");
    request("free space .", FTYPE_FREESPACE, ".");
    return 0;
}
