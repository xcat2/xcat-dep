// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Removes a disk from a virtual image's directory entry
 *
 * @param $1: The name of the guest from which a disk is to be removed
 * @param $2: The virtual device address of the volume which is to be removed
 *
 * @return 0 If the disk is not in the image's directory entry upon completion
 *         1 If given invalid parameters
 *         2 If the disk allocation failed
 */
int main(int argC, char* argV[]) {

	if (argC != 3) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* image = argV[1];
	char* vdev = argV[2];

	// Check if the userID is between 1 and 8 characters
	if (isImageNameInvalid(image) || isDevNumberInvalid(vdev))
		return 1;

	printf("Removing disk %s on %s... ", vdev, image);

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageDiskDeleteDmOutput* output;

	int rc = smImage_Disk_Delete_DM(&context, "", 0, "", // Authorizing user, password length, password.
			image, vdev, 0, // Use default setting for whether to erase data.
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
		printf("Done\n");

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 0;
	}
}
