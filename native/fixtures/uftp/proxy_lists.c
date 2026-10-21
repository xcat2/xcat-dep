/*
 * Prints whether each client list that the uftp proxy builds fits in its packet buffer, for the
 * largest block size and an RSA-2048 key. Built with the proxy objects by native/uftp-fixes.t.
 */
#include <stdio.h>
#include <string.h>

#include "proxy.h"
#include "proxy_common.h"

static void check(const char *name, struct pr_group_list_t *group, int func, int hlen, int size, int encrypted)
{
    int count = max_msg_dest(group, func, hlen);
    int len = (int)sizeof(struct uftp_h) + hlen + count * size;

    if (encrypted) {
        len += (int)sizeof(struct encrypted_h) + KEYBLSIZE;
    }
    printf("%s: %d entries, %s\n", name, count, (count > 0 && len <= MAXMTU) ? "fits" : "overflows");
}

int main(void)
{
    struct pr_group_list_t group;

    memset(&group, 0, sizeof(group));
    group.blocksize = 8800;
    group.keytype = KEY_AES256_GCM;
    check("KEYINFO", &group, KEYINFO, sizeof(struct keyinfo_h) + 256, sizeof(struct destkey), 0);
    check("REGISTER", &group, REGISTER, sizeof(struct register_h) + 256, sizeof(uint32_t), 1);
    check("FILEINFO_ACK", &group, FILEINFO_ACK, sizeof(struct fileinfoack_h), sizeof(uint32_t), 1);
    check("COMPLETE", &group, COMPLETE, sizeof(struct complete_h), sizeof(uint32_t), 1);
    return 0;
}
