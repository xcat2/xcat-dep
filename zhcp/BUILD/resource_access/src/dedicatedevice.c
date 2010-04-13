// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Adds a dedicated device to a virtual image's directory entry.
 *
 * @param $1: The name of the guest to which a device is to be added
 * @param $2: The virtual device address to be assigned to the device
 * @param $3: The device's real address
 *
 * @return 0 If the dedicated device was added successfully
 *         1 If given invalid parameters
 *         2 If device dedication failed
 */
int main(int argC, char* argV[]) {

	if (argC != 5) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* image = argV[1];
	char* vdev = argV[2];
	char* rdev = argV[3];
	char* mode = argV[4];

	// Check if the userID is between 1 and 8 characters
	if (isImageNameInvalid(image))
		return 1;

	int readonly;
	if (strcmp(mode, "RW") == 0 || strcmp(mode, "rw") == 0) {
		readonly = 0;
	} else if (strcmp(mode, "RO") == 0 || !strcmp(mode, "ro") == 0) {
		readonly = 1;
	} else {
		printf("Error: Mode must be in RW or RO\n");
		return 1;
	}

	printf("Adding device %s as %s to %s... ", rdev, vdev, image);

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageDeviceDedicateDmOutput* output;

	int rc = smImage_Device_Dedicate_DM(&context, "", 0, "", // Authorizing user, password length, password.
			image, vdev, rdev, readonly, &output);

	if (rc || output->returnCode || output->reasonCode) {
		printf("Failed\n");

		rc ? printf("  Return Code: %d\n", rc) : printf("  Return Code: %d\n"
			"  Reason Code: %d\n", output->returnCode, output->reasonCode);

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
