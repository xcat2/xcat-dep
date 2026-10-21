/*
 * Ends a group of the uftp receiver with more top level entries in its temp directory than the
 * 10000 that move_files() had room for, then counts the entries in the destination directory.
 * Built with the receiver objects and AddressSanitizer by native/uftp-fixes.t.
 */
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "client.h"
#include "uftp_common.h"

void move_files(struct group_list_t *group);

int main(void)
{
    struct group_list_t group;
    char base[] = "/tmp/uftp-move-XXXXXX", path[MAXPATHNAME];
    int i, fd, moved = 0, entries = 10050;
    DIR *dir;
    struct dirent *de;

    if (!mkdtemp(base)) {
        perror("mkdtemp");
        return 2;
    }
    applog = stderr;
    snprintf(tempdir, sizeof(tempdir), "%s/tmp", base);
    snprintf(destdir[0], sizeof(destdir[0]), "%s/dest", base);
    destdircnt = 1;
    mkdir(tempdir, 0755);
    mkdir(destdir[0], 0755);
    memset(&group, 0, sizeof(group));
    group.group_id = 1;
    snprintf(path, sizeof(path), "%s/_group_%08X", tempdir, group.group_id);
    mkdir(path, 0755);
    for (i = 0; i < entries; i++) {
        snprintf(path, sizeof(path), "%s/_group_%08X/f%05d", tempdir, group.group_id, i);
        if ((fd = open(path, O_CREAT | O_WRONLY, 0644)) != -1) {
            close(fd);
        }
    }
    move_files(&group);
    if ((dir = opendir(destdir[0])) != NULL) {
        while ((de = readdir(dir)) != NULL) {
            moved += de->d_name[0] != '.';
        }
        closedir(dir);
    }
    printf("moved %d of %d entries\n", moved, entries);
    return 0;
}
