// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Adds a 3390 (ECKD) disk that is defined in a virtual image's directory
 * entry to that virtual image's active configuration
 *
 * @param $1: The name of the guest to which a disk is to be added
 * @param $2: The virtual device address for the newly-allocated volume
 * @param $3: The mode under which the disk is to be linked by the user
 *
 * @return 0 If the disk was added successfully
 *         1 If given invalid parameters
 *         2 If disk allocation failed
 */
int main(int argC, char* argV[]) {

	if (argC != 4) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* image = argV[1];
	char* vdev = argV[2];
	char* mode = argV[3];

	// Check if the userID is between 1 and 8 characters
	if (isImageNameInvalid(image))
		return 1;

	printf("Adding disk %s to %s... ", vdev, image);

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageDiskCreateOutput * output;

	int rc = smImage_Disk_Create(&context, "", 0, "", // Authorizing user, password length, password.
			image, vdev, mode, &output);

	if (rc || output->returnCode || output->reasonCode) {
		printf("Failed\n");

		rc ? printf("  Return Code: %d\n", rc) : printf("  Return Code: %d\n"
			"  Reason Code: %d\n", output->returnCode,
				output->reasonCode);

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 2;
	} else {
		printf("Done\n");

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 0;
	}
}
