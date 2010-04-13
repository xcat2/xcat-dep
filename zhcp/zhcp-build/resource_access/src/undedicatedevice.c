// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Removes a dedicated device from a virtual image's directory entry.
 *
 * @param $1: The name of the guest from which a device is to be removed
 * @param $2: The virtual device address assigned to the device
 *
 * @return 0 If the dedicated device was removed successfully
 *         1 If given invalid parameters
 *         2 If device undedication failed.
 */
int main(int argC, char* argV[]) {

	if (argC != 6) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	char* image = argV[1];
	char* vdev = argV[2];

	if (isImageNameInvalid(image))
		return 1;

	printf("Removing device %s on %s... ", vdev, image);

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageDeviceUndedicateDmOutput* output;

	int rc = smImage_Device_Undedicate_DM(&context, "", 0, "", // Authorizing user, password length, password.
			image, vdev, &output);

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
