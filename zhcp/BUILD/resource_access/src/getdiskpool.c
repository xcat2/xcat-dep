// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Get the free and used space in a given disk pool.
 *
 * @param $1: The name of the guest to get the disk pool from
 * @param $2: The name of the disk pool
 * @param $2: Free or used space in the disk pool
 *
 * @return 0 If the disk pool was successfully printed
 *         1 If given invalid parameters
 *         2 If the disk pool could not be retrieved
 */
int main(int argC, char * argV[]) {
	if (argC != 4) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char * image = argV[1];
	char * pool = argV[2];
	char * spaceStr = argV[3];

	// Get the disk space
	int space;
	if (strcmp(spaceStr, "free") == 0) {
		space = 2;
	} else if (strcmp(spaceStr, "used") == 0) {
		space = 3;
	} else {
		printf("Error: Disk pool space must be free or used\n");
		return 1;
	}

	VmApiInternalContext context;
	vmApiImageRecord * record;
	char temp[1024];
	char * token;
	char diskStr[256];
	int i;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageVolumeSpaceQueryDmOutput * output;

	// Get disk pool used space
	int rc = smImage_Volume_Space_Query_DM(&context, "", 0, "", // Authorizing user, password length, password.
			image, space, // Used space
			3, // Query group
			pool, &output);

	if (rc || output->common.returnCode || output->common.reasonCode) {
		printf("Failed\n");

		rc ? printf("  Return Code: %d\n", rc) : printf("  Return Code: %d\n"
			"  Reason Code: %d\n", output->common.returnCode,
				output->common.reasonCode);

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 2;
	} else {
		record = output->recordList;
		for (i = 0; i < output->recordCount; i++) {
			strncpy(temp, record->imageRecord, record->imageRecordLength);

			token = strtok_r(temp, " ", &context); // VolId
			strcpy(diskStr, token);
			strcat(diskStr, " ");
			token = strtok_r(NULL, " ", &context); // Device type
			strcat(diskStr, token);
			strcat(diskStr, " ");
			token = strtok_r(NULL, " ", &context); // Start address
			strcat(diskStr, token);
			strcat(diskStr, " ");
			token = strtok_r(NULL, " ", &context); // Size
			strcat(diskStr, token);

			printf("%s\n", diskStr);
			record++;
		}

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 0;
	}
}
