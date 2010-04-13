// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Get a list of defined disk pools.
 *
 * @param $1: The name of the guest to get a list of disk pools for
 *
 * @return 0 If the disk pools were successfully printed
 *         1 If given invalid parameters
 *         2 If the disk pools could not be retrieved
 */
int main(int argC, char * argV[]) {
	if (argC != 2) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* image = argV[1];

	VmApiInternalContext context;
	vmApiImageRecord * record;
	char * poolName;
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

	int rc = smImage_Volume_Space_Query_DM(&context, "", 0, "", // Authorizing user, password length, password.
			image, 1, // Query definition
			3, // Query group
			"*", // All areas
			&output);

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
			// Get disk pool name from each record
			poolName = strtok_r(record->imageRecord, " ", &context);
			if (poolName) {
				printf("%s\n", poolName);
			}
			record++;
		}

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 0;
	}
}
